// SPDX-License-Identifier: BSD-3-Clause-Clear
// VCNDec: VideoToolbox decoder plugin for VP9 / AV1 on the Radeon 890M VCN (vcndec.c does the work).
// Class layout as in tools/890m/vtstub (reversed from AV1DecoderSW.bundle). Runs in VTDecoderXPCService
// (Chrome, Safari HEVC/VP9) or in-process via VCNDec_RegisterInProcess (tests).
// Kill switch: /Library/NullMoth/vcndec-off -> CreateInstance refuses, VideoToolbox moves on (apps decode in software).
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <os/log.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vcndec.h"

typedef struct OpaqueCMBaseObject *CMBaseObjectRef;
typedef struct OpaqueVTVideoDecoder *VTVideoDecoderRef;
typedef struct OpaqueVTVideoDecoderSession *VTVideoDecoderSession;
typedef struct OpaqueVTVideoDecoderFrame *VTVideoDecoderFrame;
typedef const void *CMBaseClassID;

#pragma pack(push, 4)
typedef struct {
  uint32_t version;
  size_t derivedStorageSize;
  Boolean (*equal)(CMBaseObjectRef, CMBaseObjectRef);
  OSStatus (*invalidate)(CMBaseObjectRef);
  void (*finalize)(CMBaseObjectRef);
  CFStringRef (*copyDebugDescription)(CMBaseObjectRef);
  OSStatus (*copyProperty)(CMBaseObjectRef, CFStringRef, CFAllocatorRef, void *);
  OSStatus (*setProperty)(CMBaseObjectRef, CFStringRef, CFTypeRef);
  OSStatus (*notificationBarrier)(CMBaseObjectRef);
  const void *protocolTable;
  void *reserved[2];
} CMBaseClass;
typedef struct {
  uint32_t version;
  OSStatus (*startSession)(VTVideoDecoderRef, VTVideoDecoderSession, CMVideoFormatDescriptionRef);
  OSStatus (*decodeFrame)(VTVideoDecoderRef, VTVideoDecoderFrame, CMSampleBufferRef, VTDecodeFrameFlags, VTDecodeInfoFlags *);
  OSStatus (*copySupportedPropertyDictionary)(VTVideoDecoderRef, CFDictionaryRef *);
  OSStatus (*setProperties)(VTVideoDecoderRef, CFDictionaryRef);
  OSStatus (*copySerializableProperties)(VTVideoDecoderRef, CFAllocatorRef, CFDictionaryRef *);
  Boolean (*canAcceptFormatDescription)(VTVideoDecoderRef, CMFormatDescriptionRef);
  OSStatus (*finishDelayedFrames)(VTVideoDecoderRef);
  void *reserved[6];
} VTVideoDecoderClass;
#pragma pack(pop)
typedef struct { const void *reserved; const CMBaseClass *baseClass; const VTVideoDecoderClass *derivedClass; } VTVideoDecoderVTable;

extern CMBaseClassID VTVideoDecoderGetClassID(void);
extern CMBaseObjectRef VTVideoDecoderGetCMBaseObject(VTVideoDecoderRef);
extern OSStatus CMDerivedObjectCreate(CFAllocatorRef, const void *vtable, CMBaseClassID, void *objOut);
extern void *CMBaseObjectGetDerivedStorage(CMBaseObjectRef);
extern OSStatus VTDecoderSessionSetPixelBufferAttributes(VTVideoDecoderSession, CFDictionaryRef);
extern CVPixelBufferPoolRef VTDecoderSessionGetPixelBufferPool(VTVideoDecoderSession);
extern OSStatus VTDecoderSessionEmitDecodedFrame(VTVideoDecoderSession, VTVideoDecoderFrame, OSStatus, VTDecodeInfoFlags, CVImageBufferRef);
extern OSStatus VTRegisterVideoDecoderWithInfo(FourCharCode, CFDictionaryRef, void *createFn);
extern const CFStringRef kVTVideoDecoder_IsHardwareAccelerated;

enum { kErrBadData = -12909, kErrNoDecoder = -12906, kErrDecoderFailed = -12911, kErrUnsupportedFormat = -12910 };

