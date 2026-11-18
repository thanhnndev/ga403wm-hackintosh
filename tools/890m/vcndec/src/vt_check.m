// SPDX-License-Identifier: BSD-3-Clause-Clear
// vt_check: decode an MP4 / MOV (H.264, HEVC Main/Main10) through a VTDecompressionSession that requires a hardware
// decoder, and check every output picture against the frame index burned into the video-suite clips
// (tools/890m/video-suite/gen: a 16-bit strip, bottom left, cell c = round(28 * H/1080), x0 = 30 s, bottom 30 s).
// -b <bundle binary>: dlopen it and call VCNDec_RegisterInProcess first (no install needed).
// Output order is free (VT may emit in decode order): pictures are matched to samples by pts.
// usage: vt_check [-b VCNDec.bundle/Contents/MacOS/VCNDec] clip.mp4 fps
// exit 0 = every sample decoded on a hardware decoder and every picture showed the right frame index.
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// memory test: VT_REPEAT=n runs n sessions in this process, VT_HOLD=s waits s seconds after each, and after each
// session (and after the hold) prints the footprint of the process that decodes: the newest VTDecoderXPCService, or
// this process with -b (in-process VCNDec). Shows whether decoded surfaces outlive their sessions.
static int g_inproc;
static void foot(const char *when, int k) {
  char cmd[256];
  if (g_inproc) snprintf(cmd, sizeof cmd, "footprint %d 2>/dev/null", getpid());
  else snprintf(cmd, sizeof cmd, "footprint $(pgrep -n VTDecoderXPCService) 2>/dev/null");
  FILE *f = popen(cmd, "r"); char l[512], out[512] = "";
  while (f && fgets(l, sizeof l, f)) {
    if (strstr(l, "Footprint:") || strstr(l, "Owned physical footprint") || strstr(l, " IOSurface\n")) {
      l[strcspn(l, "\n")] = 0; char *t = l; while (*t == ' ') t++;
      strncat(out, t, sizeof out - strlen(out) - 4); strncat(out, " | ", sizeof out - strlen(out) - 1); }
  }
  if (f) pclose(f);
  printf("FOOT session %d %s: %s\n", k, when, out); fflush(stdout);
}

static int g_fps, g_ok, g_bad, g_unreadable, g_err, g_out;
static OSType g_fmt;

static int read_index(CVPixelBufferRef pb, int *border) {
  OSType f = CVPixelBufferGetPixelFormatType(pb);
  int ten = f == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || f == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  const uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0);
  size_t bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0);
  int H = (int)CVPixelBufferGetHeight(pb);
  double s = H / 1080.0; int c = (int)lround(28 * s); double x0 = 30 * s, y0 = H - 30 * s - c, m = 4 * s;
  // luma 0..255 at (x, y); video range: white ~235, black ~16
#define LUMA(x, yy) (ten ? (((const uint16_t *)(y + (size_t)(yy) * bpr))[(int)(x)] >> 8) : y[(size_t)(yy) * bpr + (int)(x)])
  *border = LUMA(x0 - m / 2, y0 + c / 2.0);
  int idx = 0;
  for (int b = 0; b < 16; b++) idx = (idx << 1) | (LUMA(x0 + b * c + c / 2.0, y0 + c / 2.0) > 128);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  return idx;
}

// VT_KEEP=n: keep the last n pictures alive (a player's frame queue), so the session's pixel-buffer pool grows the
// way it does under AVPlayer (Aerials wallpaper, Safari, QuickTime)
static CVImageBufferRef g_keep[512]; static int g_nkeep, g_kpos;
static void keep_release(void) { for (int i = 0; i < 512; i++) if (g_keep[i]) { CVBufferRelease(g_keep[i]); g_keep[i] = NULL; } g_kpos = 0; }

