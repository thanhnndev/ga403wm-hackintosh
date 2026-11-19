// offset-matrix.m: which compute buffer-argument byte offsets read correctly through the plugin.
// Kernels read element i of a buffer bound with setBuffer:offset: and write it to an output at offset 0.
// Build: xcrun clang -fobjc-arc -o offset-matrix offset-matrix.m -framework Metal -framework Foundation
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
static NSString *src = @"#include <metal_stdlib>\nusing namespace metal;\n"
 "kernel void r16c(device const ushort *in [[buffer(0)]], device uint *out [[buffer(1)]], uint i [[thread_position_in_grid]]) { out[i] = in[i]; }\n"
 "kernel void r16w(device ushort *in [[buffer(0)]], device uint *out [[buffer(1)]], uint i [[thread_position_in_grid]]) { out[i] = in[i]; }\n"
 "kernel void r32c(device const uint *in [[buffer(0)]], device uint *out [[buffer(1)]], uint i [[thread_position_in_grid]]) { out[i] = in[i] & 0xffffu; }\n"
 "kernel void r16k(constant ushort *in [[buffer(0)]], device uint *out [[buffer(1)]], uint i [[thread_position_in_grid]]) { out[i] = in[i]; }\n";
int main(int argc, char **argv) { @autoreleasepool {
  id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); printf("device: %s\n", dev.name.UTF8String);
  NSError *err = nil; id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err]; if (!lib) { printf("%s\n", err.description.UTF8String); return 1; }
  id<MTLCommandQueue> q = [dev newCommandQueue];
  const NSUInteger LEN = 65536; id<MTLBuffer> in = [dev newBufferWithLength:LEN options:MTLResourceStorageModeShared];
  uint16_t *ip = in.contents; for (uint k = 0; k < LEN / 2; k++) ip[k] = (uint16_t)k;
  NSUInteger offs[] = { 0, 2, 4, 8, 16, 64, 256, 438, 512, 4096, 32768 }; const char *ks[] = { "r16c", "r16w", "r32c", "r16k" }; int fails = 0;
  for (int ki = 0; ki < 4; ki++) {
    id<MTLComputePipelineState> p = [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@(ks[ki])] error:&err];
    printf("%-5s", ks[ki]);
    for (int oi = 0; oi < 11; oi++) { NSUInteger off = offs[oi]; if (ki == 2 && off % 4) { printf("    -   "); continue; }
      id<MTLBuffer> o = [dev newBufferWithLength:256 * 4 options:MTLResourceStorageModeShared]; memset(o.contents, 0xee, 1024);
      id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
      [e setComputePipelineState:p]; [e setBuffer:in offset:off atIndex:0]; [e setBuffer:o offset:0 atIndex:1];
      [e dispatchThreads:MTLSizeMake(64, 1, 1) threadsPerThreadgroup:MTLSizeMake(64, 1, 1)]; [e endEncoding]; [cb commit]; [cb waitUntilCompleted];
      uint32_t *op = o.contents; int bad = 0; uint32_t g0 = op[0];
      for (uint k = 0; k < 64; k++) { uint32_t want = ki == 2 ? (uint32_t)(off / 2 + 2 * k) : (uint32_t)(off / 2 + k); if (op[k] != want) bad++; }
      printf(" %s@%-5lu", bad ? "BAD" : "ok ", (unsigned long)off); if (bad) printf("(got %u,%u want %u)", g0, op[1], ki == 2 ? (uint32_t)(off / 2) : (uint32_t)(off / 2)); fails += bad != 0; }
    printf("\n");
  }
  printf("%d failing\n", fails); return fails ? 2 : 0;
} }
