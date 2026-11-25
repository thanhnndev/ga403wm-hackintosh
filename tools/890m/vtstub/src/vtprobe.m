// SPDX-License-Identifier: BSD-3-Clause-Clear
// vtprobe: which VideoToolbox decoder gets picked? usage:
//  vtprobe [--dir DIR] [--inproc BUNDLE] [--require|--enable|--none] [--id DECODERID] [--list] file.mp4 ...
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#include <dlfcn.h>
extern OSStatus VTRegisterVideoDecoderBundleDirectory(CFURLRef);
extern Boolean VTIsHardwareDecodeSupported(CMVideoCodecType);
extern OSStatus VTCopyVideoDecoderList(CFDictionaryRef, CFArrayRef *);
extern void VTRegisterSupplementalVideoDecoderIfAvailable(CMVideoCodecType);
extern OSStatus FigRegistryAddSearchPathWithOptions(CFTypeRef, CFURLRef, uint32_t);
extern OSStatus FigRegistryRescan(CFTypeRef);
extern OSStatus FigRegistryCopyItemList(CFTypeRef, CFArrayRef *);
// Tahoe 26.6 x86_64h only: VT's decoder FigRegistry global, relative to VTRegisterVideoDecoderBundleDirectory.
static CFTypeRef vtRegistry(void) { CFArrayRef l = NULL; VTCopyVideoDecoderList(NULL, &l); if (l) CFRelease(l);
  return *(CFTypeRef *)((char *)VTRegisterVideoDecoderBundleDirectory + (0x7FF8528CA3E8 - 0x7ff82487b76b)); }
