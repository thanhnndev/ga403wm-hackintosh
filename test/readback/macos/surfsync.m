// Hardware correctness checks and a transfer microbenchmark for IOSurface <-> Metal on the NullMoth driver.
// NOT RUN YET: written in a cloud session without a Mac. Build it on the machine, read the output yourself, and
// do not treat a PASS here as proof about WindowServer.
//
//   clang -fobjc-arc -O1 -framework Foundation -framework Metal -framework IOSurface test/readback/macos/surfsync.m -o /tmp/surfsync
//   /tmp/surfsync check                         correctness; exit status 1 if any check fails
//   NVMTL_NO_SURFACE_SHARE=1 /tmp/surfsync check    same checks through the private-image + copy path (the fallback)
//   NVMTL_NO_SURFACE_PAGEOFF=1 /tmp/surfsync check  shared VRAM but eager copy-out after every GPU write
//   /tmp/surfsync bench [seconds-per-case]      transfer microbenchmark (ms per operation, process CPU ms per operation)
//
// The benchmark times single operations on synthetic surfaces. It says nothing about WindowServer CPU: measure that with the
// same visible workload before and after (scripts/macos-ws-readback-collect.sh).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
extern char **environ;

static id<MTLDevice> gDev;
static id<MTLCommandQueue> gQ;
static int gFail, gPass;

static uint32_t pat(uint32_t seed, uint32_t x, uint32_t y) { return (seed * 0x9E3779B1u) ^ (y * 0x01000193u + x * 0x85EBCA6Bu) ^ 0x00112233u; }
static double nowms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static double cpums(void) { struct rusage r; getrusage(RUSAGE_SELF, &r); return (r.ru_utime.tv_sec + r.ru_stime.tv_sec) * 1e3 + (r.ru_utime.tv_usec + r.ru_stime.tv_usec) / 1e3; }
static void report(BOOL ok, NSString *name, NSString *detail) {
    if (ok) gPass++; else gFail++;
    printf("%s %s%s%s\n", ok ? "PASS" : "FAIL", name.UTF8String, detail.length ? "  " : "", detail.UTF8String);
}