static void out_cb(void *ref, void *src, OSStatus st, VTDecodeInfoFlags fl, CVImageBufferRef img, CMTime pts, CMTime dur) {
  if (st || !img) { if (g_err++ < 5) fprintf(stderr, "frame at %.3f: status %d flags %x\n", CMTimeGetSeconds(pts), (int)st, (unsigned)fl); return; }
  g_out++;
  if (!g_fmt) g_fmt = CVPixelBufferGetPixelFormatType(img);
  if (g_nkeep) { int i = g_kpos++ % g_nkeep; if (g_keep[i]) CVBufferRelease(g_keep[i]); g_keep[i] = CVBufferRetain(img); }
  int border, idx = read_index(img, &border), want = (int)lround(CMTimeGetSeconds(pts) * g_fps);
  if (border < 170) { if (g_unreadable++ < 5) fprintf(stderr, "frame at %.3f: strip unreadable (border %d)\n", CMTimeGetSeconds(pts), border); }
  else if (idx == want) g_ok++;
  else if (g_bad++ < 5) fprintf(stderr, "frame at %.3f: shows #%d, want #%d\n", CMTimeGetSeconds(pts), idx, want);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    int a = 1;
    if (argc > 2 && !strcmp(argv[1], "-b")) {
      void *h = dlopen(argv[2], RTLD_NOW);
      void (*reg)(void) = h ? dlsym(h, "VCNDec_RegisterInProcess") : NULL;
      if (!reg) { fprintf(stderr, "cannot load %s: %s\n", argv[2], dlerror()); return 2; }
      reg(); a = 3; g_inproc = 1;
    }
    if (argc - a != 2) { fprintf(stderr, "usage: vt_check [-b bundle-binary] clip.mp4 fps\n"); return 2; }
    g_fps = atoi(argv[a + 1]);
    int reps = getenv("VT_REPEAT") ? atoi(getenv("VT_REPEAT")) : 1, hold = getenv("VT_HOLD") ? atoi(getenv("VT_HOLD")) : 0;
    int rc = 0;
    g_nkeep = getenv("VT_KEEP") ? atoi(getenv("VT_KEEP")) : 0; if (g_nkeep > 512) g_nkeep = 512;
    for (int k = 1; k <= reps; k++) @autoreleasepool {
    g_out = g_ok = g_bad = g_unreadable = g_err = 0;
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:@(argv[a])] options:nil];
    NSError *e = nil;
    AVAssetReader *rd = [AVAssetReader assetReaderWithAsset:as error:&e];
    AVAssetTrack *tr = [[as tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!rd || !tr) { fprintf(stderr, "no video track: %s\n", e.description.UTF8String); return 2; }
    AVAssetReaderTrackOutput *o = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:tr outputSettings:nil]; // compressed samples
    [rd addOutput:o];
    [rd startReading];
    CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)tr.formatDescriptions.firstObject;
    NSDictionary *spec = @{(id)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder : @YES};
    VTDecompressionOutputCallbackRecord cb = {out_cb, NULL};
    VTDecompressionSessionRef ses = NULL;
    OSStatus st = VTDecompressionSessionCreate(NULL, fd, (__bridge CFDictionaryRef)spec, NULL, &cb, &ses);
    if (st) { fprintf(stderr, "no hardware decoder for this format: %d\n", (int)st); return 3; }
    CFBooleanRef hw = NULL;
    VTSessionCopyProperty(ses, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hw);
    int n = 0;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    CMSampleBufferRef sb;
    while ((sb = [o copyNextSampleBuffer])) {
      if (CMSampleBufferGetNumSamples(sb)) { VTDecompressionSessionDecodeFrame(ses, sb, kVTDecodeFrame_EnableAsynchronousDecompression, NULL, NULL); n++; }
      CFRelease(sb);
    }
    VTDecompressionSessionFinishDelayedFrames(ses);
    VTDecompressionSessionWaitForAsynchronousFrames(ses);
    double dt = CFAbsoluteTimeGetCurrent() - t0;
    if (g_nkeep && getenv("VT_REPEAT")) foot("decoded, frames still kept", k);
    if (getenv("VT_IDLE")) { sleep(atoi(getenv("VT_IDLE"))); foot("session open, idle", k); }   // idle trim test
    VTDecompressionSessionInvalidate(ses);
    CFRelease(ses);
    keep_release();
    printf("%s: %d samples, %d pictures (hw %s, format %c%c%c%c), index ok %d, wrong %d, unreadable %d, errors %d, %.0f fps\n", argv[a], n, g_out,
           hw == kCFBooleanTrue ? "yes" : "no", (char)(g_fmt >> 24), (char)(g_fmt >> 16), (char)(g_fmt >> 8), (char)g_fmt, g_ok, g_bad, g_unreadable, g_err, n / dt);
    if (!(g_out == n && g_ok == n && hw == kCFBooleanTrue)) rc = 1;
    if (getenv("VT_REPEAT") || hold) { foot("closed", k); if (hold) { sleep(hold); foot("after hold", k); } }
    }
    return rc;
  }
}
