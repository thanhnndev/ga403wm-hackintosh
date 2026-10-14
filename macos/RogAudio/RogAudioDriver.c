// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// RogAudio.driver: CoreAudio AudioServerPlugIn that gives the daemon (macos/RogAudio/rogaudiod.c) four virtual devices:
//
//   "ROG Clear Mic"       input   mono 48 kHz   what applications record; fed by "ROG Mic Feed"
//   "ROG Mic Feed"        output  mono 48 kHz   hidden; rogaudiod writes the denoised microphone here
//   "ROG Speakers"        output  stereo 48 kHz what applications play to; has a volume and a mute control
//   "ROG Speakers Tap"    input   stereo 48 kHz hidden; rogaudiod reads it, runs the sound chain, plays on the real speakers
//
// Each pair is a loopback through a ring buffer indexed by sample time, the same idea as the NullAudio sample of Apple's
// "Creating an Audio Server Driver Plug-in" (the plug-in object model and the zero time stamp scheme follow that document).
// All devices share one clock, so a writer and a reader of a pair see the same sample time axis and the loopback latency
// is the writer's lead time.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define kRate 48000.0
#define kRingFrames 16384u                 // power of two
#define kZeroTsPeriod 512u
#define kMaxFrames 4096u

enum {
    kObjPlugIn = kAudioObjectPlugInObject,   // 1
    kObjMic = 2, kObjMicStream = 3,            // ROG Clear Mic (input)
    kObjMicFeed = 4, kObjMicFeedStream = 5,    // ROG Mic Feed (output, hidden)
    kObjSpk = 6, kObjSpkStream = 7, kObjSpkVol = 8, kObjSpkMute = 9,   // ROG Speakers (output)
    kObjTap = 10, kObjTapStream = 11,          // ROG Speakers Tap (input, hidden)
};

typedef struct {
    AudioObjectID dev, stream, vol, mute;
    const char *name, *uid, *model;
    int input;                // 1: input device, 0: output
    int hidden;
    UInt32 channels;
    int ring;                 // ring index: 0 mic pair, 1 speaker pair
    // controls (speakers)
    _Atomic uint32_t volBits; // Float32 scalar 0..1
    _Atomic int muted;
    _Atomic int running;      // clients with IO started
} Dev;

static Dev gDevs[4] = {
    { .dev = kObjMic, .stream = kObjMicStream, .name = "ROG Clear Mic", .uid = "com.itlmt7925.rogaudio.mic",
      .model = "RogAudioMic", .input = 1, .hidden = 0, .channels = 1, .ring = 0 },
    { .dev = kObjMicFeed, .stream = kObjMicFeedStream, .name = "ROG Mic Feed", .uid = "com.itlmt7925.rogaudio.micfeed",
      .model = "RogAudioMicFeed", .input = 0, .hidden = 1, .channels = 1, .ring = 0 },
    { .dev = kObjSpk, .stream = kObjSpkStream, .vol = kObjSpkVol, .mute = kObjSpkMute, .name = "ROG Speakers",
      .uid = "com.itlmt7925.rogaudio.speakers", .model = "RogAudioSpeakers", .input = 0, .hidden = 0, .channels = 2, .ring = 1 },
    { .dev = kObjTap, .stream = kObjTapStream, .name = "ROG Speakers Tap", .uid = "com.itlmt7925.rogaudio.tap",
      .model = "RogAudioTap", .input = 1, .hidden = 1, .channels = 2, .ring = 1 },
};
#define kNumDevs 4

static float *gRing[2];                       // [mic: 1 ch][speakers: 2 ch], kRingFrames frames each
static pthread_mutex_t gClockLock = PTHREAD_MUTEX_INITIALIZER;
static UInt64 gAnchorHost, gNumTs;
static UInt32 gRunning;                       // total started IO clients across devices
static Float64 gTicksPerFrame;
static AudioServerPlugInHostRef gHost;
static UInt32 gRefCount = 1;

