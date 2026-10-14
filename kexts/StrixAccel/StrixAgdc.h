// SPDX-License-Identifier: BSD-3-Clause-Clear
// StrixDeviceControl: the AppleGraphicsDeviceControl service for the Radeon 890M.
//
// Why it exists (Step06 of docs/890M-TRACE.md): CoreDisplay builds a display pipe per framebuffer through
// IOPresentmentCreateForRegistryID(); IOPresentment resolves the GPU -> framebuffer association through the AGDC user
// client of the GPU's AppleGraphicsDeviceControl service.  Without one the map is NULL ("Unable to get AGDC
// information", "Unable to acquire map"), CoreDisplay never finds a pipe and WindowServer composites on the CPU with
// gamma-only transactions.  This object answers the four queries IOPresentment issues (vendor info, GPU capability,
// link configuration, framebuffer plane-scaler capability) from the native framebuffer's own mode. Feature
// capabilities other than the plane scaler are answered with zero entries (nothing to drive); everything else
// is refused with kIOReturnUnsupported while counting what was asked.
//
// Included by StrixAccel.cpp (needs SLOG); nothing here programs hardware.
#pragma once
#include "AppleGraphicsDeviceControl_decl.h"

namespace strix_agdc {

enum : unsigned {
    kCmdVendorInfo = 0x1,
    kCmdFbExtCap   = 0x711,
    kCmdLinkConfig = 0x921,
    kCmdGpuCap     = 0x980,
    kCmdClientSet  = 0x2001,      // 4-byte input, no output; refusing it made IOPresentment give up (Step06)
    kFbCapPlaneScaler = 0x10,
    kMaxFramebuffers  = 4,        // IOPresentment's map holds 8; one panel needs one
};

#pragma pack(push, 1)
struct VendorInfo {              // 0x2c
    uint32_t version;
    char     vendor[0x20];
    uint32_t vendorID;
    uint32_t vendorClass;        // 1 = also validated against the platform table, 2 = not
};
struct GpuCapability {           // 0xdc
    uint64_t portMask;
    uint64_t portFeature[3];
    uint32_t count[4];
    uint32_t maxFramebuffers;
    void    *pciDevice;
    void    *framebuffer[20];
};
struct LinkTiming {              // 0x94
    uint32_t hScaledInset, vScaledInset, scalerFlags, hScaled, vScaled, signalConfig, signalLevels;
    uint64_t pixelClock, minPixelClock, maxPixelClock;
    uint32_t hActive, hBlanking, hSyncOffset, hSyncPulseWidth;
    uint32_t vActive, vBlanking, vSyncOffset, vSyncPulseWidth;
    uint32_t hBorderLeft, hBorderRight, vBorderTop, vBorderBottom;
    uint32_t hSyncConfig, hSyncLevel, vSyncConfig, vSyncLevel;
    uint32_t numLinks, vBlankingExtension;
    uint16_t pixelEncoding, bitsPerComponent, colorimetry, dynamicRange;
    uint16_t dscBitsPerPixel, dscSliceHeight, dscSliceWidth, reserved;
    uint8_t  tail[8];
};
struct LinkConfig {              // 0xb0
    int32_t  id;                 // framebuffer slot index (in/out)
    int32_t  groupID;
    uint64_t flags;
    LinkTiming timing;
    uint32_t port, stream, state;
};
struct FbExtCap {                // 0x196c
    uint32_t fbIndex, type, count;
    uint8_t  entry[8][0x32c];
};
#pragma pack(pop)
static_assert(sizeof(VendorInfo) == 0x2c, "AGDC vendor info");
static_assert(sizeof(GpuCapability) == 0xdc, "AGDC GPU capability");
static_assert(sizeof(LinkTiming) == 0x94, "AGDC link timing");
static_assert(sizeof(LinkConfig) == 0xb0, "AGDC link config");
static_assert(sizeof(FbExtCap) == 0x196c, "AGDC framebuffer extended capability");

struct Stats {
    volatile SInt32 commands, vendorInfo, gpuCap, linkConfig, fbCap, fbCapEmpty, refused;
    volatile SInt32 lastRefused, lastLinkIndex, lastCapIndex, lastCapType;
    volatile SInt32 noFramebuffer, badSize, clientSet, lastClientSetValue;
};
static Stats gStats;
static volatile SInt32 gRefusedLogged;
static char gRefusedSeen[128] = "";      // "0x3fc,0x925,..." distinct refused commands, bounded

static void hexdump(char *dst, size_t cap, const void *src, unsigned long n)
{
    static const char digits[] = "0123456789abcdef";
    const uint8_t *b = static_cast<const uint8_t *>(src);
    size_t w = 0;
    if (n > 24) n = 24;
    for (unsigned long i = 0; src && i < n && w + 3 < cap; ++i) {
        dst[w++] = digits[b[i] >> 4];
        dst[w++] = digits[b[i] & 15];
        if (i + 1 < n) dst[w++] = ' ';
    }
    dst[w] = 0;
}

static void noteRefused(unsigned cmd, const void *in, unsigned long inSize, unsigned long outSize)
{
    OSIncrementAtomic(&gStats.refused);
    gStats.lastRefused = (SInt32)cmd;
    // distinct list: the commands are few, so a plain bounded scan over a tag-per-entry table is enough
    static uint32_t seen[16];
    static unsigned nSeen;
    bool known = false;
    for (unsigned i = 0; i < nSeen; ++i) if (seen[i] == cmd) known = true;
    if (!known && nSeen < 16) {
        seen[nSeen++] = cmd;
        size_t n = strlen(gRefusedSeen);
        snprintf(gRefusedSeen + n, sizeof gRefusedSeen - n, "%s%#x", n ? "," : "", cmd);
    }
    if (gRefusedLogged < 40) {
        OSIncrementAtomic(&gRefusedLogged);
        char hex[80];
        hexdump(hex, sizeof hex, in, inSize);
        SLOG("AGDC: command %#x (in %lu out %lu bytes) -> Unsupported, in: %s", cmd, inSize, outSize, hex);
    }
}

} // namespace strix_agdc

