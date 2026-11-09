// inuse_test: how long WindowServer keeps an IOSurface "in use" after a layer stops showing it.
//
// Chrome's compositor on macOS reuses a back buffer only once IOSurfaceIsInUse() is false (the window server has let
// go of it); otherwise it allocates another. This tool does the same thing Chrome does: a window whose CALayer gets a
// new IOSurface as contents every frame (60 Hz), from a pool that grows whenever every surface is still in use. It
// reports the pool size and how long each surface stays in use after it was replaced.
//
// usage: inuse_test [seconds=10] [width=2816] [height=1472] [metal=0]
//   metal 1: clear each surface on the GPU through a cached MTLTexture (like Chrome/ANGLE) instead of writing it on the CPU
//   metal 2: same, but a new MTLTexture per frame
// build: tools/890m/inuse-test/build.sh
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#include <mach/mach_time.h>

static double now_ms(void) {
    static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

@interface Probe : NSObject
@property NSWindow *win; @property CALayer *layer; @property NSMutableArray *pool; @property NSMutableArray *releasedAt;
@property int w, h, frames, allocs, shown, metal; @property id<MTLDevice> dev; @property id<MTLCommandQueue> q;
@property NSMutableArray *tex; @property double gpuMs; @property double start, secs; @property NSMutableArray<NSNumber *> *busyMs;
@end

@implementation Probe
- (IOSurfaceRef)newSurface {
    NSDictionary *p = @{(id)kIOSurfaceWidth: @(_w), (id)kIOSurfaceHeight: @(_h), (id)kIOSurfaceBytesPerElement: @4,
                        (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA')};
    _allocs++;
    return IOSurfaceCreate((__bridge CFDictionaryRef)p);
}
- (void)tick:(NSTimer *)t {
    double n = now_ms();
    // releasedAt[i] < 0: the surface is on screen or never shown; else the time it was replaced
    for (NSUInteger i = 0; i < _pool.count; i++) {
        double r = [_releasedAt[i] doubleValue];
        if (r > 0 && !IOSurfaceIsInUse((__bridge IOSurfaceRef)_pool[i])) { [_busyMs addObject:@(n - r)]; _releasedAt[i] = @(0); }
    }
    // pick a surface that is not in use and not on screen (Chrome's rule), else allocate one
    NSInteger pick = -1;
    for (NSUInteger i = 0; i < _pool.count; i++)
        if ((NSInteger)i != _shown && [_releasedAt[i] doubleValue] == 0 && !IOSurfaceIsInUse((__bridge IOSurfaceRef)_pool[i])) { pick = i; break; }
    if (pick < 0) { IOSurfaceRef s = [self newSurface]; [_pool addObject:(__bridge_transfer id)s]; [_releasedAt addObject:@(0)]; pick = _pool.count - 1; }
    IOSurfaceRef s = (__bridge IOSurfaceRef)_pool[pick];
    if (_metal) {
        while (_tex.count < _pool.count) [_tex addObject:[NSNull null]];
        id<MTLTexture> t = _tex[pick] == [NSNull null] ? nil : _tex[pick];
        if (!t || _metal == 2) {
            MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:_w height:_h mipmapped:NO];
            d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead; d.storageMode = MTLStorageModeManaged;
            t = [_dev newTextureWithDescriptor:d iosurface:s plane:0]; _tex[pick] = t;
        }
        MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
        rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
        rp.colorAttachments[0].storeAction = MTLStoreActionStore;
        rp.colorAttachments[0].clearColor = MTLClearColorMake((_frames % 60) / 60.0, 0.3, 0.6, 1);
        id<MTLCommandBuffer> cb = [_q commandBuffer];
        [[cb renderCommandEncoderWithDescriptor:rp] endEncoding];
        double g0 = now_ms(); [cb commit]; [cb waitUntilScheduled]; _gpuMs += now_ms() - g0;
    } else {
        IOSurfaceLock(s, 0, NULL);
        uint32_t *px = IOSurfaceGetBaseAddress(s); size_t bpr = IOSurfaceGetBytesPerRow(s);
        uint32_t c = 0xff000000u | (uint32_t)(_frames * 2654435761u >> 8);
        for (int y = 0; y < 8; y++) for (int x = 0; x < _w; x++) ((uint32_t *)((char *)px + y * bpr))[x] = c;   // touch a strip
        IOSurfaceUnlock(s, 0, NULL);
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _layer.contents = (__bridge id)s;
    [CATransaction commit];
    if (_shown >= 0 && _shown != pick) _releasedAt[_shown] = @(n);
    _shown = (int)pick; _frames++;
    if (n - _start > _secs * 1000) {
        [t invalidate];
        NSArray *b = [_busyMs sortedArrayUsingSelector:@selector(compare:)];
        double p50 = b.count ? [b[b.count / 2] doubleValue] : -1, p90 = b.count ? [b[b.count * 9 / 10] doubleValue] : -1,
               mx = b.count ? [b.lastObject doubleValue] : -1;
        printf("frames %d in %.1f s, pool %lu surfaces (%d allocated), in-use after replace: n %lu p50 %.1f ms p90 %.1f ms max %.1f ms, schedule wait avg %.2f ms\n",
               _frames, (n - _start) / 1000, (unsigned long)_pool.count, _allocs, (unsigned long)b.count, p50, p90, mx, _gpuMs / (_frames ? _frames : 1));
        fflush(stdout);
        [NSApp terminate:nil];
    }
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        Probe *p = [Probe new];
        p.secs = argc > 1 ? atof(argv[1]) : 10; p.w = argc > 2 ? atoi(argv[2]) : 2816; p.h = argc > 3 ? atoi(argv[3]) : 1472;
        p.metal = argc > 4 ? atoi(argv[4]) : 0; p.dev = MTLCreateSystemDefaultDevice(); p.q = [p.dev newCommandQueue]; p.tex = [NSMutableArray new];
        p.pool = [NSMutableArray new]; p.releasedAt = [NSMutableArray new]; p.busyMs = [NSMutableArray new]; p.shown = -1;
        NSRect r = NSMakeRect(80, 80, p.w / 2.0, p.h / 2.0);   // points; the backing is 2x on the OLED
        p.win = [[NSWindow alloc] initWithContentRect:r styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        p.win.title = @"inuse_test";
        NSView *v = p.win.contentView; v.wantsLayer = YES;
        p.layer = [CALayer layer]; p.layer.frame = v.bounds; p.layer.contentsGravity = kCAGravityResize;
        [v.layer addSublayer:p.layer];
        [p.win makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        p.start = now_ms();
        [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 target:p selector:@selector(tick:) userInfo:nil repeats:YES];
        [app run];
    }
    return 0;
}