static Dev *devById(AudioObjectID id)
{
    for (int i = 0; i < kNumDevs; i++) if (gDevs[i].dev == id) return &gDevs[i];
    return NULL;
}
static Dev *devByStream(AudioObjectID id)
{
    for (int i = 0; i < kNumDevs; i++) if (gDevs[i].stream == id) return &gDevs[i];
    return NULL;
}
static Dev *devByControl(AudioObjectID id)
{
    for (int i = 0; i < kNumDevs; i++) if (gDevs[i].vol == id || gDevs[i].mute == id) return &gDevs[i];
    return NULL;
}
static Float32 getVol(Dev *d) { uint32_t b = atomic_load(&d->volBits); Float32 f; memcpy(&f, &b, 4); return f; }
static void setVol(Dev *d, Float32 f) { uint32_t b; memcpy(&b, &f, 4); atomic_store(&d->volBits, b); }

// ---- COM-ish plumbing --------------------------------------------------------------------------------------------------
static HRESULT QueryInterface(void *d, REFIID iid, LPVOID *out)
{
    CFUUIDRef want = CFUUIDCreateFromUUIDBytes(NULL, iid);
    HRESULT rc = E_NOINTERFACE;
    if (CFEqual(want, IUnknownUUID) || CFEqual(want, kAudioServerPlugInDriverInterfaceUUID)) {
        __sync_fetch_and_add(&gRefCount, 1);
        *out = d;
        rc = 0;
    }
    CFRelease(want);
    return rc;
}
static ULONG AddRef(void *d) { (void)d; return __sync_add_and_fetch(&gRefCount, 1); }
static ULONG Release(void *d) { (void)d; return __sync_sub_and_fetch(&gRefCount, 1); }

static OSStatus Initialize(AudioServerPlugInDriverRef d, AudioServerPlugInHostRef host)
{
    (void)d;
    gHost = host;
    struct mach_timebase_info tb;
    mach_timebase_info(&tb);
    gTicksPerFrame = (1e9 / kRate) * ((Float64)tb.denom / (Float64)tb.numer);
    for (int i = 0; i < 2; i++) gRing[i] = calloc(kRingFrames * (i ? 2 : 1), sizeof(float));
    for (int i = 0; i < kNumDevs; i++) setVol(&gDevs[i], 1.0f);
    return 0;
}

static OSStatus CreateDevice(AudioServerPlugInDriverRef d, CFDictionaryRef desc, const AudioServerPlugInClientInfo *c, AudioObjectID *o)
{ (void)d; (void)desc; (void)c; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus DestroyDevice(AudioServerPlugInDriverRef d, AudioObjectID o) { (void)d; (void)o; return kAudioHardwareUnsupportedOperationError; }
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c) { (void)d; (void)o; (void)c; return 0; }
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef d, AudioObjectID o, const AudioServerPlugInClientInfo *c) { (void)d; (void)o; (void)c; return 0; }
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *i) { (void)d; (void)o; (void)a; (void)i; return 0; }
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef d, AudioObjectID o, UInt64 a, void *i) { (void)d; (void)o; (void)a; (void)i; return 0; }

// ---- properties --------------------------------------------------------------------------------------------------------
enum { kClsPlugIn, kClsDevice, kClsStream, kClsVolume, kClsMute, kClsNone };
static int classOf(AudioObjectID id)
{
    if (id == kObjPlugIn) return kClsPlugIn;
    if (devById(id)) return kClsDevice;
    if (devByStream(id)) return kClsStream;
    Dev *c = devByControl(id);
    if (c) return c->vol == id ? kClsVolume : kClsMute;
    return kClsNone;
}

// reply helpers
#define PUT(type, val) do { if (inDataSize < sizeof(type)) return kAudioHardwareBadPropertySizeError; *(type *)outData = (val); *outDataSize = sizeof(type); return 0; } while (0)
#define PUT_CF(str) do { if (inDataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError; *(CFStringRef *)outData = CFStringCreateWithCString(NULL, (str), kCFStringEncodingUTF8); *outDataSize = sizeof(CFStringRef); return 0; } while (0)

