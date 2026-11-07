// SPDX-License-Identifier: BSD-3-Clause-Clear
// metal_check: decode an IVF with vcndec and read every output frame's Y plane back through Metal
// (MTLCreateSystemDefaultDevice = the installed NVMTL plugin, the same path Core Animation / Chromium use).
// A frame whose Metal readback differs from the CPU view of the IOSurface is stale. Exit 1 if any.
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include "vcndec.h"
#include <stdio.h>

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: metal_check clip.ivf\n"); return 2; }
    FILE *f = fopen(argv[1], "rb"); uint8_t hdr[32];
    if (!f || fread(hdr, 1, 32, f) != 32) return 2;
    int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
    uint32_t codec = !memcmp(hdr + 8, "AV01", 4) ? 'av01' : 'vp09';
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> q = [dev newCommandQueue];
    printf("Metal device: %s\n", dev.name.UTF8String);
    char err[256]; vcn_dec *d = vcn_open(codec, w, h, NULL, 0, err, sizeof err);
    if (!d) { fprintf(stderr, "vcn_open: %s\n", err); return 1; }
    NSDictionary *pa = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                         (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h),
                         (id)kCVPixelBufferIOSurfacePropertiesKey: @{}, (id)kCVPixelBufferMetalCompatibilityKey: @YES};
    CVPixelBufferPoolRef pool; CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)pa, &pool);
    id<MTLBuffer> rb = [dev newBufferWithLength:(NSUInteger)w * h options:MTLResourceStorageModeShared];
    int reuse = getenv("MC_REUSE") != NULL, managed = getenv("MC_MANAGED") != NULL;
    NSMutableDictionary *texs = [NSMutableDictionary dictionary];
    NSMutableArray *held = [NSMutableArray array]; // keep a few frames alive like a compositor queue does
    uint8_t fh[12], *buf = malloc(8 << 20); int n = 0, stale = 0, eof = 0;
    while (!eof) {
      if (fread(fh, 1, 12, f) != 12) { eof = 1; vcn_flush(d); }
      else { uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24; fread(buf, 1, sz, f); vcn_send(d, buf, sz, n); }
      for (;;) {
        CVPixelBufferRef pb; int64_t pts; int r = vcn_receive(d, pool, &pb, &pts);
        if (r <= 0) break;
        IOSurfaceRef s = CVPixelBufferGetIOSurface(pb);
        id<MTLTexture> t = reuse ? texs[@(IOSurfaceGetID(s))] : nil;
        if (!t) {
          MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:w height:h mipmapped:NO];
          td.usage = MTLTextureUsageShaderRead; td.storageMode = managed ? MTLStorageModeManaged : MTLStorageModeShared;
          t = [dev newTextureWithDescriptor:td iosurface:s plane:0];
          if (reuse) texs[@(IOSurfaceGetID(s))] = t;
        }
        id<MTLCommandBuffer> cb = [q commandBuffer]; id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder];
        [be copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
                   toBuffer:rb destinationOffset:0 destinationBytesPerRow:w destinationBytesPerImage:(NSUInteger)w * h];
        [be endEncoding]; [cb commit]; [cb waitUntilCompleted];
        IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
        const uint8_t *y = IOSurfaceGetBaseAddressOfPlane(s, 0); size_t bpr = IOSurfaceGetBytesPerRowOfPlane(s, 0);
        int bad = 0; for (int row = 0; row < h && !bad; row++) bad = memcmp(y + row * bpr, (uint8_t *)rb.contents + (size_t)row * w, w) != 0;
        IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
        if (bad) { if (stale++ < 5) printf("frame %d: Metal view differs from the surface (surface %u seed %u)\n", n, IOSurfaceGetID(s), IOSurfaceGetSeed(s)); }
        [held addObject:(__bridge_transfer id)pb]; if (held.count > 4) [held removeObjectAtIndex:0];
        n++;
      }
    }
    printf("%d frames, %d stale through Metal\n", n, stale);
    vcn_close(d);
    return stale ? 1 : 0;
  }
}
