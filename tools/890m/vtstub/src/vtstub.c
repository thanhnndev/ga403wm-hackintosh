// SPDX-License-Identifier: BSD-3-Clause-Clear
// VTStub: logging-only VideoToolbox decoder plugin (probe loading/selection rules).
// Layout reversed from /System/Library/Video/Plug-Ins/AV1DecoderSW.bundle (Tahoe 26.6/26.7).
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <os/log.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

typedef struct OpaqueCMBaseObject *CMBaseObjectRef;
typedef struct OpaqueVTVideoDecoder *VTVideoDecoderRef;
typedef struct OpaqueVTVideoDecoderSession *VTVideoDecoderSession;
typedef struct OpaqueVTVideoDecoderFrame *VTVideoDecoderFrame;
typedef const void *CMBaseClassID;

#pragma pack(push, 4)
typedef struct {
  uint32_t version;                      // 1
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
  uint32_t version;                      // 1 (AV1DecoderSW uses 3: +tile slots)
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
extern OSStatus VTRegisterVideoDecoder(FourCharCode, void *createFn);
extern OSStatus VTRegisterVideoDecoderWithInfo(FourCharCode, CFDictionaryRef, void *createFn);
extern const CFStringRef kVTVideoDecoder_IsHardwareAccelerated;

typedef struct { VTVideoDecoderSession session; CMVideoFormatDescriptionRef fmt; FourCharCode codec; uint64_t frames; } Storage;

static os_log_t L(void) { static os_log_t l; if (!l) l = os_log_create("com.ga403wm.vtstub", "decoder"); return l; }
static Storage *ST(VTVideoDecoderRef d) { return (Storage *)CMBaseObjectGetDerivedStorage(VTVideoDecoderGetCMBaseObject(d)); }
static const char *cc(FourCharCode c, char b[5]) { b[0]=c>>24; b[1]=c>>16; b[2]=c>>8; b[3]=c; b[4]=0; return b; }

__attribute__((constructor)) static void vtstub_loaded(void) {
  char p[1024] = {0};
  extern int proc_pidpath(int, void *, uint32_t); proc_pidpath(getpid(), p, sizeof p);
  os_log(L(), "VTSTUB loaded into pid %d %{public}s", getpid(), p);
}

static OSStatus b_invalidate(CMBaseObjectRef o) { os_log(L(), "VTSTUB invalidate"); return 0; }
static void b_finalize(CMBaseObjectRef o) { Storage *s = CMBaseObjectGetDerivedStorage(o); os_log(L(), "VTSTUB finalize frames=%llu", s->frames); if (s->fmt) CFRelease(s->fmt); }
static CFStringRef b_desc(CMBaseObjectRef o) { return CFStringCreateWithFormat(NULL, NULL, CFSTR("<VTStub decoder %p>"), o); }
static OSStatus b_copyProperty(CMBaseObjectRef o, CFStringRef key, CFAllocatorRef a, void *out) {
  char k[256] = "?"; CFStringGetCString(key, k, sizeof k, kCFStringEncodingUTF8);
  if (CFEqual(key, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder)) {
    *(CFTypeRef *)out = kCFBooleanTrue; os_log(L(), "VTSTUB copyProperty %{public}s -> true", k); return 0; }
  os_log(L(), "VTSTUB copyProperty %{public}s -> n/a", k);
  return -12783; // kCMBaseObjectError_ValueNotAvailable
}
static OSStatus b_setProperty(CMBaseObjectRef o, CFStringRef key, CFTypeRef v) {
  char k[256] = "?"; CFStringGetCString(key, k, sizeof k, kCFStringEncodingUTF8);
  os_log(L(), "VTSTUB setProperty %{public}s", k); return 0;
}

static OSStatus d_start(VTVideoDecoderRef d, VTVideoDecoderSession sess, CMVideoFormatDescriptionRef f) {
  Storage *s = ST(d); s->session = sess; s->fmt = (CMVideoFormatDescriptionRef)CFRetain(f);
  CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(f); char b[5];
  s->codec = CMFormatDescriptionGetMediaSubType(f);
  os_log(L(), "VTSTUB StartSession codec=%{public}s %dx%d", cc(s->codec, b), dim.width, dim.height);
  int32_t fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, w = dim.width, h = dim.height;
  CFNumberRef nf = CFNumberCreate(NULL, kCFNumberSInt32Type, &fmt), nw = CFNumberCreate(NULL, kCFNumberSInt32Type, &w), nh = CFNumberCreate(NULL, kCFNumberSInt32Type, &h);
  CFDictionaryRef io = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  const void *k[] = { kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey, kCVPixelBufferIOSurfacePropertiesKey };
  const void *v[] = { nf, nw, nh, io };
  CFDictionaryRef attrs = CFDictionaryCreate(NULL, k, v, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  OSStatus e = VTDecoderSessionSetPixelBufferAttributes(sess, attrs);
  os_log(L(), "VTSTUB SetPixelBufferAttributes -> %d", (int)e);
  CFRelease(attrs); CFRelease(io); CFRelease(nf); CFRelease(nw); CFRelease(nh);
  return 0;
}
static OSStatus d_decode(VTVideoDecoderRef d, VTVideoDecoderFrame fr, CMSampleBufferRef sb, VTDecodeFrameFlags fl, VTDecodeInfoFlags *info) {
  Storage *s = ST(d); s->frames++; if (info) *info = 0;
  if (s->frames <= 5 || s->frames % 100 == 0)
    os_log(L(), "VTSTUB DecodeFrame #%llu size=%zu flags=%#x", s->frames, CMSampleBufferGetTotalSampleSize(sb), fl);
  CVPixelBufferRef pb = NULL; OSStatus e = -1;
  CVPixelBufferPoolRef pool = VTDecoderSessionGetPixelBufferPool(s->session);
  if (pool) e = CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &pb);
  if (pb) { // solid magenta-ish: Y=105 Cb=212 Cr=234
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0); size_t yb = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), yh = CVPixelBufferGetHeightOfPlane(pb, 0);
    uint8_t *c = CVPixelBufferGetBaseAddressOfPlane(pb, 1); size_t cb = CVPixelBufferGetBytesPerRowOfPlane(pb, 1), ch = CVPixelBufferGetHeightOfPlane(pb, 1);
    memset(y, 105, yb * yh); for (size_t i = 0; i < cb * ch; i += 2) { c[i] = 212; c[i + 1] = 234; }
    CVPixelBufferUnlockBaseAddress(pb, 0);
  } else os_log(L(), "VTSTUB no pixel buffer (pool=%p err=%d)", pool, (int)e);
  OSStatus r = VTDecoderSessionEmitDecodedFrame(s->session, fr, pb ? 0 : -12911, 0, pb);
  if (s->frames <= 2) os_log(L(), "VTSTUB EmitDecodedFrame -> %d", (int)r);
  if (pb) CVPixelBufferRelease(pb);
  return 0;
}
static OSStatus d_props(VTVideoDecoderRef d, CFDictionaryRef *out) {
  os_log(L(), "VTSTUB CopySupportedPropertyDictionary");
  *out = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); return 0;
}
static OSStatus d_setprops(VTVideoDecoderRef d, CFDictionaryRef p) { os_log(L(), "VTSTUB SetProperties n=%ld", p ? CFDictionaryGetCount(p) : 0); return 0; }
static Boolean d_accept(VTVideoDecoderRef d, CMFormatDescriptionRef f) { os_log(L(), "VTSTUB CanAcceptFormatDescription"); return true; }
static OSStatus d_finish(VTVideoDecoderRef d) { os_log(L(), "VTSTUB FinishDelayedFrames"); return 0; }