static UInt32 devOwned(Dev *d, AudioObjectID *ids)    // streams + controls owned by a device
{
    UInt32 n = 0;
    ids[n++] = d->stream;
    if (d->vol) { ids[n++] = d->vol; ids[n++] = d->mute; }
    return n;
}

static Boolean has(AudioObjectID id, const AudioObjectPropertyAddress *a)
{
    switch (classOf(id)) {
    case kClsPlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyManufacturer: case kAudioObjectPropertyOwnedObjects: case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice: return true;
        }
        return false;
    case kClsDevice:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID: case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices: case kAudioDevicePropertyClockDomain: case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning: case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyStreams: case kAudioObjectPropertyControlList: case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyNominalSampleRate: case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden: case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyPreferredChannelsForStereo: return true;
        }
        return false;
    case kClsStream:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection: case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel: case kAudioStreamPropertyLatency: case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: return true;
        }
        return false;
    case kClsVolume:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects: case kAudioControlPropertyScope: case kAudioControlPropertyElement:
        case kAudioLevelControlPropertyScalarValue: case kAudioLevelControlPropertyDecibelValue:
        case kAudioLevelControlPropertyDecibelRange: case kAudioLevelControlPropertyConvertScalarToDecibels:
        case kAudioLevelControlPropertyConvertDecibelsToScalar: return true;
        }
        return false;
    case kClsMute:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass: case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects: case kAudioControlPropertyScope: case kAudioControlPropertyElement:
        case kAudioBooleanControlPropertyValue: return true;
        }
        return false;
    }
    return false;
}

static Boolean HasProperty(AudioServerPlugInDriverRef d, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a)
{ (void)d; (void)pid; return has(id, a); }

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef d, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a, Boolean *out)
{
    (void)d; (void)pid;
    if (!has(id, a)) return kAudioHardwareUnknownPropertyError;
    *out = false;
    switch (classOf(id)) {
    case kClsVolume: *out = a->mSelector == kAudioLevelControlPropertyScalarValue || a->mSelector == kAudioLevelControlPropertyDecibelValue; break;
    case kClsMute: *out = a->mSelector == kAudioBooleanControlPropertyValue; break;
    case kClsStream: *out = a->mSelector == kAudioStreamPropertyIsActive; break;
    }
    return 0;
}

static AudioStreamBasicDescription fmtOf(const Dev *d)
{
    AudioStreamBasicDescription f = { 0 };
    f.mSampleRate = kRate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    f.mBytesPerPacket = 4 * d->channels;
    f.mFramesPerPacket = 1;
    f.mBytesPerFrame = 4 * d->channels;
    f.mChannelsPerFrame = d->channels;
    f.mBitsPerChannel = 32;
    return f;
}

