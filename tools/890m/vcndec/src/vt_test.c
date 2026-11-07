// SPDX-License-Identifier: BSD-3-Clause-Clear
// vt_test: decode an IVF (VP9 / AV1) through a VTDecompressionSession that requires a hardware decoder.
// -b <bundle binary>: dlopen it and call VCNDec_RegisterInProcess first (no install needed);
// without -b the installed decoders are used (after VTRegisterSupplementalVideoDecoderIfAvailable, as Chrome does).
// Prints the md5 of every frame with -m (packed NV12, like ffmpeg framemd5) and the decoder's hardware flag.
#define COMMON_DIGEST_FOR_OPENSSL
#include <CommonCrypto/CommonDigest.h>
#include <CoreMedia/CoreMedia.h>
#include <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
extern void VTRegisterSupplementalVideoDecoderIfAvailable(CMVideoCodecType) __attribute__((weak_import));

static int g_md5, g_frames, g_errors;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static double cpu(void) {
  struct rusage u; getrusage(RUSAGE_SELF, &u);
  return u.ru_utime.tv_sec + u.ru_utime.tv_usec / 1e6 + u.ru_stime.tv_sec + u.ru_stime.tv_usec / 1e6;
}

static void out_cb(void *ref, void *fref, OSStatus st, VTDecodeInfoFlags fl, CVImageBufferRef img, CMTime pts, CMTime dur) {
  if (st || !img) {
    if (g_errors++ < 5) fprintf(stderr, "frame %ld: status %d flags %#x img %p\n", (long)(intptr_t)fref, (int)st, fl, img);
    return;
  }
  if (g_md5) {
    CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
    int w = (int)CVPixelBufferGetWidth(img), h = (int)CVPixelBufferGetHeight(img);
    uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(img, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(img, 1);
    size_t yb = CVPixelBufferGetBytesPerRowOfPlane(img, 0), cb = CVPixelBufferGetBytesPerRowOfPlane(img, 1);
    MD5_CTX c; MD5_Init(&c);
    for (int r = 0; r < h; r++) MD5_Update(&c, y + r * yb, w);
    for (int r = 0; r < (h + 1) / 2; r++) MD5_Update(&c, uv + r * cb, ((w + 1) / 2) * 2);
    unsigned char m[16]; MD5_Final(m, &c);
    CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
    for (int i = 0; i < 16; i++) printf("%02x", m[i]);
    printf("\n");
  }
  g_frames++;
}

int main(int argc, char **argv) {
  const char *bundle = NULL, *path = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "-m")) g_md5 = 1;
    else if (!strcmp(argv[i], "-b") && i + 1 < argc) bundle = argv[++i];
    else path = argv[i];
  }
  if (!path) { fprintf(stderr, "usage: vt_test [-m] [-b VCNDec.bundle/Contents/MacOS/VCNDec] clip.ivf\n"); return 2; }
  FILE *f = fopen(path, "rb");
  uint8_t hdr[32];
  if (!f || fread(hdr, 1, 32, f) != 32 || memcmp(hdr, "DKIF", 4)) { fprintf(stderr, "not IVF\n"); return 2; }
  int av1 = !memcmp(hdr + 8, "AV01", 4);
  int w = hdr[12] | hdr[13] << 8, h = hdr[14] | hdr[15] << 8;
  CMVideoCodecType codec = av1 ? 'av01' : 'vp09';
  if (bundle) {
    void *lib = dlopen(bundle, RTLD_NOW);
    void (*reg)(void) = lib ? (void (*)(void))dlsym(lib, "VCNDec_RegisterInProcess") : NULL;
    if (!reg) { fprintf(stderr, "dlopen %s: %s\n", bundle, dlerror()); return 1; }
    if (VTRegisterSupplementalVideoDecoderIfAvailable && getenv("VT_SUPP_FIRST")) VTRegisterSupplementalVideoDecoderIfAvailable(codec);
    reg();
    if (VTRegisterSupplementalVideoDecoderIfAvailable && !getenv("VT_SUPP_FIRST")) VTRegisterSupplementalVideoDecoderIfAvailable(codec);
  } else if (VTRegisterSupplementalVideoDecoderIfAvailable) {
    VTRegisterSupplementalVideoDecoderIfAvailable(codec);
  }
  fprintf(stderr, "VTIsHardwareDecodeSupported(%s) = %d\n", av1 ? "av01" : "vp09", VTIsHardwareDecodeSupported(codec));

  // vpcC: version 1, profile 0, level 4.1, 8-bit 4:2:0 colocated, BT.709, limited range. av1C: main, 8-bit 4:2:0.
  uint8_t vpcc[] = {1, 0, 0, 0, 0, 41, (8 << 4) | (1 << 1), 1, 1, 1, 0, 0};
  uint8_t av1c[] = {0x81, 0x08, 0x0c, 0x00};
  CFDataRef atom = CFDataCreate(NULL, av1 ? av1c : vpcc, av1 ? sizeof av1c : sizeof vpcc);
  const void *ak[] = {av1 ? CFSTR("av1C") : CFSTR("vpcC")}, *av[] = {atom};
  CFDictionaryRef atoms = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void *ek[] = {kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms, kCVImageBufferYCbCrMatrixKey,
                      kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey};
  const void *ev[] = {atoms, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVImageBufferColorPrimaries_ITU_R_709_2,
                      kCVImageBufferTransferFunction_ITU_R_709_2};
  CFDictionaryRef ext = CFDictionaryCreate(NULL, ek, ev, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CMVideoFormatDescriptionRef fd;
  if (CMVideoFormatDescriptionCreate(NULL, codec, w, h, ext, &fd)) { fprintf(stderr, "format description failed\n"); return 1; }

  const void *sk[] = {kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder};
  const void *sv[] = {kCFBooleanTrue};
  CFDictionaryRef spec = CFDictionaryCreate(NULL, sk, sv, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  int32_t pf = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  CFNumberRef npf = CFNumberCreate(NULL, kCFNumberSInt32Type, &pf);
  CFDictionaryRef io = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void *pk[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferIOSurfacePropertiesKey}, *pv[] = {npf, io};
  CFDictionaryRef dst = CFDictionaryCreate(NULL, pk, pv, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  VTDecompressionOutputCallbackRecord cb = {out_cb, NULL};
  VTDecompressionSessionRef sess;
  double t0 = now();
  OSStatus e = VTDecompressionSessionCreate(NULL, fd, spec, dst, &cb, &sess);
  if (e) { fprintf(stderr, "VTDecompressionSessionCreate (require hardware) = %d\n", (int)e); return 1; }
  CFBooleanRef hw = NULL;
  VTSessionCopyProperty(sess, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hw);
  fprintf(stderr, "session created in %.3f s, UsingHardwareAcceleratedVideoDecoder = %d\n", now() - t0, hw == kCFBooleanTrue);

  uint8_t fh[12];
  int n = 0;
  t0 = now();
  double c0 = cpu();
  while (fread(fh, 1, 12, f) == 12) {
    uint32_t sz = fh[0] | fh[1] << 8 | fh[2] << 16 | (uint32_t)fh[3] << 24;
    void *data = malloc(sz);
    if (fread(data, 1, sz, f) != sz) { free(data); break; }
    CMBlockBufferRef bb;
    CMBlockBufferCreateWithMemoryBlock(NULL, data, sz, kCFAllocatorMalloc, NULL, 0, sz, 0, &bb);
    CMSampleTimingInfo ti = {CMTimeMake(1, 60), CMTimeMake(n, 60), kCMTimeInvalid};
    size_t ssz = sz;
    CMSampleBufferRef sb;
    CMSampleBufferCreateReady(NULL, bb, fd, 1, 1, &ti, 1, &ssz, &sb);
    VTDecodeInfoFlags inf;
    e = VTDecompressionSessionDecodeFrame(sess, sb, kVTDecodeFrame_EnableAsynchronousDecompression, (void *)(intptr_t)n, &inf);
    if (e && g_errors++ < 5) fprintf(stderr, "DecodeFrame %d = %d\n", n, (int)e);
    CFRelease(sb);
    CFRelease(bb);
    n++;
  }
  VTDecompressionSessionWaitForAsynchronousFrames(sess);
  double wall = now() - t0, cp = cpu() - c0;
  fprintf(stderr, "%d samples -> %d frames, %d errors, %.3f s (%.0f fps), CPU %.3f s (%.2f ms/frame, client side)\n", n,
          g_frames, g_errors, wall, g_frames / wall, cp, cp * 1000 / (g_frames ? g_frames : 1));
  VTDecompressionSessionInvalidate(sess);
  return g_errors ? 1 : 0;
}