class StrixDeviceControl : public AppleGraphicsDeviceControl {
    OSDeclareDefaultStructors(StrixDeviceControl)
public:
    IOService *gpu = nullptr;          // the IOPCIDevice (not retained: it is our provider)
    IOFramebuffer *fb = nullptr;       // retained once found
    using AppleGraphicsDeviceControl::vendor_doDeviceAttribute;
    IOReturn vendor_doDeviceAttribute(unsigned int cmd, unsigned long *in, unsigned long inSize,
                                      unsigned long *out, unsigned long *outSize,
                                      IOExternalMethodArguments *args) override;
    void dropFramebuffer() { if (fb) { fb->release(); fb = nullptr; } }

private:
    IOFramebuffer *framebuffer();
    void timing(strix_agdc::LinkTiming &t);
};
OSDefineMetaClassAndStructors(StrixDeviceControl, AppleGraphicsDeviceControl)

IOFramebuffer *StrixDeviceControl::framebuffer()
{
    if (fb) return fb;
    if (!gpu) return nullptr;
    OSIterator *it = gpu->getChildIterator(gIOServicePlane);
    if (!it) return nullptr;
    while (OSObject *o = it->getNextObject()) {
        if (IOFramebuffer *f = OSDynamicCast(IOFramebuffer, o)) {
            f->retain();
            fb = f;
            break;
        }
    }
    it->release();
    return fb;
}