static OSStatus sizeAndData(AudioObjectID id, const AudioObjectPropertyAddress *a, UInt32 qualSize, const void *qual,
                            UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    int cls = classOf(id);
    Dev *dev = devById(id), *st = devByStream(id), *ctl = devByControl(id);
    AudioObjectID tmp[3];

    // list-valued properties are handled with a bounded copy
    #define PUT_LIST(arr, n) do { UInt32 want_ = (n) * sizeof(AudioObjectID); UInt32 cp_ = inDataSize < want_ ? inDataSize / sizeof(AudioObjectID) * sizeof(AudioObjectID) : want_; \
        memcpy(outData, (arr), cp_); *outDataSize = cp_; return 0; } while (0)

    switch (cls) {
    case kClsPlugIn:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioPlugInClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, kAudioObjectUnknown);
        case kAudioObjectPropertyManufacturer: PUT_CF("itlmt7925");
        case kAudioObjectPropertyOwnedObjects: case kAudioPlugInPropertyDeviceList: {
            AudioObjectID ids[kNumDevs];
            for (int i = 0; i < kNumDevs; i++) ids[i] = gDevs[i].dev;
            PUT_LIST(ids, kNumDevs);
        }
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            AudioObjectID r = kAudioObjectUnknown;
            if (qualSize == sizeof(CFStringRef) && qual) {
                CFStringRef uid = *(CFStringRef *)qual;
                for (int i = 0; i < kNumDevs; i++) {
                    CFStringRef s = CFStringCreateWithCString(NULL, gDevs[i].uid, kCFStringEncodingUTF8);
                    if (CFStringCompare(uid, s, 0) == kCFCompareEqualTo) r = gDevs[i].dev;
                    CFRelease(s);
                }
            }
            PUT(AudioObjectID, r);
        }
        }
        break;

    case kClsDevice: {
        const Dev *d = dev;
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioDeviceClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, kObjPlugIn);
        case kAudioObjectPropertyName: PUT_CF(d->name);
        case kAudioObjectPropertyManufacturer: PUT_CF("itlmt7925");
        case kAudioDevicePropertyDeviceUID: PUT_CF(d->uid);
        case kAudioDevicePropertyModelUID: PUT_CF(d->model);
        case kAudioDevicePropertyTransportType: PUT(UInt32, kAudioDeviceTransportTypeVirtual);
        case kAudioDevicePropertyClockDomain: PUT(UInt32, 0);
        case kAudioDevicePropertyDeviceIsAlive: PUT(UInt32, 1);
        case kAudioDevicePropertyDeviceIsRunning: PUT(UInt32, atomic_load(&dev->running) > 0);
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: PUT(UInt32, !d->hidden);
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: PUT(UInt32, !d->hidden && !d->input ? 1 : 0);
        case kAudioDevicePropertyLatency: PUT(UInt32, 0);
        case kAudioDevicePropertySafetyOffset: PUT(UInt32, 0);
        case kAudioDevicePropertyIsHidden: PUT(UInt32, d->hidden);
        case kAudioDevicePropertyZeroTimeStampPeriod: PUT(UInt32, kZeroTsPeriod);
        case kAudioDevicePropertyNominalSampleRate: PUT(Float64, kRate);
        case kAudioDevicePropertyRelatedDevices: PUT(AudioObjectID, d->dev);
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            if (inDataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            AudioValueRange r = { kRate, kRate };
            memcpy(outData, &r, sizeof(r)); *outDataSize = sizeof(r); return 0;
        }
        case kAudioDevicePropertyPreferredChannelsForStereo: {
            if (inDataSize < 2 * sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            UInt32 ch[2] = { 1, d->channels > 1 ? 2 : 1 };
            memcpy(outData, ch, sizeof(ch)); *outDataSize = sizeof(ch); return 0;
        }
        case kAudioObjectPropertyOwnedObjects: {
            UInt32 n = devOwned(dev, tmp);
            PUT_LIST(tmp, n);
        }
        case kAudioDevicePropertyStreams: {
            // global scope or the scope matching the stream direction
            int wantIn = a->mScope == kAudioObjectPropertyScopeInput, wantOut = a->mScope == kAudioObjectPropertyScopeOutput;
            UInt32 n = 0;
            if (a->mScope == kAudioObjectPropertyScopeGlobal || (wantIn && d->input) || (wantOut && !d->input)) tmp[n++] = d->stream;
            PUT_LIST(tmp, n);
        }
        case kAudioObjectPropertyControlList: {
            UInt32 n = 0;
            if (d->vol) { tmp[n++] = d->vol; tmp[n++] = d->mute; }
            PUT_LIST(tmp, n);
        }
        }
        break;
    }

    case kClsStream: {
        const Dev *d = st;
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioStreamClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, d->dev);
        case kAudioStreamPropertyIsActive: PUT(UInt32, 1);
        case kAudioStreamPropertyDirection: PUT(UInt32, d->input ? 1 : 0);
        case kAudioStreamPropertyTerminalType: PUT(UInt32, d->input ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker);
        case kAudioStreamPropertyStartingChannel: PUT(UInt32, 1);
        case kAudioStreamPropertyLatency: PUT(UInt32, 0);
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: {
            AudioStreamBasicDescription f = fmtOf(d);
            PUT(AudioStreamBasicDescription, f);
        }
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: {
            if (inDataSize < sizeof(AudioStreamRangedDescription)) return kAudioHardwareBadPropertySizeError;
            AudioStreamRangedDescription r = { fmtOf(d), { kRate, kRate } };
            memcpy(outData, &r, sizeof(r)); *outDataSize = sizeof(r); return 0;
        }
        }
        break;
    }

    case kClsVolume: {
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioLevelControlClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioVolumeControlClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, ctl->dev);
        case kAudioObjectPropertyOwnedObjects: *outDataSize = 0; return 0;
        case kAudioControlPropertyScope: PUT(AudioObjectPropertyScope, kAudioObjectPropertyScopeOutput);
        case kAudioControlPropertyElement: PUT(AudioObjectPropertyElement, kAudioObjectPropertyElementMain);
        case kAudioLevelControlPropertyScalarValue: PUT(Float32, getVol(ctl));
        case kAudioLevelControlPropertyDecibelValue: PUT(Float32, -64.0f + 64.0f * getVol(ctl));
        case kAudioLevelControlPropertyDecibelRange: {
            if (inDataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            AudioValueRange r = { -64.0, 0.0 };
            memcpy(outData, &r, sizeof(r)); *outDataSize = sizeof(r); return 0;
        }
        case kAudioLevelControlPropertyConvertScalarToDecibels: {
            if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
            Float32 s = *(Float32 *)outData;
            s = s < 0 ? 0 : (s > 1 ? 1 : s);
            *(Float32 *)outData = -64.0f + 64.0f * s; *outDataSize = sizeof(Float32); return 0;
        }
        case kAudioLevelControlPropertyConvertDecibelsToScalar: {
            if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
            Float32 db = *(Float32 *)outData;
            db = db < -64 ? -64 : (db > 0 ? 0 : db);
            *(Float32 *)outData = (db + 64.0f) / 64.0f; *outDataSize = sizeof(Float32); return 0;
        }
        }
        break;
    }

    case kClsMute:
        switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: PUT(AudioClassID, kAudioBooleanControlClassID);
        case kAudioObjectPropertyClass: PUT(AudioClassID, kAudioMuteControlClassID);
        case kAudioObjectPropertyOwner: PUT(AudioObjectID, ctl->dev);
        case kAudioObjectPropertyOwnedObjects: *outDataSize = 0; return 0;
        case kAudioControlPropertyScope: PUT(AudioObjectPropertyScope, kAudioObjectPropertyScopeOutput);
        case kAudioControlPropertyElement: PUT(AudioObjectPropertyElement, kAudioObjectPropertyElementMain);
        case kAudioBooleanControlPropertyValue: PUT(UInt32, atomic_load(&ctl->muted) ? 1 : 0);
        }
        break;
    }
    return kAudioHardwareUnknownPropertyError;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef d, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a,
                                    UInt32 qualSize, const void *qual, UInt32 *outSize)
{
    (void)d; (void)pid;
    if (!has(id, a)) return kAudioHardwareUnknownPropertyError;
    // measure with a scratch buffer: simple and keeps one source of truth for the sizes
    uint8_t scratch[256];
    UInt32 n = 0;
    memset(scratch, 0, sizeof(scratch));
    if ((a->mSelector == kAudioLevelControlPropertyConvertScalarToDecibels) || (a->mSelector == kAudioLevelControlPropertyConvertDecibelsToScalar)) {
        *outSize = sizeof(Float32);
        return 0;
    }
    OSStatus rc = sizeAndData(id, a, qualSize, qual, sizeof(scratch), &n, scratch);
    if (rc) return rc;
    // CFStrings returned by sizeAndData are owned by the scratch copy; release them
    if (n == sizeof(CFStringRef)) {
        switch (a->mSelector) {
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer: case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID: { CFStringRef s; memcpy(&s, scratch, sizeof(s)); if (s) CFRelease(s); break; }
        }
    }
    *outSize = n;
    return 0;
}

