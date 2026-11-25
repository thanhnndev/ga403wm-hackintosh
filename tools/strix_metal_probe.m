// SPDX-License-Identifier: BSD-3-Clause-Clear
// Public Metal end-to-end oracle. Select890M by PCI ancestry, never GPU name.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include "../include/StrixNativeABI.h"

static uint32_t pciProperty(io_registry_entry_t entry, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0);
    uint32_t result = 0xffffffff;
    if (value && CFGetTypeID(value) == CFDataGetTypeID() && CFDataGetLength(value) == 4) {
        const UInt8 *b = CFDataGetBytePtr(value);
        result = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    }
    if (value) CFRelease(value);
    return result;
}

static NSDictionary *identity(id<MTLDevice> device) {
    uint64_t registry = device.registryID;
    io_registry_entry_t e = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registry));
    uint32_t vendor = 0xffffffff, product = 0xffffffff;
    for (unsigned i = 0; e && i < 32; ++i) {
        vendor = pciProperty(e, CFSTR("vendor-id")); product = pciProperty(e, CFSTR("device-id"));
        if (vendor != 0xffffffff && product != 0xffffffff) break;
        io_registry_entry_t parent = IO_OBJECT_NULL;
        kern_return_t kr = IORegistryEntryGetParentEntry(e, kIOServicePlane, &parent);
        IOObjectRelease(e); e = kr == KERN_SUCCESS ? parent : IO_OBJECT_NULL;
    }
    if (e) IOObjectRelease(e);
    return @{ @"name": device.name ?: @"", @"registry_id": [NSString stringWithFormat:@"0x%llx", (unsigned long long)registry],
              @"pci_vendor": @(vendor), @"pci_device": @(product),
              @"is_890m": vendor == 0x1002 && product == 0x150e ? @YES : @NO,
              @"headless": @(device.headless), @"low_power": @(device.lowPower) };
}

static BOOL nativeReady(id<MTLDevice> device, NSMutableDictionary *report) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(device.registryID));
    if (!service) { report[@"failed_stage"] = @"native_service_identity"; return NO; }
    CFTypeRef major = IORegistryEntryCreateCFProperty(service, CFSTR("StrixNative,ABIMajor"), kCFAllocatorDefault, 0);
    int abi = 0;
    if (major && CFGetTypeID(major) == CFNumberGetTypeID()) CFNumberGetValue(major, kCFNumberIntType, &abi);
    if (major) CFRelease(major);
    if (abi != S89N_ABI_MAJOR) { IOObjectRelease(service); report[@"failed_stage"] = @"native_abi_not_advertised"; return NO; }
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), S89N_UC_TYPE, &connection);
    IOObjectRelease(service);
    if (kr) { report[@"failed_stage"] = @"native_open"; report[@"native_error"] = @(kr); return NO; }
    s89n_hello_request request = {S89N_ABI_MAJOR, S89N_ABI_MINOR, {0, 0}};
    s89n_hello_reply reply; size_t size = sizeof(reply);
    kr = IOConnectCallStructMethod(connection, S89N_HELLO, &request, sizeof(request), &reply, &size);
    s89n_info info = {0};
    if (!kr && size == sizeof(reply) && reply.magic == S89N_MAGIC && reply.major == S89N_ABI_MAJOR && !reply.reserved) {
        size = sizeof(info); kr = IOConnectCallStructMethod(connection, S89N_QUERY_INFO, NULL, 0, &info, &size);
    } else if (!kr) kr = kIOReturnBadArgument;
    IOServiceClose(connection);
    if (kr || size != sizeof(info) || !s89n_metal_ready(&info) || info.accelerator_registry_id != device.registryID) {
        report[@"failed_stage"] = @"native_backend_not_ready";
        report[@"native_capabilities"] = @(info.capabilities); report[@"native_readiness"] = @(info.readiness);
        report[@"native_error"] = @(kr); return NO;
    }
    report[@"native_backend_ready"] = @YES; return YES;
}