typedef struct {
  pthread_mutex_t lock;
  VTVideoDecoderSession session;
  CMVideoFormatDescriptionRef fmt;
  CFDictionaryRef color; // attachments for each output buffer
  vcn_dec *dec;
  FourCharCode codec;
  uint64_t in, out, dropped, errors;
  uint8_t *buf;
  size_t bufn;
} Storage;

static os_log_t g_log;
static void mk_log(void) { g_log = os_log_create("com.ga403wm.vcndec", "decoder"); }
static os_log_t L(void) {
  static pthread_once_t o = PTHREAD_ONCE_INIT;
  pthread_once(&o, mk_log);
  return g_log;
}
static Storage *ST(VTVideoDecoderRef d) { return (Storage *)CMBaseObjectGetDerivedStorage(VTVideoDecoderGetCMBaseObject(d)); }
static const char *cc(FourCharCode c, char b[5]) { b[0] = c >> 24; b[1] = c >> 16; b[2] = c >> 8; b[3] = c; b[4] = 0; return b; }

static void teardown(Storage *s) {
  if (s->dec) {
    uint64_t f, g, c, i;
    vcn_stats(s->dec, &f, &g, &c, &i);
    os_log(L(), "VCNDEC close: in %llu out %llu dropped %llu errors %llu (gpu-copy %llu cpu-copy %llu imports %llu)",
           s->in, s->out, s->dropped, s->errors, g, c, i);
    vcn_close(s->dec);
    s->dec = NULL;
  }
}

static OSStatus b_invalidate(CMBaseObjectRef o) {
  Storage *s = CMBaseObjectGetDerivedStorage(o);
  pthread_mutex_lock(&s->lock); teardown(s); pthread_mutex_unlock(&s->lock);
  return 0;
}
static void b_finalize(CMBaseObjectRef o) {
  Storage *s = CMBaseObjectGetDerivedStorage(o);
  teardown(s);
  if (s->fmt) CFRelease(s->fmt);
  if (s->color) CFRelease(s->color);
  free(s->buf);
  pthread_mutex_destroy(&s->lock);
}
static CFStringRef b_desc(CMBaseObjectRef o) { return CFStringCreateWithFormat(NULL, NULL, CFSTR("<VCNDec 890M decoder %p>"), o); }
static OSStatus b_copyProperty(CMBaseObjectRef o, CFStringRef key, CFAllocatorRef a, void *out) {
  if (CFEqual(key, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder)) {
    *(CFTypeRef *)out = kCFBooleanTrue;
    return 0;
  }
  return -12783; // kCMBaseObjectError_ValueNotAvailable
}
static OSStatus b_setProperty(CMBaseObjectRef o, CFStringRef key, CFTypeRef v) { return 0; }

// 8-bit 4:2:0 only (NV12 out). vpcC: FullBox (4) + profile, level, bitDepth:4|chroma:3|fullRange:1.
// av1C: marker/version, seq_profile:3|level:5, tier:1|high_bitdepth:1|twelve_bit:1|mono:1|ss_x:1|ss_y:1|pos:2.
static int check_config(FourCharCode codec, CFDataRef cfg, int *full_range) {
  *full_range = 0;
  if (!cfg) return 1;
  const uint8_t *p = CFDataGetBytePtr(cfg);
  CFIndex n = CFDataGetLength(cfg);
  if (codec == 'vp09' && n >= 7) {
    int profile = p[4], depth = p[6] >> 4, chroma = (p[6] >> 1) & 7;
    *full_range = p[6] & 1;
    return profile == 0 && depth == 8 && chroma <= 1;
  }
  if (codec == 'av01' && n >= 4) {
    int profile = p[1] >> 5, hbd = (p[2] >> 6) & 1, mono = (p[2] >> 4) & 1, ssx = (p[2] >> 3) & 1, ssy = (p[2] >> 2) & 1;
    return profile == 0 && !hbd && !mono && ssx && ssy;
  }
  return 1;
}