static OSStatus GetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a,
                                UInt32 qualSize, const void *qual, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    (void)d; (void)pid;
    if (!has(id, a)) return kAudioHardwareUnknownPropertyError;
    // the convert properties take their input in the data buffer
    if (a->mSelector == kAudioLevelControlPropertyConvertScalarToDecibels || a->mSelector == kAudioLevelControlPropertyConvertDecibelsToScalar) {
        if (inDataSize < sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
    }
    return sizeAndData(id, a, qualSize, qual, inDataSize, outDataSize, outData);
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef d, AudioObjectID id, pid_t pid, const AudioObjectPropertyAddress *a,
                                UInt32 qualSize, const void *qual, UInt32 size, const void *data)
{
    (void)d; (void)pid; (void)qualSize; (void)qual;
    Dev *c = devByControl(id);
    if (c && classOf(id) == kClsVolume) {
        Float32 v;
        if (size != sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
        memcpy(&v, data, sizeof(v));
        if (a->mSelector == kAudioLevelControlPropertyDecibelValue) v = (v + 64.0f) / 64.0f;
        else if (a->mSelector != kAudioLevelControlPropertyScalarValue) return kAudioHardwareUnknownPropertyError;
        v = v < 0 ? 0 : (v > 1 ? 1 : v);
        setVol(c, v);
        AudioObjectPropertyAddress ch[2] = {
            { kAudioLevelControlPropertyScalarValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain },
            { kAudioLevelControlPropertyDecibelValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain } };
        if (gHost) gHost->PropertiesChanged(gHost, id, 2, ch);
        return 0;
    }
    if (c && classOf(id) == kClsMute && a->mSelector == kAudioBooleanControlPropertyValue) {
        if (size != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        UInt32 m; memcpy(&m, data, sizeof(m));
        atomic_store(&c->muted, m ? 1 : 0);
        AudioObjectPropertyAddress ch = { kAudioBooleanControlPropertyValue, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        if (gHost) gHost->PropertiesChanged(gHost, id, 1, &ch);
        return 0;
    }
    if (devByStream(id) && a->mSelector == kAudioStreamPropertyIsActive) return 0;
    return kAudioHardwareUnsupportedOperationError;
}

// ---- IO ----------------------------------------------------------------------------------------------------------------
static OSStatus StartIO(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client)
{
    (void)d; (void)client;
    Dev *dev = devById(id);
    if (!dev) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gClockLock);
    if (gRunning == 0) {
        gNumTs = 0;
        gAnchorHost = mach_absolute_time();
        for (int i = 0; i < 2; i++) memset(gRing[i], 0, kRingFrames * (i ? 2 : 1) * sizeof(float));
    }
    gRunning++;
    atomic_fetch_add(&dev->running, 1);
    pthread_mutex_unlock(&gClockLock);
    return 0;
}

static OSStatus StopIO(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client)
{
    (void)d; (void)client;
    Dev *dev = devById(id);
    if (!dev) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&gClockLock);
    if (gRunning) gRunning--;
    if (atomic_load(&dev->running) > 0) atomic_fetch_sub(&dev->running, 1);
    pthread_mutex_unlock(&gClockLock);
    return 0;
}

static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client, Float64 *outSample, UInt64 *outHost, UInt64 *outSeed)
{
    (void)d; (void)id; (void)client;
    pthread_mutex_lock(&gClockLock);
    UInt64 now = mach_absolute_time();
    Float64 perPeriod = gTicksPerFrame * kZeroTsPeriod;
    UInt64 next = gAnchorHost + (UInt64)((gNumTs + 1) * perPeriod);
    if (next <= now) gNumTs++;
    *outSample = (Float64)gNumTs * kZeroTsPeriod;
    *outHost = gAnchorHost + (UInt64)(gNumTs * perPeriod);
    *outSeed = 1;
    pthread_mutex_unlock(&gClockLock);
    return 0;
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client, UInt32 op, Boolean *will, Boolean *inPlace)
{
    (void)d; (void)id; (void)client;
    *will = (op == kAudioServerPlugInIOOperationReadInput || op == kAudioServerPlugInIOOperationWriteMix);
    *inPlace = true;
    return 0;
}
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo *ci)
{ (void)d; (void)id; (void)client; (void)op; (void)n; (void)ci; return 0; }
static OSStatus EndIOOperation(AudioServerPlugInDriverRef d, AudioObjectID id, UInt32 client, UInt32 op, UInt32 n, const AudioServerPlugInIOCycleInfo *ci)
{ (void)d; (void)id; (void)client; (void)op; (void)n; (void)ci; return 0; }