static const CMBaseClass kBase = { 1, sizeof(Storage), NULL, b_invalidate, b_finalize, b_desc, b_copyProperty, b_setProperty, NULL, NULL, {0} };
static const VTVideoDecoderClass kDer = { 1, d_start, d_decode, d_props, d_setprops, NULL, d_accept, d_finish, {0} };
static const VTVideoDecoderVTable kVT = { NULL, &kBase, &kDer };

__attribute__((visibility("default")))
OSStatus VTStub_CreateInstance(FourCharCode codec, CFAllocatorRef alloc, VTVideoDecoderRef *out) {
  char b[5];
  // Opt-in gate: the stub only draws solid frames, so without the flag file it refuses and VideoToolbox moves on to
  // the next decoder (Apple's), keeping normal video playback intact. `touch /tmp/vtstub.on` to test, rm to stop.
  if (access("/tmp/vtstub.on", F_OK) != 0) {
    os_log(L(), "VTSTUB CreateInstance codec=%{public}s refused (no /tmp/vtstub.on)", cc(codec, b));
    return -12906;  // kVTCouldNotFindVideoDecoderErr
  }
  os_log(L(), "VTSTUB CreateInstance codec=%{public}s", cc(codec, b));
  OSStatus e = CMDerivedObjectCreate(alloc, &kVT, VTVideoDecoderGetClassID(), out);
  if (e) os_log_error(L(), "VTSTUB CMDerivedObjectCreate failed %d", (int)e);
  return e;
}
// For in-process tests without a bundle scan.
__attribute__((visibility("default"))) void VTStub_RegisterInProcess(void) {
  FourCharCode c[] = { 'avc1', 'hvc1', 'hev1', 'vp09', 'av01' };
  int rating = 1000; CFNumberRef r = CFNumberCreate(NULL, kCFNumberIntType, &rating);
  const void *k[] = { kVTVideoDecoder_IsHardwareAccelerated, CFSTR("VTRating") }, *v[] = { kCFBooleanTrue, r };
  CFDictionaryRef info = CFDictionaryCreate(NULL, k, v, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  int withInfo = getenv("VTSTUB_NOINFO") == NULL;
  for (int i = 0; i < 5; i++) {
    OSStatus e = withInfo ? VTRegisterVideoDecoderWithInfo(c[i], info, (void *)VTStub_CreateInstance) : VTRegisterVideoDecoder(c[i], (void *)VTStub_CreateInstance);
    os_log(L(), "VTSTUB register %d withInfo=%d -> %d", i, withInfo, (int)e); }
  CFRelease(info); CFRelease(r);
}