// Current mode of the native framebuffer; falls back to the panel's 120 Hz mode (Step01 EDID) when it cannot say.
void StrixDeviceControl::timing(strix_agdc::LinkTiming &t)
{
    using namespace strix_agdc;
    bzero(&t, sizeof t);
    uint64_t clock = 652264000;
    uint32_t hA = 2880, hB = 100, hO = 48, hP = 32, vA = 1800, vB = 24, vO = 3, vP = 5;
    if (IOFramebuffer *f = framebuffer()) {
        IODisplayModeID mode = 0;
        IOIndex depth = 0;
        IOTimingInformation ti;
        if (f->getCurrentDisplayMode(&mode, &depth) == kIOReturnSuccess &&
            f->getTimingInfoForDisplayMode(mode, &ti) == kIOReturnSuccess &&
            (ti.flags & kIODetailedTimingValid)) {
            const auto &d = ti.detailedInfo.v2;
            if (d.pixelClock && d.horizontalActive && d.verticalActive) {
                clock = d.pixelClock;
                hA = d.horizontalActive; hB = d.horizontalBlanking;
                hO = d.horizontalSyncOffset; hP = d.horizontalSyncPulseWidth;
                vA = d.verticalActive; vB = d.verticalBlanking;
                vO = d.verticalSyncOffset; vP = d.verticalSyncPulseWidth;
            }
        }
    }
    t.pixelClock = t.minPixelClock = t.maxPixelClock = clock;
    t.hActive = hA; t.hBlanking = hB; t.hSyncOffset = hO; t.hSyncPulseWidth = hP;
    t.vActive = vA; t.vBlanking = vB; t.vSyncOffset = vO; t.vSyncPulseWidth = vP;
    t.hSyncConfig = 1; t.vSyncConfig = 1;      // positive polarity, as the framebuffer reports it
    t.numLinks = 1;
    t.pixelEncoding = 1;                       // RGB 4:4:4
    t.bitsPerComponent = 2;                    // 8 bpc
    t.colorimetry = 1;
    t.dynamicRange = 1;
}