static const char *cc(FourCharCode c){ static char b[5]; b[0]=c>>24;b[1]=c>>16;b[2]=c>>8;b[3]=c;b[4]=0; return b; }
static int gFrames; static uint8_t gY, gCb, gCr; static OSStatus gErr;
static void out(void *r, void *s, OSStatus st, VTDecodeInfoFlags f, CVImageBufferRef img, CMTime pts, CMTime d) {
  if (st) { gErr = st; return; } if (!img) return;
  if (gFrames++ == 0) { CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
    if (CVPixelBufferGetPlaneCount(img) >= 2) { size_t w = CVPixelBufferGetWidthOfPlane(img,0)/2, h = CVPixelBufferGetHeightOfPlane(img,0)/2;
      gY = ((uint8_t*)CVPixelBufferGetBaseAddressOfPlane(img,0))[h*CVPixelBufferGetBytesPerRowOfPlane(img,0)+w];
      uint8_t *c = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(img,1) + (h/2)*CVPixelBufferGetBytesPerRowOfPlane(img,1) + (w/2)*2; gCb=c[0]; gCr=c[1]; }
    printf("    first frame: %zux%zu fmt=%s centre YCbCr=%d,%d,%d%s\n", CVPixelBufferGetWidth(img), CVPixelBufferGetHeight(img),
      cc(CVPixelBufferGetPixelFormatType(img)), gY, gCb, gCr, (gY==105&&gCb==212&&gCr==234)?"  <== VTSTUB solid colour":"");
    CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly); }
}
int main(int argc, char **argv) { @autoreleasepool {
  int mode = 1; NSString *decID = nil; BOOL list = NO; NSMutableArray *files = [NSMutableArray array];
  for (int i = 1; i < argc; i++) { NSString *a = @(argv[i]);
    if ([a isEqual:@"--dir"]) { NSURL *u = [NSURL fileURLWithPath:@(argv[++i]) isDirectory:YES];
      printf("VTRegisterVideoDecoderBundleDirectory(%s) -> %d\n", argv[i], (int)VTRegisterVideoDecoderBundleDirectory((__bridge CFURLRef)u)); }
    else if ([a isEqual:@"--figdir"]) { NSURL *u = [NSURL fileURLWithPath:@(argv[++i]) isDirectory:YES]; CFTypeRef reg = vtRegistry();
      printf("VT registry %p (%s)\n", reg, reg ? [[(__bridge id)reg description] UTF8String] : "-");
      OSStatus e = FigRegistryAddSearchPathWithOptions(reg, (__bridge CFURLRef)u, getenv("FIGOPT") ? atoi(getenv("FIGOPT")) : 1); printf("FigRegistryAddSearchPathWithOptions -> %d, rescan -> %d\n", (int)e, (int)FigRegistryRescan(reg));
      CFArrayRef it = NULL; FigRegistryCopyItemList(reg, &it); printf("registry items: %ld\n", it ? CFArrayGetCount(it) : -1L);
      for (id x in (__bridge NSArray *)it) { NSString *d = [x description]; if ([d containsString:@"ga403"] || [d containsString:@"VTStub"]) printf("  %s\n", d.UTF8String); } }
    else if ([a isEqual:@"--inproc"]) { void *h = dlopen(argv[++i], RTLD_NOW); void (*r)(void) = h ? dlsym(h, "VTStub_RegisterInProcess") : NULL;
      printf("dlopen %s -> %p %s\n", argv[i], h, h ? "" : dlerror()); if (r) { r(); printf("VTRegisterVideoDecoder x4 done\n"); } }
    else if ([a isEqual:@"--supplemental"]) { VTRegisterSupplementalVideoDecoderIfAvailable('vp09'); VTRegisterSupplementalVideoDecoderIfAvailable('av01'); printf("supplemental vp09/av01 registered\n"); }
    else if ([a isEqual:@"--require"]) mode = 2; else if ([a isEqual:@"--enable"]) mode = 1; else if ([a isEqual:@"--none"]) mode = 0;
    else if ([a isEqual:@"--id"]) decID = @(argv[++i]); else if ([a isEqual:@"--list"]) list = YES; else [files addObject:a]; }
  CMVideoCodecType cs[] = { 'avc1', 'hvc1', 'vp09', 'av01' };
  for (int i = 0; i < 4; i++) printf("VTIsHardwareDecodeSupported(%s) = %d\n", cc(cs[i]), VTIsHardwareDecodeSupported(cs[i]));
  CFArrayRef dl = NULL; VTCopyVideoDecoderList(NULL, &dl);
  for (NSDictionary *d in (__bridge NSArray *)dl) { uint32_t c = [d[@"CodecType"] unsignedIntValue];
    if (!list && c != 'avc1' && c != 'hvc1' && c != 'vp09' && c != 'av01') continue;
    printf("  decoder %s id=%s hw=%s rating=%s name=%s\n", cc(c), [[d[@"DecoderID"] description] UTF8String], [[d[@"IsHardwareAccelerated"] description] UTF8String],
      [[d[@"PerformanceRating"] description] UTF8String], [[d[@"DisplayName"] ?: d[@"DecoderName"] description] UTF8String]); }
  if (dl) CFRelease(dl);
  for (NSString *f in files) {
    AVURLAsset *as = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:f] options:nil];
    AVAssetTrack *t = [[as tracksWithMediaType:AVMediaTypeVideo] firstObject]; if (!t) { printf("%s: no video track\n", f.UTF8String); continue; }
    CMVideoFormatDescriptionRef fd = (__bridge CMVideoFormatDescriptionRef)t.formatDescriptions.firstObject;
    printf("== %s codec=%s mode=%s%s%s\n", f.UTF8String, cc(CMFormatDescriptionGetMediaSubType(fd)), mode==2?"require-hw":mode==1?"enable-hw":"default", decID?" id=":"", decID?decID.UTF8String:"");
    NSMutableDictionary *spec = [NSMutableDictionary dictionary];
    if (mode >= 1) spec[(id)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = @YES;
    if (mode == 2) spec[(id)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] = @YES;
    if (decID) spec[@"DecoderID"] = decID;
    VTDecompressionOutputCallbackRecord cb = { out, NULL }; VTDecompressionSessionRef s = NULL;
    NSDictionary *pba = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) };
    OSStatus e = VTDecompressionSessionCreate(NULL, fd, (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)pba, &cb, &s);
    printf("    VTDecompressionSessionCreate -> %d\n", (int)e); if (e) continue;
    CFBooleanRef hw = NULL; VTSessionCopyProperty(s, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hw);
    printf("    UsingHardwareAcceleratedVideoDecoder = %s\n", hw ? (CFBooleanGetValue(hw) ? "true" : "false") : "(null)");
    AVAssetReader *r = [AVAssetReader assetReaderWithAsset:as error:nil];
    AVAssetReaderTrackOutput *o = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:t outputSettings:nil]; [r addOutput:o]; [r startReading];
    gFrames = 0; gErr = 0; int n = 0; CMSampleBufferRef sb;
    while ((sb = [o copyNextSampleBuffer]) && n < 120) { if (CMSampleBufferGetNumSamples(sb)) { VTDecompressionSessionDecodeFrame(s, sb, 0, NULL, NULL); n++; } CFRelease(sb); }
    VTDecompressionSessionWaitForAsynchronousFrames(s);
    printf("    submitted %d, got %d frames, last err %d\n", n, gFrames, (int)gErr);
    VTDecompressionSessionInvalidate(s); CFRelease(s);
  }
} return 0; }