static IOSurfaceRef makeSurface(uint32_t w, uint32_t h, uint32_t row, BOOL global) {
    NSMutableDictionary *d = [@{ (id)kIOSurfaceWidth: @(w), (id)kIOSurfaceHeight: @(h), (id)kIOSurfaceBytesPerElement: @4,
                                 (id)kIOSurfacePixelFormat: @(0x42475241u) } mutableCopy];   // 'BGRA'
    if (row) d[(id)kIOSurfaceBytesPerRow] = @(row);
    if (global) d[@"IOSurfaceIsGlobal"] = @YES;       // lets a child process IOSurfaceLookup() it
    return IOSurfaceCreate((__bridge CFDictionaryRef)d);
}
static id<MTLTexture> makeTex(IOSurfaceRef s, MTLPixelFormat fmt, NSUInteger plane, uint32_t w, uint32_t h) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt width:w height:h mipmapped:NO];
    d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    return [gDev newTextureWithDescriptor:d iosurface:s plane:plane];
}
// CPU side -------------------------------------------------------------------------------------------------------------
static void cpuFill(IOSurfaceRef s, uint32_t w, uint32_t h, uint32_t seed, uint32_t x0, uint32_t y0, uint32_t cw, uint32_t ch) {
    IOSurfaceLock(s, 0, NULL);
    uint8_t *base = IOSurfaceGetBaseAddress(s); size_t row = IOSurfaceGetBytesPerRow(s);
    for (uint32_t y = y0; y < y0 + ch && y < h; y++) {
        uint32_t *p = (uint32_t *)(base + y * row);
        for (uint32_t x = x0; x < x0 + cw && x < w; x++) p[x] = pat(seed, x, y);
    }
    IOSurfaceUnlock(s, 0, NULL);
}
static void padFill(IOSurfaceRef s, uint32_t w, uint32_t h) {          // sentinel in the row padding
    IOSurfaceLock(s, 0, NULL);
    uint8_t *base = IOSurfaceGetBaseAddress(s); size_t row = IOSurfaceGetBytesPerRow(s);
    for (uint32_t y = 0; y < h; y++) memset(base + y * row + (size_t)w * 4, 0xA5, row - (size_t)w * 4);
    IOSurfaceUnlock(s, 0, NULL);
}
static BOOL padIntact(IOSurfaceRef s, uint32_t w, uint32_t h) {
    IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
    const uint8_t *base = IOSurfaceGetBaseAddress(s); size_t row = IOSurfaceGetBytesPerRow(s); BOOL ok = YES;
    for (uint32_t y = 0; y < h && ok; y++) for (size_t x = (size_t)w * 4; x < row; x++) if (base[y * row + x] != 0xA5) { ok = NO; break; }
    IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
    return ok;
}
// returns the number of wrong pixels in the rectangle (all pixels when cw == 0); -1 for "constant colour expected" via cfix
static long cpuCheck(IOSurfaceRef s, uint32_t w, uint32_t h, uint32_t seed, uint32_t cfix, BOOL useConst, NSString **first) {
    IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
    const uint8_t *base = IOSurfaceGetBaseAddress(s); size_t row = IOSurfaceGetBytesPerRow(s); long bad = 0;
    for (uint32_t y = 0; y < h; y++) {
        const uint32_t *p = (const uint32_t *)(base + y * row);
        for (uint32_t x = 0; x < w; x++) {
            uint32_t want = useConst ? cfix : pat(seed, x, y);
            if (p[x] != want) { if (!bad && first) *first = [NSString stringWithFormat:@"first bad pixel (%u,%u) got %08x want %08x", x, y, p[x], want]; bad++; }
        }
    }
    IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
    return bad;
}
// GPU side -------------------------------------------------------------------------------------------------------------
static BOOL waitDone(id<MTLCommandBuffer> cb) { [cb commit]; [cb waitUntilCompleted]; return cb.status == MTLCommandBufferStatusCompleted; }
static BOOL gpuBlitWrite(id<MTLTexture> t, uint32_t w, uint32_t h, uint32_t seed) {          // buffer -> texture
    id<MTLBuffer> b = [gDev newBufferWithLength:(NSUInteger)w * h * 4 options:MTLResourceStorageModeShared];
    uint32_t *p = b.contents; for (uint32_t y = 0; y < h; y++) for (uint32_t x = 0; x < w; x++) p[(size_t)y * w + x] = pat(seed, x, y);
    id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromBuffer:b sourceOffset:0 sourceBytesPerRow:(NSUInteger)w * 4 sourceBytesPerImage:(NSUInteger)w * h * 4 sourceSize:MTLSizeMake(w, h, 1)
            toTexture:t destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [e endEncoding];
    return waitDone(cb);
}
static BOOL gpuClear(id<MTLTexture> t, double r, double g, double b, double a) {              // render pass, load action clear
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = t; rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].storeAction = MTLStoreActionStore; rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, a);
    id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
    [e endEncoding];
    return waitDone(cb);
}
static long gpuReadCheck(id<MTLTexture> t, uint32_t w, uint32_t h, uint32_t seed, NSString **first) {   // texture -> buffer -> compare
    id<MTLBuffer> b = [gDev newBufferWithLength:(NSUInteger)w * h * 4 options:MTLResourceStorageModeShared]; memset(b.contents, 0xEE, b.length);
    id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1)
              toBuffer:b destinationOffset:0 destinationBytesPerRow:(NSUInteger)w * 4 destinationBytesPerImage:(NSUInteger)w * h * 4];
    [e endEncoding];
    if (!waitDone(cb)) { if (first) *first = @"command buffer failed"; return -1; }
    const uint32_t *p = b.contents; long bad = 0;
    for (uint32_t y = 0; y < h; y++) for (uint32_t x = 0; x < w; x++)
        if (p[(size_t)y * w + x] != pat(seed, x, y)) { if (!bad && first) *first = [NSString stringWithFormat:@"first bad pixel (%u,%u) got %08x want %08x", x, y, p[(size_t)y * w + x], pat(seed, x, y)]; bad++; }
    return bad;
}
#define VERIFY(name, cond, detail) report((cond), (name), (detail))