static BOOL complete(id<MTLCommandBuffer> buffer, NSMutableDictionary *report, NSString *stage) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> unused) { (void)unused; dispatch_semaphore_signal(semaphore); }];
    [buffer commit];
    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
        report[@"failed_stage"] = stage; report[@"error"] = @"GPU completion timeout (5s)"; return NO;
    }
    if (buffer.status != MTLCommandBufferStatusCompleted || buffer.error) {
        report[@"failed_stage"] = stage;
        report[@"error"] = buffer.error.localizedDescription ?: @"Command buffer did not complete";
        return NO;
    }
    return YES;
}

static BOOL exercise(id<MTLDevice> device, NSMutableDictionary *report) {
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void verify(device uint *v [[buffer(0)]], uint i [[thread_position_in_grid]]) { "
        "v[i] = (v[i] * 1664525u + 1013904223u) ^ i; }\n"
        "vertex float4 triangle(uint i [[vertex_id]]) { const float2 p[3] = {"
        "float2(-0.7,-0.7),float2(0.7,-0.7),float2(0,0.7)}; return float4(p[i],0,1); }\n"
        "fragment float4 red() { return float4(1,0,0,1); }\n";
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (!library) { report[@"failed_stage"] = @"compile_msl"; report[@"error"] = error.localizedDescription ?: @"No library"; return NO; }
    id<MTLFunction> function = [library newFunctionWithName:@"verify"];
    id<MTLComputePipelineState> pipeline = function ? [device newComputePipelineStateWithFunction:function error:&error] : nil;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    const NSUInteger count = 1024;
    id<MTLBuffer> values = [device newBufferWithLength:count * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    if (!pipeline || !queue || !values || !values.contents) {
        report[@"failed_stage"] = @"compute_setup"; report[@"error"] = error.localizedDescription ?: @"Missing queue/pipeline/shared buffer"; return NO;
    }
    uint32_t expected[1024]; uint32_t *cpu = values.contents;
    for (NSUInteger i = 0; i < count; ++i) cpu[i] = expected[i] = (uint32_t)i + 17;
    for (NSUInteger round = 0; round < 3; ++round) {
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [cb computeCommandEncoder];
        if (!cb || !encoder || !pipeline.maxTotalThreadsPerThreadgroup) {
            report[@"failed_stage"] = @"compute_encode"; report[@"error"] = @"Missing encoder or invalid threadgroup limit"; return NO;
        }
        [encoder setComputePipelineState:pipeline]; [encoder setBuffer:values offset:0 atIndex:0];
        NSUInteger threads = MIN((NSUInteger)64, pipeline.maxTotalThreadsPerThreadgroup);
        [encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads, 1, 1)];
        [encoder endEncoding];
        if (!complete(cb, report, @"compute_submit")) return NO;
        for (NSUInteger i = 0; i < count; ++i) {
            expected[i] = (expected[i] * 1664525u + 1013904223u) ^ (uint32_t)i;
            if (cpu[i] != expected[i]) {
                report[@"failed_stage"] = @"compute_readback"; report[@"mismatch_index"] = @(i); return NO;
            }
        }
    }
    report[@"compute"] = @{ @"status": @"PASS", @"submissions": @3, @"validated_words_per_submission": @(count) };
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"triangle"]; pd.fragmentFunction = [library newFunctionWithName:@"red"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> render = [device newRenderPipelineStateWithDescriptor:pd error:&error];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:32 height:32 mipmapped:NO];
    td.storageMode = MTLStorageModePrivate; td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [device newTextureWithDescriptor:td];
    id<MTLBuffer> readback = [device newBufferWithLength:256 * 32 options:MTLResourceStorageModeShared];
    if (!render || !texture || !readback || !readback.contents) {
        report[@"failed_stage"] = @"render_setup"; report[@"error"] = error.localizedDescription ?: @"Missing render objects"; return NO;
    }
    memset(readback.contents, 0x5a, readback.length);
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture; pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore; pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
    id<MTLCommandBuffer> cb = [queue commandBuffer]; id<MTLRenderCommandEncoder> encoder = [cb renderCommandEncoderWithDescriptor:pass];
    if (!cb || !encoder) { report[@"failed_stage"] = @"render_encode"; return NO; }
    [encoder setRenderPipelineState:render]; [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [encoder endEncoding];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (!blit) { report[@"failed_stage"] = @"blit_encode"; return NO; }
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(32, 32, 1)
                toBuffer:readback destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:256 * 32];
    [blit endEncoding]; if (!complete(cb, report, @"render_submit")) return NO;
    uint8_t *bytes = readback.contents; uint8_t *center = bytes + 16 * 256 + 16 * 4;
    if (memcmp(center, (uint8_t[]){255, 0, 0, 255}, 4) || memcmp(bytes, (uint8_t[]){0, 0, 255, 255}, 4)) {
        report[@"failed_stage"] = @"render_readback";
        report[@"center_rgba"] = @[@(center[0]), @(center[1]), @(center[2]), @(center[3])];
        report[@"corner_rgba"] = @[@(bytes[0]), @(bytes[1]), @(bytes[2]), @(bytes[3])]; return NO;
    }
    report[@"render"] = @{ @"status": @"PASS", @"size": @[@32, @32], @"triangle_and_clear_readback_validated": @YES };
    return YES;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL listOnly = NO; uint64_t control = 0;
        for (int i = 1; i < argc; ++i) {
            if (!strcmp(argv[i], "--list-only")) listOnly = YES;
            else if (!strcmp(argv[i], "--control-registry-id") && i + 1 < argc) {
                char *end = NULL; control = strtoull(argv[++i], &end, 0);
                if (!control || !end || *end) { fprintf(stderr, "Invalid registry ID\n"); return 2; }
            } else { fprintf(stderr, "Usage: strix-metal-probe [--list-only | --control-registry-id ID]\n"); return 2; }
        }
        NSMutableDictionary *report = [@{ @"schema": @1, @"target": @"PCI1002:150e", @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
                                          @"purpose": control ? @"explicit_non_target_control" : @"890m_validation", @"hardware_890m_pass": @NO } mutableCopy];
        int result = 10;
        @try {
            NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices(); NSMutableArray *identities = [NSMutableArray array];
            NSMutableArray<id<MTLDevice>> *targets = [NSMutableArray array];
            for (id<MTLDevice> device in devices) {
                NSDictionary *info = identity(device); [identities addObject:info];
                if (control ? device.registryID == control : [info[@"is_890m"] boolValue]) [targets addObject:device];
            }
            report[@"devices"] = identities;
            if (listOnly) { report[@"status"] = @"ENUMERATED-not-a-hardware-pass"; result = 0; }
            else if (targets.count != 1) { report[@"status"] = targets.count ? @"AMBIGUOUS-target" : @"ABSENT-target-Metal-device"; }
            else {
                report[@"selected"] = identity(targets[0]);
                BOOL passed = (control || nativeReady(targets[0], report)) && exercise(targets[0], report);
                report[@"status"] = passed ? (control ? @"PASS-control-only" : @"PASS-890m-compute-render") : @"FAILED-Metal-validation";
                report[@"hardware_890m_pass"] = passed && !control ? @YES : @NO;
                result = passed ? 0 : 1;
            }
        } @catch (NSException *e) { report[@"status"] = @"FAILED-ObjectiveC-exception"; report[@"error"] = e.reason ?: e.name; result = 1; }
        NSError *jsonError = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&jsonError];
        if (!data) { fprintf(stderr, "JSON error: %s\n", jsonError.localizedDescription.UTF8String); return 1; }
        fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); return result;
    }
}
