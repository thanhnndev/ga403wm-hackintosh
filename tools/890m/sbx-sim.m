// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// sbx-sim: apply a sandbox profile to this process the way WebKit's GPU process does (in-process, after dyld), then
// create the Metal device and run ONE bounded render job (64x64 triangle, MSL source compiled at runtime like ANGLE,
// command buffer polled for at most 5 s, never waitUntilCompleted). Used to find what the NVMTL plugin hits inside
// com.apple.WebKit.GPUProcess.sb once the file-map-executable deny is gone, without a reboot.
//
//   clang -fobjc-arc -O1 -framework Foundation -framework Metal -o build/sbx-sim tools/890m/sbx-sim.m
//   build/sbx-sim PROFILE.sb [KEY=VALUE ...]     (profile params, e.g. CPU=x86_64 HOME_DIR=$HOME ...)
//   build/sbx-sim --none                         (same job, no sandbox: control run)
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int sandbox_init_with_parameters(const char *profile, uint64_t flags, const char *const parameters[], char **errorbuf);
void sandbox_free_error(char *errorbuf);

static NSString *const kShader =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "struct V { float4 p [[position]]; };\n"
     "vertex V vs(uint i [[vertex_id]]) { float2 q[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };"
     " V o; o.p = float4(q[i], 0, 1); return o; }\n"
     "fragment float4 fs(V in [[stage_in]]) { return float4(0, 1, 0, 1); }\n";

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: sbx-sim PROFILE.sb [KEY=VALUE ...] | --none\n"); return 2; }
        setvbuf(stdout, NULL, _IONBF, 0);
        // The real GPU process has libdispatch's workqueue and its main bundle up before it enters the sandbox
        // (the profile filters syscall-unix, workq_open is not on its list).
        dispatch_semaphore_t warm = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ dispatch_semaphore_signal(warm); });
        dispatch_semaphore_wait(warm, DISPATCH_TIME_FOREVER);
        (void)[NSBundle mainBundle].infoDictionary;
        if (strcmp(argv[1], "--none") != 0) {
            NSString *profile = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
            if (!profile) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
            const char *params[64]; int n = 0;
            for (int i = 2; i < argc && n < 62; i++) {
                char *eq = strchr(argv[i], '=');
                if (!eq) continue;
                *eq = 0; params[n++] = argv[i]; params[n++] = eq + 1;
            }
            params[n] = NULL;
            char *err = NULL;
            if (sandbox_init_with_parameters(profile.UTF8String, 0, params, &err) != 0) {
                fprintf(stderr, "sandbox_init_with_parameters: %s\n", err ? err : "?"); return 2;
            }
            printf("sandbox: applied %s (pid %d)\n", argv[1], getpid());
        }
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        if (!dev) { printf("device: none\n"); return 1; }
        printf("device: %s\n", dev.name.UTF8String);
        NSError *e = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:kShader options:nil error:&e];
        if (!lib) { printf("library: FAILED %s\n", e.localizedDescription.UTF8String); return 1; }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vs"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fs"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        id<MTLRenderPipelineState> ps = [dev newRenderPipelineStateWithDescriptor:pd error:&e];
        if (!ps) { printf("pipeline: FAILED %s\n", e.localizedDescription.UTF8String); return 1; }
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                      width:64 height:64 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModeManaged;
        id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
        id<MTLCommandQueue> q = [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [q commandBuffer];
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = tex; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1); rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
        [enc setRenderPipelineState:ps];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
        id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
        [bl synchronizeResource:tex];
        [bl endEncoding];
        [cb commit];
        for (int i = 0; i < 500 && cb.status < MTLCommandBufferStatusCompleted; i++) usleep(10000);
        if (cb.status != MTLCommandBufferStatusCompleted) { printf("job: status %ld after 5 s\n", (long)cb.status); return 1; }
        uint8_t px[4] = { 0 };
        [tex getBytes:px bytesPerRow:64 * 4 fromRegion:MTLRegionMake2D(32, 32, 1, 1) mipmapLevel:0];
        printf("job: completed, pixel %u %u %u %u -> %s\n", px[0], px[1], px[2], px[3],
               (px[0] == 0 && px[1] == 255 && px[2] == 0) ? "PASS" : "WRONG");
        return (px[0] == 0 && px[1] == 255 && px[2] == 0) ? 0 : 1;
    }
}