// ---- checks ---------------------------------------------------------------------------------------------------------
static void checkGeometry(uint32_t w, uint32_t h, uint32_t row) {
    IOSurfaceRef s = makeSurface(w, h, row, NO);
    NSString *tag = [NSString stringWithFormat:@"geometry %ux%u row=%zu%s", w, h, s ? IOSurfaceGetBytesPerRow(s) : 0, (s && IOSurfaceGetBytesPerRow(s) % 32) ? " (not a multiple of 32: private path expected)" : ""];
    if (!s) { report(NO, tag, @"IOSurfaceCreate failed"); return; }
    id<MTLTexture> t = makeTex(s, MTLPixelFormatBGRA8Unorm, 0, w, h);
    if (!t) { report(NO, tag, @"texture from IOSurface failed"); CFRelease(s); return; }
    padFill(s, w, h);
    NSString *why = nil;
    // C1: CPU writes, GPU reads; CPU edits a rectangle, GPU must see the edit (seed moved -> re-upload)
    cpuFill(s, w, h, 1, 0, 0, w, h);
    long bad = gpuReadCheck(t, w, h, 1, &why);
    VERIFY([tag stringByAppendingString:@" cpu->gpu full"], bad == 0, bad ? [NSString stringWithFormat:@"%ld wrong pixels; %@", bad, why] : @"");
    cpuFill(s, w, h, 2, w / 4, h / 4, w / 2, h / 2);
    // pixels outside the rectangle still carry seed 1, inside seed 2: check both
    {
        id<MTLBuffer> b = [gDev newBufferWithLength:(NSUInteger)w * h * 4 options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
        [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1) toBuffer:b destinationOffset:0
        destinationBytesPerRow:(NSUInteger)w * 4 destinationBytesPerImage:(NSUInteger)w * h * 4];
        [e endEncoding]; BOOL ok = waitDone(cb); const uint32_t *p = b.contents; long wrong = 0;
        for (uint32_t y = 0; ok && y < h; y++) for (uint32_t x = 0; x < w; x++) {
            BOOL in = x >= w / 4 && x < w / 4 + w / 2 && y >= h / 4 && y < h / 4 + h / 2;
            if (p[(size_t)y * w + x] != pat(in ? 2 : 1, x, y)) wrong++;
        }
        VERIFY([tag stringByAppendingString:@" cpu edit->gpu"], ok && wrong == 0, wrong ? [NSString stringWithFormat:@"%ld wrong pixels after a CPU edit" , wrong] : @"");
    }
    // C2: GPU writes (blit and render-pass clear), CPU lock must see it, repeatedly with different contents
    BOOL allOk = YES; NSString *detail = @"";
    for (uint32_t i = 0; i < 20 && allOk; i++) {
        if (!gpuBlitWrite(t, w, h, 100 + i)) { allOk = NO; detail = @"GPU write failed"; break; }
        long b2 = cpuCheck(s, w, h, 100 + i, 0, NO, &why);
        if (b2) { allOk = NO; detail = [NSString stringWithFormat:@"round %u: %ld wrong pixels; %@", i, b2, why]; }
    }
    VERIFY([tag stringByAppendingString:@" gpu blit->cpu x20"], allOk, detail);
    allOk = YES; detail = @"";
    for (uint32_t i = 0; i < 20 && allOk; i++) {
        double c = (i % 5) / 4.0;
        if (!gpuClear(t, c, 1 - c, 0.5, 1.0)) { allOk = NO; detail = @"GPU clear failed"; break; }
        IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
        const uint32_t *p = (const uint32_t *)IOSurfaceGetBaseAddress(s);
        uint32_t first = p[0], last = *(const uint32_t *)((const uint8_t *)IOSurfaceGetBaseAddress(s) + (size_t)(h - 1) * IOSurfaceGetBytesPerRow(s) + (size_t)(w - 1) * 4);
        IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
        if (first != last || first == 0) { allOk = NO; detail = [NSString stringWithFormat:@"round %u: first %08x last %08x", i, first, last]; }
    }
    VERIFY([tag stringByAppendingString:@" gpu clear->cpu x20"], allOk, detail);
    // padding must never change
    VERIFY([tag stringByAppendingString:@" row padding untouched"], padIntact(s, w, h), @"");
    // GPU write then GPU read through the same texture without a CPU lock in between
    gpuBlitWrite(t, w, h, 777);
    bad = gpuReadCheck(t, w, h, 777, &why);
    VERIFY([tag stringByAppendingString:@" gpu->gpu"], bad == 0, bad ? why : @"");
    t = nil; CFRelease(s);
}