static CFDataRef config_atom(CMVideoFormatDescriptionRef f, FourCharCode codec) {
  CFDictionaryRef atoms = CMFormatDescriptionGetExtension(f, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
  if (!atoms || CFGetTypeID(atoms) != CFDictionaryGetTypeID()) return NULL;
  CFDataRef d = CFDictionaryGetValue(atoms, codec == 'av01' ? CFSTR("av1C") : CFSTR("vpcC"));
  return d && CFGetTypeID(d) == CFDataGetTypeID() ? d : NULL;
}

static Boolean d_accept(VTVideoDecoderRef d, CMFormatDescriptionRef f) {
  FourCharCode c = CMFormatDescriptionGetMediaSubType(f);
  int fr;
  return (c == 'vp09' || c == 'av01') && check_config(c, config_atom(f, c), &fr);
}

static OSStatus d_start(VTVideoDecoderRef d, VTVideoDecoderSession sess, CMVideoFormatDescriptionRef f) {
  Storage *s = ST(d);
  char b[5];
  s->session = sess;
  s->fmt = (CMVideoFormatDescriptionRef)CFRetain(f);
  s->codec = CMFormatDescriptionGetMediaSubType(f);
  CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(f);
  CFDataRef cfg = config_atom(f, s->codec);
  int full = 0;
  if (!check_config(s->codec, cfg, &full)) {
    os_log(L(), "VCNDEC StartSession %{public}s %dx%d: not 8-bit 4:2:0 profile 0, refused", cc(s->codec, b), dim.width, dim.height);
    return kErrUnsupportedFormat;
  }
  char err[256] = "";
  // av1C goes to libavcodec as extradata; vpcC carries nothing the VP9 decoder needs.
  s->dec = vcn_open(s->codec, dim.width, dim.height, s->codec == 'av01' && cfg ? CFDataGetBytePtr(cfg) : NULL,
                    s->codec == 'av01' && cfg ? (size_t)CFDataGetLength(cfg) : 0, err, sizeof err);
  if (!s->dec) {
    os_log_error(L(), "VCNDEC StartSession %{public}s %dx%d: %{public}s", cc(s->codec, b), dim.width, dim.height, err);
    return kErrDecoderFailed;
  }
  int32_t fmt = full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
  int32_t w = dim.width, h = dim.height;
  CFNumberRef nf = CFNumberCreate(NULL, kCFNumberSInt32Type, &fmt), nw = CFNumberCreate(NULL, kCFNumberSInt32Type, &w),
              nh = CFNumberCreate(NULL, kCFNumberSInt32Type, &h);
  CFDictionaryRef io = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void *k[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey,
                     kCVPixelBufferIOSurfacePropertiesKey, kCVPixelBufferMetalCompatibilityKey};
  const void *v[] = {nf, nw, nh, io, kCFBooleanTrue};
  CFDictionaryRef attrs = CFDictionaryCreate(NULL, k, v, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  OSStatus e = VTDecoderSessionSetPixelBufferAttributes(sess, attrs);
  CFRelease(attrs); CFRelease(io); CFRelease(nf); CFRelease(nw); CFRelease(nh);

  // colour tags from the format description go onto every output buffer
  CFMutableDictionaryRef col = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const CFStringRef keys[] = {kCVImageBufferYCbCrMatrixKey, kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferChromaLocationTopFieldKey};
  for (int i = 0; i < 4; i++) {
    CFTypeRef x = CMFormatDescriptionGetExtension(f, keys[i]);
    if (x) CFDictionarySetValue(col, keys[i], x);
  }
  s->color = col;
  os_log(L(), "VCNDEC StartSession %{public}s %dx%d full-range %d on the 890M VCN (pixel buffer attrs %d)",
         cc(s->codec, b), dim.width, dim.height, full, (int)e);
  return 0;
}

static OSStatus d_decode(VTVideoDecoderRef d, VTVideoDecoderFrame fr, CMSampleBufferRef sb, VTDecodeFrameFlags fl,
                         VTDecodeInfoFlags *info) {
  Storage *s = ST(d);
  if (info) *info = 0;
  pthread_mutex_lock(&s->lock);
  OSStatus st = 0;
  CVPixelBufferRef out = NULL;
  CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
  size_t n = bb ? CMBlockBufferGetDataLength(bb) : 0;
  s->in++;
  if (!s->dec || !n) { st = s->dec ? kErrBadData : kErrDecoderFailed; goto emit; }
  if (n > s->bufn) { free(s->buf); s->bufn = n + 65536; s->buf = malloc(s->bufn); }
  if (CMBlockBufferCopyDataBytes(bb, 0, n, s->buf)) { st = kErrBadData; goto emit; }
  CMTime t = CMSampleBufferGetPresentationTimeStamp(sb);
  int64_t pts = CMTIME_IS_VALID(t) ? CMTimeConvertScale(t, 1000000, kCMTimeRoundingMethod_Default).value : (int64_t)s->in;
  if (vcn_send(s->dec, s->buf, n, pts) < 0) { st = kErrBadData; goto emit; }
  // VP9 / AV1 here have no reordering: one shown frame per sample at most. Extra frames are dropped.
  for (;;) {
    CVPixelBufferRef pb = NULL;
    int64_t opts;
    int r = vcn_receive(s->dec, VTDecoderSessionGetPixelBufferPool(s->session), &pb, &opts);
    if (r < 0) { st = kErrDecoderFailed; break; }
    if (!r) break;
    if (!out) out = pb; else CVPixelBufferRelease(pb);
  }
emit:
  if (out && s->color) CVBufferSetAttachments(out, s->color, kCVAttachmentMode_ShouldPropagate);
  if (st) {
    s->errors++;
    if (s->errors <= 5) os_log_error(L(), "VCNDEC decode #%llu (%zu bytes): %{public}s", s->in, n, vcn_last_error(s->dec));
  }
  VTDecodeInfoFlags fi = 0;
  if (!st && !out) { fi = kVTDecodeInfo_FrameDropped; s->dropped++; }
  if (out) s->out++;
  if (s->out == 1 && out) os_log(L(), "VCNDEC first frame out (%zu bytes in)", n);
  pthread_mutex_unlock(&s->lock);
  VTDecoderSessionEmitDecodedFrame(s->session, fr, st, fi, out);
  if (out) CVPixelBufferRelease(out);
  return 0;
}

static OSStatus d_props(VTVideoDecoderRef d, CFDictionaryRef *out) {
  *out = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  return 0;
}
static OSStatus d_setprops(VTVideoDecoderRef d, CFDictionaryRef p) { return 0; }
static OSStatus d_finish(VTVideoDecoderRef d) { return 0; } // frames are emitted inside DecodeFrame

static const CMBaseClass kBase = {1, sizeof(Storage), NULL, b_invalidate, b_finalize, b_desc, b_copyProperty, b_setProperty, NULL, NULL, {0}};
static const VTVideoDecoderClass kDer = {1, d_start, d_decode, d_props, d_setprops, NULL, d_accept, d_finish, {0}};
static const VTVideoDecoderVTable kVT = {NULL, &kBase, &kDer};

__attribute__((visibility("default")))
OSStatus VCNDec_CreateInstance(FourCharCode codec, CFAllocatorRef alloc, VTVideoDecoderRef *out) {
  char b[5];
  if (codec != 'vp09' && codec != 'av01') return kErrNoDecoder;
  if (access("/Library/NullMoth/vcndec-off", F_OK) == 0) {
    os_log(L(), "VCNDEC CreateInstance %{public}s refused (/Library/NullMoth/vcndec-off)", cc(codec, b));
    return kErrNoDecoder;
  }
  OSStatus e = CMDerivedObjectCreate(alloc, &kVT, VTVideoDecoderGetClassID(), out);
  if (e) { os_log_error(L(), "VCNDEC CMDerivedObjectCreate failed %d", (int)e); return e; }
  Storage *s = ST(*out);
  pthread_mutex_init(&s->lock, NULL);
  os_log(L(), "VCNDEC CreateInstance %{public}s (pid %d)", cc(codec, b), getpid());
  return 0;
}

// In-process registration for tests (the bundle path needs /System/Library/Video/Plug-Ins).
__attribute__((visibility("default"))) void VCNDec_RegisterInProcess(void) {
  FourCharCode c[] = {'vp09', 'av01'};
  int rating = 1000;
  CFNumberRef r = CFNumberCreate(NULL, kCFNumberIntType, &rating);
  const void *k[] = {kVTVideoDecoder_IsHardwareAccelerated, CFSTR("VTRating")}, *v[] = {kCFBooleanTrue, r};
  CFDictionaryRef info = CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  for (int i = 0; i < 2; i++) VTRegisterVideoDecoderWithInfo(c[i], info, (void *)VCNDec_CreateInstance);
  CFRelease(info);
  CFRelease(r);
}
