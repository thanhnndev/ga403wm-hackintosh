// ushort-offset.m: Metal compute test for a ushort buffer argument bound at a byte offset that is 2 mod 4
// (what ANGLE's fixIndexBuffer kernel gets for a GL_UNSIGNED_SHORT draw at an unaligned element offset).
// Build: xcrun clang -fobjc-arc -o ushort-offset ushort-offset.m -framework Metal -framework Foundation
// Prints PASS/FAIL per offset. Runs on the default Metal device (the 890M through the NVMTL plugin).
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
 "kernel void copy16(device const ushort *in [[buffer(0)]], device ushort *out16 [[buffer(1)]], device uint *out32 [[buffer(2)]], constant uint &n [[buffer(3)]], uint i [[thread_position_in_grid]]) {\n"
 "  if (i >= n) return; ushort v = in[i]; out16[i] = v; out32[i] = v; }\n"
 "kernel void copy8(device const uchar *in [[buffer(0)]], device uchar *out [[buffer(1)]], constant uint &n [[buffer(2)]], uint i [[thread_position_in_grid]]) {\n"
 "  if (i >= n) return; out[i] = in[i]; }\n";
int main(void) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); printf("device: %s\n", dev.name.UTF8String);
  NSError *err = nil; id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err]; if (!lib) { printf("compile: %s\n", err.description.UTF8String); return 1; }
  id<MTLComputePipelineState> p16 = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"copy16"] error:&err];
  id<MTLComputePipelineState> p8 = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"copy8"] error:&err];
  if (!p16 || !p8) { printf("pipeline: %s\n", err.description.UTF8String); return 1; }
  id<MTLCommandQueue> q = [dev newCommandQueue];
  const uint N = 64; id<MTLBuffer> in = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
  uint16_t *ip = in.contents; for (uint k = 0; k < 2048; k++) ip[k] = (uint16_t)(1000 + k);
  int fails = 0;
  for (NSUInteger off = 0; off <= 10; off += 2) for (int kind = 0; kind < 2; kind++) {
    id<MTLBuffer> o16 = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared], o32 = [dev newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    memset(o16.contents, 0xee, 4096); memset(o32.contents, 0xee, 4096);
    id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
    uint n = kind ? N * 2 : N;
    [e setComputePipelineState:kind ? p8 : p16]; [e setBuffer:in offset:off atIndex:0]; [e setBuffer:o16 offset:0 atIndex:1];
    if (!kind) { [e setBuffer:o32 offset:0 atIndex:2]; [e setBytes:&n length:4 atIndex:3]; } else [e setBytes:&n length:4 atIndex:2];
    [e dispatchThreads:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(32, 1, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
    int bad = 0; char first[160] = "";
    for (uint k = 0; k < N; k++) { uint16_t want = (uint16_t)(1000 + off / 2 + k);
      uint16_t got = ((uint16_t *)o16.contents)[k]; uint32_t got32 = kind ? want : ((uint32_t *)o32.contents)[k];
      if (got != want || got32 != want) { if (!bad) snprintf(first, sizeof first, "[%u] got %u/%u want %u", k, got, got32, want); bad++; } }
    printf("%s %s offset %2lu (mod 4 = %lu): %s%s\n", bad ? "FAIL" : "PASS", kind ? "uchar " : "ushort", (unsigned long)off, (unsigned long)(off % 4), bad ? "" : "ok", first);
    fails += bad != 0;
  }
  printf("%d failing\n", fails); return fails ? 2 : 0;
} }