static void checkDestroyRecreate(void) {
    const uint32_t w = 640, h = 480; BOOL ok = YES; NSString *detail = @"";
    for (int i = 0; i < 100 && ok; i++) {
        IOSurfaceRef s = makeSurface(w, h, 0, NO);
        if (!s) { ok = NO; detail = @"IOSurfaceCreate failed"; break; }
        NSString *why = nil;
        long z = cpuCheck(s, w, h, 0, 0, YES, &why);                // a new surface must read as zeros, whatever lived in that VRAM before
        if (z) { ok = NO; detail = [NSString stringWithFormat:@"iteration %d: new surface not zero (%ld pixels); %@", i, z, why]; CFRelease(s); break; }
        id<MTLTexture> t = makeTex(s, MTLPixelFormatBGRA8Unorm, 0, w, h);
        if (!t) { ok = NO; detail = @"texture failed"; CFRelease(s); break; }
        gpuBlitWrite(t, w, h, 5000 + i);
        long b = cpuCheck(s, w, h, 5000 + i, 0, NO, &why);
        if (b) { ok = NO; detail = [NSString stringWithFormat:@"iteration %d: %ld wrong pixels; %@", i, b, why]; }
        t = nil; CFRelease(s);
    }
    VERIFY(@"destroy/recreate x100: new surfaces read zero, then take new data", ok, detail);
}

static int spawnChild(const char *mode, IOSurfaceID sid, uint32_t w, uint32_t h, uint32_t seed) {
    char exe[4096]; uint32_t n = sizeof exe; if (_NSGetExecutablePath(exe, &n)) return -1;
    char a1[16], a2[16], a3[16], a4[16];
    snprintf(a1, sizeof a1, "%u", sid); snprintf(a2, sizeof a2, "%u", w); snprintf(a3, sizeof a3, "%u", h); snprintf(a4, sizeof a4, "%u", seed);
    char *argv[] = { exe, (char *)"child", (char *)mode, a1, a2, a3, a4, NULL };
    pid_t pid; if (posix_spawn(&pid, exe, NULL, NULL, argv, environ)) return -1;
    int st = 0; waitpid(pid, &st, 0); return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}