static OSStatus DoIOOperation(AudioServerPlugInDriverRef d, AudioObjectID id, AudioObjectID stream, UInt32 client, UInt32 op, UInt32 frames,
                              const AudioServerPlugInIOCycleInfo *ci, void *main, void *second)
{
    (void)d; (void)id; (void)client; (void)second;
    Dev *dev = devByStream(stream);
    if (!dev) return kAudioHardwareBadObjectError;
    float *ring = gRing[dev->ring];
    UInt32 ch = dev->channels;
    if (frames > kMaxFrames) return kAudioHardwareIllegalOperationError;

    if (op == kAudioServerPlugInIOOperationReadInput && dev->input) {
        UInt64 t = (UInt64)ci->mInputTime.mSampleTime;
        float *out = main;
        for (UInt32 i = 0; i < frames; i++) {
            UInt32 slot = (UInt32)((t + i) & (kRingFrames - 1));
            for (UInt32 c = 0; c < ch; c++) { out[i * ch + c] = ring[slot * ch + c]; ring[slot * ch + c] = 0; }
        }
        return 0;
    }
    if (op == kAudioServerPlugInIOOperationWriteMix && !dev->input) {
        UInt64 t = (UInt64)ci->mOutputTime.mSampleTime;
        const float *in = main;
        float g = 1.0f;
        if (dev->vol) {
            float v = getVol(dev);
            // taper: -64 dB .. 0 dB, same mapping the volume control reports
            g = v <= 0.0f ? 0.0f : powf(10.0f, (-64.0f + 64.0f * v) / 20.0f);
            if (atomic_load(&dev->muted)) g = 0.0f;
        }
        for (UInt32 i = 0; i < frames; i++) {
            UInt32 slot = (UInt32)((t + i) & (kRingFrames - 1));
            for (UInt32 c = 0; c < ch; c++) ring[slot * ch + c] = in[i * ch + c] * g;
        }
        return 0;
    }
    return 0;
}

// ---- factory -----------------------------------------------------------------------------------------------------------
static AudioServerPlugInDriverInterface gInterface = {
    NULL, QueryInterface, AddRef, Release, Initialize, CreateDevice, DestroyDevice, AddDeviceClient, RemoveDeviceClient,
    PerformDeviceConfigurationChange, AbortDeviceConfigurationChange, HasProperty, IsPropertySettable, GetPropertyDataSize,
    GetPropertyData, SetPropertyData, StartIO, StopIO, GetZeroTimeStamp, WillDoIOOperation, BeginIOOperation, DoIOOperation,
    EndIOOperation,
};
static AudioServerPlugInDriverInterface *gInterfacePtr = &gInterface;
static AudioServerPlugInDriverRef gDriverRef = &gInterfacePtr;

void *RogAudio_Create(CFAllocatorRef alloc, CFUUIDRef type)
{
    (void)alloc;
    if (!CFEqual(type, kAudioServerPlugInTypeUUID)) return NULL;
    return gDriverRef;
}
