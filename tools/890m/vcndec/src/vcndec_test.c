// SPDX-License-Identifier: BSD-3-Clause-Clear
// vcndec_test: decode an IVF (VP9 / AV1) with vcndec into IOSurface NV12 pixel buffers.
// Prints one md5 per frame (packed NV12, same as `ffmpeg -pix_fmt nv12 -f framemd5`) with -m, and CPU/wall time.
#define COMMON_DIGEST_FOR_OPENSSL
#include "vcndec.h"
#include <CommonCrypto/CommonDigest.h>
#include <IOSurface/IOSurface.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static double cpu(void) {
  struct rusage u; getrusage(RUSAGE_SELF, &u);
  return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec + u.ru_stime.tv_usec / 1e6;
}

static void md5_frame(CVPixelBufferRef pb, int w, int h, FILE *o, int n) {
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  MD5_CTX c; MD5_Init(&c);
  uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
  size_t yb = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cb = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
  for (int r = 0; r < h; r++) MD5_Update(&c, y + r * yb, w);
  for (int r = 0; r < (h + 1) / 2; r++) MD5_Update(&c, uv + r * cb, ((w + 1) / 2) * 2);
  unsigned char m[16]; MD5_Final(m, &c);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  fprintf(o, "%d ", n);
  for (int i = 0; i < 16; i++) fprintf(o, "%02x", m[i]);
  fprintf(o, "\n");
}

static void dump_frame(CVPixelBufferRef pb, int w, int h, const char *path) {
  FILE *o = fopen(path, "wb");
  CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
  size_t yb = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cb = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
  for (int r = 0; r < h; r++) fwrite(y + r * yb, 1, w, o);
  for (int r = 0; r < (h + 1) / 2; r++) fwrite(uv + r * cb, 1, ((w + 1) / 2) * 2, o);
  CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
  fclose(o);
  fprintf(stderr, "dumped %s (bpr %zu/%zu)\n", path, yb, cb);
}

int main(int argc, char **argv) {
  int md5 = 0, loops = 1, dumpn = -1;
  const char *path = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-m")) md5 = 1;
    else if (!strcmp(argv[i], "-l") && i + 1 < argc) loops = atoi(argv[++i]);
    else if (!strcmp(argv[i], "-d") && i + 1 < argc) dumpn = atoi(argv[++i]);
    else path = argv[i];
  }
  if (!path) { fprintf(stderr, "usage: vcndec_test [-m] [-l loops] clip.ivf\n"); return 2; }
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); return 2; }
  uint8_t hdr[32];
  if (fread(hdr, 1, 32, f) != 32 || memcmp(hdr, "DKIF", 4)) { fprintf(stderr, "not IVF\n"); return 2; }
  uint32_t fourcc = (uint32_t)hdr[8] << 24 | hdr[9] << 16 | hdr[10] << 8 | hdr[11];
  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  uint32_t codec = fourcc == 'AV01' ? 'av01' : 'vp09';
  long data0 = ftell(f);

  char err[256] = "";
  double t0 = now(), c0 = cpu();
  vcn_dec *d = vcn_open(codec, w, h, NULL, 0, err, sizeof err);
  if (!d) { fprintf(stderr, "vcn_open: %s\n", err); return 1; }
  double topen = now() - t0;

  int32_t fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  CFNumberRef nf = CFNumberCreate(NULL, kCFNumberSInt32Type, &fmt), nw = CFNumberCreate(NULL, kCFNumberSInt32Type, &w),
              nh = CFNumberCreate(NULL, kCFNumberSInt32Type, &h);
  CFDictionaryRef io = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void *k[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey, kCVPixelBufferIOSurfacePropertiesKey};
  const void *v[] = {nf, nw, nh, io};
  CFDictionaryRef attrs = CFDictionaryCreate(NULL, k, v, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CVPixelBufferPoolRef pool = NULL;
  CVPixelBufferPoolCreate(NULL, NULL, attrs, &pool);

  int n = 0;
  uint8_t *buf = malloc(8 << 20);
  t0 = now(); c0 = cpu();
  for (int l = 0; l < loops; l++) {
    fseek(f, data0, SEEK_SET);
    uint8_t fh[12];
    for (;;) {
      int eof = fread(fh, 1, 12, f) != 12;
      if (!eof) {
        uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
        if (sz > (8u << 20) || fread(buf, 1, sz, f) != sz) eof = 1;
        else if (vcn_send(d, buf, sz, n) < 0) { fprintf(stderr, "send: %s\n", vcn_last_error(d)); return 1; }
      }
      if (eof && l == loops - 1) vcn_flush(d);
      for (;;) {
        CVPixelBufferRef pb; int64_t pts;
        int r = vcn_receive(d, pool, &pb, &pts);
        if (r < 0) { fprintf(stderr, "receive: %s\n", vcn_last_error(d)); return 1; }
        if (!r) break;
        if (md5) md5_frame(pb, w, h, stdout, n);
        if (n == dumpn) dump_frame(pb, w, h, "vcn-frame.nv12");
        CVPixelBufferRelease(pb);
        n++;
      }
      if (eof) break;
    }
  }
  double wall = now() - t0, cp = cpu() - c0;
  uint64_t fr, g, c, im; vcn_stats(d, &fr, &g, &c, &im);
  fprintf(stderr, "%s %dx%d: %d frames in %.3f s (%.0f fps), CPU %.3f s (%.2f ms/frame), open %.3f s; gpu-copy %llu, cpu-copy %llu, imports %llu\n",
          codec == 'av01' ? "av1" : "vp9", w, h, n, wall, n / wall, cp, cp * 1000 / (n ? n : 1), topen,
          (unsigned long long)g, (unsigned long long)c, (unsigned long long)im);
  vcn_close(d);
  return 0;
}