static void checkTwoProcesses(void) {
    const uint32_t w = 800, h = 600;
    IOSurfaceRef s = makeSurface(w, h, 0, YES);
    if (!s) { report(NO, @"two processes", @"IOSurfaceCreate failed"); return; }
    id<MTLTexture> t = makeTex(s, MTLPixelFormatBGRA8Unorm, 0, w, h);           // this texture lives across both children
    NSString *why = nil;
    gpuBlitWrite(t, w, h, 11);
    int rc = spawnChild("verify", IOSurfaceGetID(s), w, h, 11);                    // child must see this process's GPU write
    if (rc == 77) { report(YES, @"two processes (skipped: IOSurfaceLookup refused a global surface here)", @""); CFRelease(s); return; }
    VERIFY(@"two processes: child GPU-reads what the parent GPU wrote", rc == 0, rc ? [NSString stringWithFormat:@"child exit %d", rc] : @"");
    rc = spawnChild("write", IOSurfaceGetID(s), w, h, 12);                         // child GPU-writes new contents and exits
    VERIFY(@"two processes: child GPU write ran", rc == 0, rc ? [NSString stringWithFormat:@"child exit %d", rc] : @"");
    long b = gpuReadCheck(t, w, h, 12, &why);                                      // parent's old texture must see the child's data
    VERIFY(@"two processes: parent's existing texture sees the child's GPU write", b == 0, b ? [NSString stringWithFormat:@"%ld wrong pixels; %@", b, why] : @"");
    b = cpuCheck(s, w, h, 12, 0, NO, &why);
    VERIFY(@"two processes: CPU lock sees the child's GPU write", b == 0, b ? [NSString stringWithFormat:@"%ld wrong pixels; %@", b, why] : @"");
    t = nil; CFRelease(s);
}
static int childMain(const char *mode, IOSurfaceID sid, uint32_t w, uint32_t h, uint32_t seed) {
    IOSurfaceRef s = IOSurfaceLookup(sid); if (!s) return 77;
    id<MTLTexture> t = makeTex(s, MTLPixelFormatBGRA8Unorm, 0, w, h); if (!t) return 2;
    if (!strcmp(mode, "verify")) { NSString *why = nil; long b = gpuReadCheck(t, w, h, seed, &why); if (b) fprintf(stderr, "child: %ld wrong pixels; %s\n", b, why.UTF8String); return b ? 1 : 0; }
    if (!strcmp(mode, "write")) return gpuBlitWrite(t, w, h, seed) ? 0 : 3;
    return 4;
}
static void checkPlanes(void) {
    // two-plane 4:2:0 ('420f'): plane 1 is RG8 at half size. Sharing is not offered for planes > 0, so this is the private path.
    const uint32_t w = 256, h = 128;
    NSDictionary *d = @{ (id)kIOSurfaceWidth: @(w), (id)kIOSurfaceHeight: @(h), (id)kIOSurfacePixelFormat: @(0x34323066u),
        (id)kIOSurfacePlaneInfo: @[ @{ (id)kIOSurfacePlaneWidth: @(w), (id)kIOSurfacePlaneHeight: @(h), (id)kIOSurfacePlaneBytesPerElement: @1 },
                                     @{ (id)kIOSurfacePlaneWidth: @(w / 2), (id)kIOSurfacePlaneHeight: @(h / 2), (id)kIOSurfacePlaneBytesPerElement: @2 } ] };
    IOSurfaceRef s = IOSurfaceCreate((__bridge CFDictionaryRef)d);
    if (!s) { report(NO, @"planes", @"IOSurfaceCreate(420f) failed"); return; }
    id<MTLTexture> t = makeTex(s, MTLPixelFormatRG8Unorm, 1, w / 2, h / 2);
    if (!t) { report(NO, @"planes: RG8 texture on plane 1", @"newTextureWithDescriptor:iosurface:plane: returned nil"); CFRelease(s); return; }
    IOSurfaceLock(s, 0, NULL);
    uint8_t *p = IOSurfaceGetBaseAddressOfPlane(s, 1); size_t row = IOSurfaceGetBytesPerRowOfPlane(s, 1);
    for (uint32_t y = 0; y < h / 2; y++) for (uint32_t x = 0; x < w / 2; x++) { p[y * row + 2 * x] = (uint8_t)(x * 3 + y); p[y * row + 2 * x + 1] = (uint8_t)(x + y * 5); }
    IOSurfaceUnlock(s, 0, NULL);
    id<MTLBuffer> b = [gDev newBufferWithLength:(w / 2) * (h / 2) * 2 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
    [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w / 2, h / 2, 1) toBuffer:b destinationOffset:0
    destinationBytesPerRow:(w / 2) * 2 destinationBytesPerImage:(w / 2) * (h / 2) * 2];
    [e endEncoding]; BOOL ok = waitDone(cb); const uint8_t *q = b.contents; long wrong = 0;
    for (uint32_t y = 0; ok && y < h / 2; y++) for (uint32_t x = 0; x < w / 2; x++)
        if (q[(y * (w / 2) + x) * 2] != (uint8_t)(x * 3 + y) || q[(y * (w / 2) + x) * 2 + 1] != (uint8_t)(x + y * 5)) wrong++;
    VERIFY(@"planes: CPU writes plane 1, GPU reads it", ok && wrong == 0, wrong ? [NSString stringWithFormat:@"%ld wrong texels", wrong] : @"");
    t = nil; CFRelease(s);
}