IOReturn StrixDeviceControl::vendor_doDeviceAttribute(unsigned int cmd, unsigned long *in, unsigned long inSize,
                                                      unsigned long *out, unsigned long *outSize,
                                                      IOExternalMethodArguments *)
{
    using namespace strix_agdc;
    OSIncrementAtomic(&gStats.commands);
    const unsigned long outBytes = outSize ? *outSize : 0;

    switch (cmd) {
    case kCmdVendorInfo: {
        if (!out || outBytes != sizeof(VendorInfo)) { OSIncrementAtomic(&gStats.badSize); return kIOReturnBadArgument; }
        auto v = reinterpret_cast<VendorInfo *>(out);
        bzero(v, sizeof *v);
        v->version = 0x30000;
        strlcpy(v->vendor, "AMD", sizeof v->vendor);
        v->vendorID = 0x1002;
        v->vendorClass = 2;
        OSIncrementAtomic(&gStats.vendorInfo);
        return kIOReturnSuccess;
    }
    case kCmdGpuCap: {
        if (!out || outBytes != sizeof(GpuCapability)) { OSIncrementAtomic(&gStats.badSize); return kIOReturnBadArgument; }
        auto c = reinterpret_cast<GpuCapability *>(out);
        bzero(c, sizeof *c);
        IOFramebuffer *f = framebuffer();
        if (!f) OSIncrementAtomic(&gStats.noFramebuffer);
        c->pciDevice = gpu;
        c->framebuffer[0] = f;
        c->portMask = f ? (1ull << 1) : 0;
        c->count[0] = c->count[1] = c->count[2] = c->count[3] = f ? 1 : 0;
        c->maxFramebuffers = f ? 1 : 0;
        OSIncrementAtomic(&gStats.gpuCap);
        return kIOReturnSuccess;
    }
    case kCmdLinkConfig: {
        if (!in || !out || inSize != sizeof(LinkConfig) || outBytes != sizeof(LinkConfig)) {
            OSIncrementAtomic(&gStats.badSize);
            return kIOReturnBadArgument;
        }
        const int32_t idx = reinterpret_cast<const LinkConfig *>(in)->id;
        gStats.lastLinkIndex = idx;
        if (idx != 0 || !framebuffer()) return kIOReturnBadArgument;
        auto l = reinterpret_cast<LinkConfig *>(out);
        bzero(l, sizeof *l);
        l->id = idx;
        l->groupID = -1;
        l->flags = 0x1 | 0x2 | 0x8;
        timing(l->timing);
        l->port = 1;
        l->stream = 0;
        l->state = 1;
        OSIncrementAtomic(&gStats.linkConfig);
        return kIOReturnSuccess;
    }
    case kCmdFbExtCap: {
        if (!in || !out || inSize != sizeof(FbExtCap) || outBytes != sizeof(FbExtCap)) {
            OSIncrementAtomic(&gStats.badSize);
            return kIOReturnBadArgument;
        }
        const auto *q = reinterpret_cast<const FbExtCap *>(in);
        const uint32_t idx = q->fbIndex, type = q->type;
        gStats.lastCapIndex = (SInt32)idx;
        gStats.lastCapType = (SInt32)type;
        if (type != kFbCapPlaneScaler) {
            // Any other feature (HDR, colour, DSC, power, ...): a display-only pipe has none of them.
            // Answer success with zero entries ("nothing to use, skip it") instead of Unsupported; never
            // synthesize entries CoreDisplay would try to drive. Counted separately from the scaler answers.
            auto c = reinterpret_cast<FbExtCap *>(out);
            bzero(c, sizeof *c);
            c->fbIndex = idx;
            c->type = type;
            c->count = 0;
            OSIncrementAtomic(&gStats.fbCapEmpty);
            return kIOReturnSuccess;
        }
        if (idx != 0 || !framebuffer()) return kIOReturnBadArgument;
        LinkTiming t;
        timing(t);
        auto c = reinterpret_cast<FbExtCap *>(out);
        bzero(c, sizeof *c);
        c->fbIndex = idx;
        c->type = type;
        c->count = 1;
        auto put = [&](unsigned off, uint32_t v) { memcpy(&c->entry[0][off], &v, sizeof v); };
        put(0x000, 0x80004);                             // scaler descriptor id
        put(0x01c, 1);                                   // enabled
        put(0x024, t.vActive); put(0x028, t.hActive);    // max source
        put(0x02c, t.vActive); put(0x030, t.hActive);    // max destination
        put(0x034, 0x70007);                             // scale factor limits (1:1 .. 7:1)
        put(0x1a4, 1);
        put(0x1ac, t.vActive); put(0x1b0, t.hActive);
        put(0x1b4, t.vActive); put(0x1b8, t.hActive);
        put(0x1bc, 0x70007);
        OSIncrementAtomic(&gStats.fbCap);
        return kIOReturnSuccess;
    }
    case kCmdClientSet: {
        // A 4-byte value the client hands us; there is nothing to apply for a display-only GPU, accept it.
        uint32_t v = 0;
        if (in && inSize >= sizeof v) memcpy(&v, in, sizeof v);
        gStats.lastClientSetValue = (SInt32)v;
        if (OSIncrementAtomic(&gStats.clientSet) < 8) SLOG("AGDC: command 0x2001 value %#x accepted", v);
        return kIOReturnSuccess;
    }
    default:
        noteRefused(cmd, in, inSize, outBytes);
        return kIOReturnUnsupported;
    }
}

// ---- lifetime, driven by StrixAccelerator (never from the registry thread) ----
static StrixDeviceControl *strixAgdcUp(IOService *gpu)
{
    StrixDeviceControl *d = OSTypeAlloc(StrixDeviceControl);
    if (!d) return nullptr;
    if (!d->init(nullptr)) { d->release(); return nullptr; }
    d->gpu = gpu;
    if (!d->attach(gpu)) { SLOG("AGDC: attach failed"); d->release(); return nullptr; }
    if (!d->start(gpu)) {
        SLOG("AGDC: AppleGraphicsDeviceControl::start failed");
        d->detach(gpu);
        d->release();
        return nullptr;
    }
    SLOG("AGDC: up on %s", gpu->getName());
    return d;
}

static void strixAgdcDown(StrixDeviceControl *d)
{
    if (!d) return;
    d->terminate(kIOServiceRequired | kIOServiceSynchronous);
    d->dropFramebuffer();
    d->release();
}