// ---- benchmark ------------------------------------------------------------------------------------------------------
typedef BOOL (^Op)(void);
static void timeCase(NSString *name, uint32_t w, uint32_t h, double seconds, Op op) {
    for (int i = 0; i < 5; i++) op();                       // warm-up
    double t0 = nowms(), c0 = cpums(); long n = 0;
    while (nowms() - t0 < seconds * 1e3) { if (!op()) { printf("%-44s %ux%u  operation failed\n", name.UTF8String, w, h); return; } n++; }
    double wall = (nowms() - t0) / n, cpu = (cpums() - c0) / n;
    printf("%-44s %4ux%-4u %8.3f ms/op wall  %8.3f ms/op process CPU  %8.1f MB/s of surface per op\n", name.UTF8String, w, h, wall, cpu,
           (double)w * h * 4 / 1048576.0 / (wall / 1e3));
}
static void bench(double seconds) {
    const uint32_t sizes[][2] = { {64, 64}, {512, 512}, {1920, 1080}, {2880, 1800} };
    printf("device: %s   (NVMTL_NO_SURFACE_SHARE=%s NVMTL_NO_SURFACE_PAGEOFF=%s)\n", gDev.name.UTF8String,
           getenv("NVMTL_NO_SURFACE_SHARE") ?: "unset", getenv("NVMTL_NO_SURFACE_PAGEOFF") ?: "unset");
    printf("single-operation transfer costs on synthetic surfaces; NOT a WindowServer measurement\n");
    for (int k = 0; k < 4; k++) {
        uint32_t w = sizes[k][0], h = sizes[k][1];
        IOSurfaceRef s = makeSurface(w, h, 0, NO); id<MTLTexture> t = makeTex(s, MTLPixelFormatBGRA8Unorm, 0, w, h);
        id<MTLBuffer> src = [gDev newBufferWithLength:(NSUInteger)w * h * 4 options:MTLResourceStorageModeShared]; memset(src.contents, 0x5A, src.length);
        __block uint32_t seed = 1;
        Op gpuWrite = ^BOOL{
            id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
            [e copyFromBuffer:src sourceOffset:0 sourceBytesPerRow:(NSUInteger)w * 4 sourceBytesPerImage:src.length sourceSize:MTLSizeMake(w, h, 1)
                    toTexture:t destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
            [e endEncoding]; return waitDone(cb); };
        timeCase(@"gpu write, wait (no CPU access)", w, h, seconds, gpuWrite);
        timeCase(@"gpu write, wait, CPU lock + read 1 pixel", w, h, seconds, ^BOOL{
            if (!gpuWrite()) return NO;
            IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL); volatile uint32_t v = *(uint32_t *)IOSurfaceGetBaseAddress(s); (void)v; IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL); return YES; });
        timeCase(@"cpu write 1 row, gpu read (re-upload), wait", w, h, seconds, ^BOOL{
            IOSurfaceLock(s, 0, NULL); memset(IOSurfaceGetBaseAddress(s), (int)(++seed & 0xFF), (size_t)w * 4); IOSurfaceUnlock(s, 0, NULL);
            id<MTLBuffer> dst = [gDev newBufferWithLength:(NSUInteger)w * h * 4 options:MTLResourceStorageModeShared];
            id<MTLCommandBuffer> cb = [gQ commandBuffer]; id<MTLBlitCommandEncoder> e = [cb blitCommandEncoder];
            [e copyFromTexture:t sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake(w, h, 1) toBuffer:dst destinationOffset:0
            destinationBytesPerRow:(NSUInteger)w * 4 destinationBytesPerImage:dst.length];
            [e endEncoding]; return waitDone(cb); });
        t = nil; CFRelease(s);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gDev = MTLCreateSystemDefaultDevice();
        if (!gDev) { fprintf(stderr, "no Metal device\n"); return 2; }
        gQ = [gDev newCommandQueue];
        if (argc >= 7 && !strcmp(argv[1], "child")) return childMain(argv[2], (IOSurfaceID)atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), (uint32_t)atoi(argv[6]));
        if (argc >= 2 && !strcmp(argv[1], "bench")) { bench(argc >= 3 ? atof(argv[2]) : 2.0); return 0; }
        if (argc >= 2 && !strcmp(argv[1], "check")) {
            printf("device: %s   (NVMTL_NO_SURFACE_SHARE=%s NVMTL_NO_SURFACE_PAGEOFF=%s)\n", gDev.name.UTF8String,
                   getenv("NVMTL_NO_SURFACE_SHARE") ?: "unset", getenv("NVMTL_NO_SURFACE_PAGEOFF") ?: "unset");
            checkGeometry(256, 64, 0);          // default pitch
            checkGeometry(256, 64, 1024 + 64);  // padded pitch (multiple of 32)
            checkGeometry(1921, 64, 0);         // width whose natural row is not a multiple of 32 on some allocators
            checkGeometry(1000, 50, 4000 + 16); // pitch that is a multiple of 16 but not of 32
            checkGeometry(2880, 1800, 0);       // the panel
            checkDestroyRecreate();
            checkTwoProcesses();
            checkPlanes();
            printf("\n%d passed, %d failed\n", gPass, gFail);
            return gFail ? 1 : 0;
        }
        fprintf(stderr, "usage: surfsync check | bench [seconds] | child ...\n");
        return 2;
    }
}
