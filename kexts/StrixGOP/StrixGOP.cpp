// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step03: fixed GOP raster. IOGraphics/WindowServer may write only that raster.
// No DCN/SMU/PSP/GFX init, modesetting, GPU allocator or acceleration.
// 0.1.5 adds the one hardware interaction the panel needs: its brightness. The OLED is AUX-only
// (DPCD 0x720..0x723, no PWM pin), so the framebuffer drives DCN35's DPAUX engine through BAR5
// (DcnAux.h) and publishes an IODisplayParameterHandler named "backlight" so IOGraphics builds an
// AppleBacklightDisplay (slider, Fn keys, dim/sleep). Boot-arg -strixauxoff keeps all of it inert.
#include <IOKit/graphics/IOFramebuffer.h>
#include <IOKit/graphics/IODisplay.h>
#include <IOKit/ndrvsupport/IOMacOSVideo.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IODeviceMemory.h>
#include <kern/thread_call.h>
#include <libkern/OSByteOrder.h>
#include <pexpert/pexpert.h>
#include "GopLayout.h"
#include "DcnAux.h"

class StrixGOPFramebuffer;

// IODisplay finds this below the framebuffer (searchParameterHandlers) and offers "brightness" and
// "linear-brightness" through it, in percent. IODisplay calls doIntegerSet() with the framebuffer lock
// held, so the DPCD writes run from a thread call (same recipe as NVRMFB's handler).
class StrixBacklightHandler : public IODisplayParameterHandler {
    OSDeclareDefaultStructors(StrixBacklightHandler)
    StrixGOPFramebuffer *fb = nullptr;
    IOLock *lock = nullptr;
    thread_call_t apply = nullptr;
    volatile SInt32 pending = -1;
    SInt32 level = 100;
    UInt32 rawCount = 0;
    static void applyFire(thread_call_param_t me, thread_call_param_t);
public:
    static StrixBacklightHandler *with(StrixGOPFramebuffer *owner, uint32_t percent);
    void orphan();
    // Deferred percent request usable from any lock context (display power path);
    // same coalescing apply as doIntegerSet.
    void requestPercent(UInt32 v) { pending = SInt32(v > 100 ? 100 : v); if (apply) thread_call_enter(apply); }
    bool setDisplay(IODisplay *display) override;
    bool doIntegerSet(OSDictionary *params, const OSSymbol *paramName, UInt32 value) override;
    bool doDataSet(const OSSymbol *, OSData *) override { return false; }
    bool doUpdate() override { return true; }
    void free() override;
};

class StrixGOPFramebuffer : public IOFramebuffer {
    OSDeclareDefaultStructors(StrixGOPFramebuffer)
    GopLayout layout {};
    uint64_t raster = 0;
    IODeviceMemory *surface = nullptr;
    // Same 2880x1800 raster for both; refresh only informs CoreDisplay
    // scheduling. No hardware modeset is ever performed, so HiDPI keeps its
    // native backing either way. Boot GOP scans at 120 Hz (Step01/HANDOFF).
    static constexpr IODisplayModeID mode60 = 1;
    static constexpr IODisplayModeID mode120 = 2;
    // Step11: CoreDisplay's Display::SupportsHDRMode / CGXIsHDRSupported only say
    // yes when FindIOModeIDForIODynamicRange(fb, mode, kIODynamicRangeHDR10) finds a
    // second mode with identical detailed timing whose dynamicRange == 2. These are
    // those twins; published only with boot-arg strixhdr=1 (default off).
    static constexpr IODisplayModeID mode60hdr = 3;
    static constexpr IODisplayModeID mode120hdr = 4;
    bool hdrModes = false;
    bool knownMode(IODisplayModeID m) const {
        return m == mode60 || m == mode120 || (hdrModes && (m == mode60hdr || m == mode120hdr));
    }
    IODisplayModeID currentMode = mode120;
    // Optional EDID from the personality (runner-embedded). Reported over the
    // framebuffer DDC path so IODisplayConnect/ColorSync identify the panel.
    OSData *edid = nullptr;
    // Read-only diagnostic: sparse sampling of the boot raster to show
    // whether WindowServer ever writes to the scanned-out aperture.
    static constexpr unsigned kSampleGrid = 32;
    IOMemoryMap *sampleMap = nullptr;
    uint32_t baseline[kSampleGrid * kSampleGrid] {};
    bool haveBaseline = false;
    unsigned attributeLog = 0;
    // Panel brightness over DCN35 DPAUX (see DcnAux.h). auxChannel < 0: no usable AUX brightness.
    DcnAux aux;
    int auxChannel = -1;
    unsigned blBytes = 2;       // DPCD 0x702 bit 2: 16-bit level
    uint32_t blMax = 0;         // (1 << PWMGEN bit count) - 1
    bool blAuxEnable = false;   // DPCD 0x701 bit 2: 0x720 bit 0 is the enable
    uint32_t blPercent = 100;
    IOLock *blLock = nullptr;
    StrixBacklightHandler *backlight = nullptr;
    unsigned blWrites = 0, blFailures = 0;
    // Display-sleep bookkeeping: kConnectionPower(0) parks the panel at level 0 and remembers the last
    // lit percent; power-on / post-wake restores it. Counted as properties so traces prove the path ran.
    bool panelAsleep = false;
    uint32_t sleepSavedPercent = 100;
    unsigned sleepCount = 0, wakeCount = 0;
    void displayPower(bool on);
    bool readProfile(IOPCIDevice *pci);
    bool discoverPanel(IOPCIDevice *pci);
    void publishBacklight();
    bool loadEdid();
    void logAttribute(const char *where, IOIndex connection, IOSelect attribute, uintptr_t value, IOReturn rc);
    bool takeSample(uint32_t *out);
    void refreshSample();
public:
    bool setPanelPercent(uint32_t percent);
    void dumpDpcd(unsigned ch, uint32_t addr, unsigned n, const char *key);
    IOReturn getAppleSense(IOIndex connectIndex, UInt32 *senseType, UInt32 *primary, UInt32 *extended,
                           UInt32 *displayType) override;
    void stop(IOService *provider) override;
    bool serializeProperties(OSSerialize *s) const override;
    bool hasDDCConnect(IOIndex connectIndex) override;
    IOReturn getDDCBlock(IOIndex connectIndex, UInt32 blockNumber, IOSelect blockType,
                         IOOptionBits options, UInt8 *data, IOByteCount *length) override;
    IOReturn setAttribute(IOSelect attribute, uintptr_t value) override;
    IOReturn setAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t value) override;
    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void free() override;
    IOReturn enableController() override;
    IODeviceMemory *getApertureRange(IOPixelAperture aperture) override;
    IODeviceMemory *getVRAMRange() override;
    const char *getPixelFormats() override;
    IOItemCount getDisplayModeCount() override;
    IOReturn getDisplayModes(IODisplayModeID *modes) override;
    IOReturn getInformationForDisplayMode(IODisplayModeID mode, IODisplayModeInformation *info) override;
    IOReturn getTimingInfoForDisplayMode(IODisplayModeID mode, IOTimingInformation *info) override;
    UInt64 getPixelFormatsForDisplayMode(IODisplayModeID, IOIndex) override;
    IOReturn getPixelInformation(IODisplayModeID mode, IOIndex depth, IOPixelAperture aperture,
                               IOPixelInformation *info) override;
    IOReturn getCurrentDisplayMode(IODisplayModeID *mode, IOIndex *depth) override;
    IOReturn getStartupDisplayMode(IODisplayModeID *mode, IOIndex *depth) override;
    IOReturn setDisplayMode(IODisplayModeID mode, IOIndex depth) override;
    IOReturn setStartupDisplayMode(IODisplayModeID mode, IOIndex depth) override;
    IOReturn getAttribute(IOSelect attribute, uintptr_t *value) override;
    IOReturn getAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t *value) override;
};
OSDefineMetaClassAndStructors(StrixGOPFramebuffer, IOFramebuffer)

IOService *StrixGOPFramebuffer::probe(IOService *provider, SInt32 *score) {
    if (PE_parse_boot_argn("-strixgopoff", nullptr, 0)) return nullptr;
    if (getProperty("AdoptBootGOP") != kOSBooleanTrue) return nullptr;
    auto pci = OSDynamicCast(IOPCIDevice, provider);
    if (!pci || pci->configRead32(0) != 0x150e1002 ||
        (pci->configRead32(8) & 255) != 0xc1 || pci->configRead32(0x2c) != 0x39981043)
        return nullptr;
    return IOFramebuffer::probe(provider, score);
}

bool StrixGOPFramebuffer::readProfile(IOPCIDevice *pci) {
    auto profile = OSDynamicCast(OSDictionary, getProperty("BootGOPProfile"));
    if (!profile) return false;
    auto number = [&](const char *key, uint64_t &value) {
        auto n = OSDynamicCast(OSNumber, profile->getObject(key));
        if (!n) return false;
        value = n->unsigned64BitValue(); return true;
    };
    uint64_t expectedBase, expectedLength, w, h, stride, depth, rotation, offset;
    if (!number("BAR0Base", expectedBase) || !number("BAR0Length", expectedLength) ||
        !number("Width", w) || !number("Height", h) || !number("Stride", stride) ||
        !number("Depth", depth) || !number("Rotation", rotation) || !number("Offset", offset) ||
        w > UINT32_MAX || h > UINT32_MAX || stride > UINT32_MAX || depth > UINT32_MAX || rotation > UINT32_MAX)
        return false;
    // Only the explicitly selected standard XRGB layout is implemented.
    auto format = OSDynamicCast(OSString, profile->getObject("PixelFormat"));
    if (!format || !format->isEqualTo("XRGB8888")) return false;
    auto resources = OSDynamicCast(OSArray, pci->getProperty("IODeviceMemory"));
    if (!resources) return false;
    for (unsigned i = 0; i < resources->getCount(); ++i) {
        // IODeviceMemory factories actually return general/sub descriptors in XNU.
        // Do not dynamic-cast to IODeviceMemory: it has no runtime metaclass.
        auto memory = OSDynamicCast(IOMemoryDescriptor, resources->getObject(i));
        if (!memory || (memory->getTag() & 255) != 0x10) continue;
        IOByteCount segment = 0;
        uint64_t base = memory->getPhysicalSegment(0, &segment, kIOMemoryMapperNone);
        uint64_t length = memory->getLength();
        uint32_t lo = pci->configRead32(0x10), hi = pci->configRead32(0x14);
        if ((lo & 7) != 4 || ((uint64_t(hi) << 32) | (lo & ~15u)) != base ||
            base != expectedBase || length != expectedLength || segment < length) return false;
        layout = {base, length, offset, uint32_t(w), uint32_t(h), uint32_t(stride),
                  uint32_t(depth), uint32_t(rotation)};
        const char *error = validateGopLayout(layout, raster);
        if (error) { IOLog("StrixGOP: reject %s\n", error); return false; }
        surface = IODeviceMemory::withSubRange(reinterpret_cast<IODeviceMemory *>(memory),
                                             offset, (raster + 4095) & ~uint64_t(4095));
        return surface != nullptr;
    }
    return false;
}

bool StrixGOPFramebuffer::start(IOService *provider) {
    auto pci = OSDynamicCast(IOPCIDevice, provider);
    if (!pci || !readProfile(pci)) return false;
    setProperty("TraceStep", "890M-03");
    setProperty("StrixGOPVersion", "0.1.8");
    setProperty("HardwareModesetting", false);
    setProperty("Acceleration", false);
    setProperty("Aperture,Base", layout.barBase + layout.offset, 64);
    setProperty("Aperture,RasterBytes", raster, 64);
    setProperty("PixelFormat,Status", "XRGB8888-selected-needs-color-validation");
    loadEdid();
    {
        uint32_t hdr = 0;
        if (PE_parse_boot_argn("strixhdr", &hdr, sizeof(hdr)) && hdr) hdrModes = true;
        // Persistent switch from the personality (install script --hdr / --nohdr).
        if (OSBoolean *b = OSDynamicCast(OSBoolean, getProperty("HdrModes"))) hdrModes = hdrModes || b->isTrue();
        if (PE_parse_boot_argn("-strixhdroff", nullptr, 0)) hdrModes = false;
        setProperty("Hdr,Modes", hdrModes ? 1 : 0, 32);
    }
    // The backlight handler must exist before IOFramebuffer::start(): IOFramebuffer::open looks for
    // a service named "backlight" when the first framebuffer opens (gIOFBHaveBacklight).
    if (PE_parse_boot_argn("-strixauxoff", nullptr, 0)) setProperty("Aux,Status", "disabled-by-boot-arg");
    else if (discoverPanel(pci)) publishBacklight();
    // Superclass publishes the service and handles IOGraphics lifecycle.
    if (IOFramebuffer::start(provider)) return true;
    if (backlight) { backlight->orphan(); backlight->detach(this); backlight->release(); backlight = nullptr; }
    return false;
}

void StrixGOPFramebuffer::stop(IOService *provider) {
    if (backlight) {
        backlight->orphan();
        backlight->detach(this);
        backlight->release();
        backlight = nullptr;
    }
    IOFramebuffer::stop(provider);
}

void StrixGOPFramebuffer::free() {
    if (backlight) { backlight->orphan(); backlight->release(); backlight = nullptr; }
    aux.detach();
    if (blLock) { IOLockFree(blLock); blLock = nullptr; }
    if (sampleMap) { sampleMap->release(); sampleMap = nullptr; }
    if (edid) { edid->release(); edid = nullptr; }
    if (surface) { surface->release(); surface = nullptr; }
    IOFramebuffer::free();
}

IOReturn StrixGOPFramebuffer::enableController() {
    IOLog("StrixGOP: fixed raster %ux%u stride %u; no hardware modeset\n",
          layout.width, layout.height, layout.stride);
    setProperty("Controller,Enabled", surface != nullptr);
    if (surface && !haveBaseline) haveBaseline = takeSample(baseline);
    return surface ? kIOReturnSuccess : kIOReturnNotReady;
}

IODeviceMemory *StrixGOPFramebuffer::getApertureRange(IOPixelAperture aperture) {
    if (aperture != kIOFBSystemAperture || !surface) return nullptr;
    surface->retain(); return surface; // One consumed reference per call.
}
IODeviceMemory *StrixGOPFramebuffer::getVRAMRange() { return getApertureRange(kIOFBSystemAperture); }
const char *StrixGOPFramebuffer::getPixelFormats() { return IO32BitDirectPixels "\0"; }
IOItemCount StrixGOPFramebuffer::getDisplayModeCount() { return hdrModes ? 4 : 2; }
UInt64 StrixGOPFramebuffer::getPixelFormatsForDisplayMode(IODisplayModeID, IOIndex) { return 0; }
IOReturn StrixGOPFramebuffer::getDisplayModes(IODisplayModeID *modes) {
    if (!modes) return kIOReturnBadArgument;
    modes[0] = mode60; modes[1] = mode120;
    if (hdrModes) { modes[2] = mode60hdr; modes[3] = mode120hdr; }
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getInformationForDisplayMode(IODisplayModeID mode, IODisplayModeInformation *info) {
    if (!knownMode(mode) || !info) return kIOReturnBadArgument;
    bzero(info, sizeof(*info));
    info->nominalWidth = layout.width; info->nominalHeight = layout.height;
    // Step01 EDID (ATNA40CU05-0): 60 Hz base DTD 652.270 MHz (htotal 2980,
    // vtotal 3648), 120 Hz DisplayID 652.264 MHz (htotal 2980, vtotal 1824).
    // Previously zero, which published IOFB0Hz and left CoreDisplay with no
    // display pipe (frozen boot logo while the WindowServer shadow composited
    // fine). Default is the boot scanout (120 Hz). No hardware modeset.
    const bool is120 = mode == mode120 || mode == mode120hdr;
    info->refreshRate = is120 ? IOFixed1616(120 << 16) : IOFixed1616(60 << 16);
    info->maxDepthIndex = 0;
    info->flags = kDisplayModeValidFlag | kDisplayModeSafeFlag |
                  kDisplayModeBuiltInFlag | kDisplayModeNativeFlag |
                  kDisplayModeValidForHiResFlag;
    if (mode == mode120) info->flags |= kDisplayModeDefaultFlag;
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getTimingInfoForDisplayMode(IODisplayModeID mode, IOTimingInformation *info) {
    if (!knownMode(mode) || !info) return kIOReturnBadArgument;
    const bool hdrTwin = mode == mode60hdr || mode == mode120hdr;
    if (mode == mode120hdr) mode = mode120;
    else if (mode == mode60hdr) mode = mode60;
    // Informational only: never programmed into DCN. Sync split is a
    // plausible placeholder inside the known blanking intervals.
    bzero(info, sizeof(*info));
    info->appleTimingID = kIOTimingIDApple_FixedRateLCD;
    info->flags = kIODetailedTimingValid;
    auto &t = info->detailedInfo.v2;
    if (mode == mode120) {
        t.pixelClock = 652264000; t.minPixelClock = 652264000; t.maxPixelClock = 652264000;
        t.horizontalActive = layout.width; t.horizontalBlanking = 100;
        t.horizontalSyncOffset = 48; t.horizontalSyncPulseWidth = 32;
        t.verticalActive = layout.height; t.verticalBlanking = 24;
        t.verticalSyncOffset = 3; t.verticalSyncPulseWidth = 5;
    } else {
        t.pixelClock = 652270000; t.minPixelClock = 652270000; t.maxPixelClock = 652270000;
        t.horizontalActive = layout.width; t.horizontalBlanking = 100;
        t.horizontalSyncOffset = 48; t.horizontalSyncPulseWidth = 32;
        t.verticalActive = layout.height; t.verticalBlanking = 1848;
        t.verticalSyncOffset = 3; t.verticalSyncPulseWidth = 5;
    }
    t.horizontalSyncConfig = kIOSyncPositivePolarity;
    t.verticalSyncConfig = kIOSyncPositivePolarity;
    t.numLinks = 1;
    t.pixelEncoding = kIOPixelEncodingRGB444;
    t.bitsPerColorComponent = 8;
    // The SDR twins stay kIODynamicRangeNotSupported unless the HDR twins exist, so
    // the default boot is byte-identical to 0.1.7.
    if (hdrModes) t.dynamicRange = hdrTwin ? kIODynamicRangeHDR10 : kIODynamicRangeSDR;
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getPixelInformation(IODisplayModeID mode, IOIndex depth,
    IOPixelAperture aperture, IOPixelInformation *info) {
    if (!knownMode(mode) || depth != 0 || aperture != kIOFBSystemAperture || !info)
        return kIOReturnBadArgument;
    bzero(info, sizeof(*info));
    info->bytesPerRow = layout.stride; info->bitsPerPixel = 32;
    info->pixelType = kIORGBDirectPixels; info->componentCount = 3; info->bitsPerComponent = 8;
    info->componentMasks[0] = 0x00ff0000; info->componentMasks[1] = 0x0000ff00;
    info->componentMasks[2] = 0x000000ff;
    strlcpy(info->pixelFormat, IO32BitDirectPixels, sizeof(info->pixelFormat));
    info->activeWidth = layout.width; info->activeHeight = layout.height;
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getCurrentDisplayMode(IODisplayModeID *mode, IOIndex *depth) {
    if (!mode || !depth) return kIOReturnBadArgument;
    *mode = currentMode; *depth = 0; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getStartupDisplayMode(IODisplayModeID *mode, IOIndex *depth) {
    if (!mode || !depth) return kIOReturnBadArgument;
    *mode = mode120; *depth = 0; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::setDisplayMode(IODisplayModeID mode, IOIndex depth) {
    // No hardware modeset: both modes share the boot raster. Record the
    // selection so the scheduler's refresh matches what was asked.
    if (!knownMode(mode) || depth != 0) return kIOReturnUnsupported;
    currentMode = mode; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::setStartupDisplayMode(IODisplayModeID mode, IOIndex depth) {
    return setDisplayMode(mode, depth);
}
IOReturn StrixGOPFramebuffer::getAttribute(IOSelect attribute, uintptr_t *value) {
    if (!value) return kIOReturnBadArgument;
    if (attribute == kIOHardwareCursorAttribute) { *value = 0; return kIOReturnSuccess; }
    IOReturn rc = IOFramebuffer::getAttribute(attribute, value);
    if (rc != kIOReturnSuccess) logAttribute("get", -1, attribute, 0, rc);
    return rc;
}
IOReturn StrixGOPFramebuffer::setAttribute(IOSelect attribute, uintptr_t value) {
    IOReturn rc;
    switch (attribute) {
        // Pure bookkeeping with no hardware to program: acknowledge so the
        // IOFramebuffer power/capture state machines can complete.
        case kIOPowerAttribute:
        case kIODriverPowerAttribute:
        case kIOSystemPowerAttribute:
        case kIOCapturedAttribute:
            rc = kIOReturnSuccess; break;
        default:
            rc = IOFramebuffer::setAttribute(attribute, value);
    }
    logAttribute("set", -1, attribute, value, rc);
    return rc;
}
void StrixGOPFramebuffer::displayPower(bool on) {
    // Steered through the same deferred apply as slider sets: this path may run under locks.
    if (on) {
        if (panelAsleep) {
            panelAsleep = false;
            uint32_t restore = sleepSavedPercent ? sleepSavedPercent : 100;
            if (backlight) backlight->requestPercent(restore);
            ++wakeCount;
            setProperty("Backlight,WakeCount", wakeCount, 32);
            IOLog("StrixGOP: display power ON (wake #%u, restore %u%%)\n", wakeCount, restore);
        }
    } else {
        if (!panelAsleep) {
            panelAsleep = true;
            sleepSavedPercent = blPercent ? blPercent : 100;
            if (backlight) backlight->requestPercent(0);
            ++sleepCount;
            setProperty("Backlight,SleepCount", sleepCount, 32);
            IOLog("StrixGOP: display power OFF (sleep #%u, saved %u%%)\n", sleepCount, sleepSavedPercent);
        }
    }
}
IOReturn StrixGOPFramebuffer::setAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t value) {
    IOReturn rc;
    switch (attribute) {
        // Display power now drives the panel (0.1.7): OFF parks the backlight at 0, ON/post-wake
        // restores the saved percent. Previously pure-ACKed, which left the panel lit on display sleep.
        case kConnectionPower:
            if (connection) { rc = kIOReturnBadArgument; break; }
            displayPower(value != 0);
            rc = kIOReturnSuccess; break;
        case kConnectionPostWake:
            if (connection) { rc = kIOReturnBadArgument; break; }
            displayPower(true);
            rc = kIOReturnSuccess; break;
        case kConnectionEnable:
        case kConnectionProbe:
            rc = connection ? kIOReturnBadArgument : kIOReturnSuccess; break;
        default:
            rc = IOFramebuffer::setAttributeForConnection(connection, attribute, value);
    }
    logAttribute("setconn", connection, attribute, value, rc);
    return rc;
}

void StrixGOPFramebuffer::logAttribute(const char *where, IOIndex connection, IOSelect attribute,
                                       uintptr_t value, IOReturn rc) {
    // Bounded: evidence of what IOGraphics asks of this framebuffer.
    if (attributeLog >= 64) return;
    ++attributeLog;
    char cc[5] = {char(attribute >> 24), char(attribute >> 16), char(attribute >> 8), char(attribute), 0};
    for (int i = 0; i < 4; ++i) if (cc[i] < 32 || cc[i] > 126) cc[i] = '.';
    IOLog("StrixGOP: %s conn=%d attr='%s' value=0x%lx -> 0x%x\n", where, int(connection), cc,
          (unsigned long)value, unsigned(rc));
}

bool StrixGOPFramebuffer::loadEdid() {
    auto data = OSDynamicCast(OSData, getProperty("PanelEDID"));
    if (!data) return false;
    unsigned n = data->getLength();
    if (n == 0 || n % 128 || n > 256) { IOLog("StrixGOP: reject EDID length %u\n", n); return false; }
    auto bytes = static_cast<const uint8_t *>(data->getBytesNoCopy());
    static const uint8_t header[8] = {0, 255, 255, 255, 255, 255, 255, 0};
    if (memcmp(bytes, header, 8)) { IOLog("StrixGOP: reject EDID header\n"); return false; }
    for (unsigned b = 0; b < n / 128; ++b) {
        uint8_t sum = 0;
        for (unsigned i = 0; i < 128; ++i) sum += bytes[b * 128 + i];
        if (sum) { IOLog("StrixGOP: reject EDID block %u checksum\n", b); return false; }
    }
    data->retain(); edid = data;
    setProperty("EDID,Blocks", n / 128, 32);
    return true;
}
bool StrixGOPFramebuffer::hasDDCConnect(IOIndex connectIndex) { return !connectIndex && edid; }
IOReturn StrixGOPFramebuffer::getDDCBlock(IOIndex connectIndex, UInt32 blockNumber, IOSelect blockType,
                                          IOOptionBits, UInt8 *data, IOByteCount *length) {
    if (connectIndex || !edid || !data || !length || blockType != kIODDCBlockTypeEDID)
        return kIOReturnUnsupported;
    if (blockNumber < 1 || blockNumber > edid->getLength() / 128) return kIOReturnBadArgument;
    if (*length < 128) return kIOReturnNoSpace;
    bcopy(static_cast<const uint8_t *>(edid->getBytesNoCopy()) + (blockNumber - 1) * 128, data, 128);
    *length = 128;
    return kIOReturnSuccess;
}

bool StrixGOPFramebuffer::takeSample(uint32_t *out) {
    if (!surface || !layout.stride) return false;
    if (!sampleMap) sampleMap = surface->map(kIOMapInhibitCache);
    if (!sampleMap) return false;
    auto base = reinterpret_cast<volatile uint8_t *>(sampleMap->getVirtualAddress());
    if (!base) return false;
    for (unsigned y = 0; y < kSampleGrid; ++y)
        for (unsigned x = 0; x < kSampleGrid; ++x) {
            uint64_t row = uint64_t(y) * layout.height / kSampleGrid;
            uint64_t col = uint64_t(x) * layout.width / kSampleGrid;
            out[y * kSampleGrid + x] =
                *reinterpret_cast<volatile uint32_t *>(base + row * layout.stride + col * 4);
        }
    return true;
}
void StrixGOPFramebuffer::refreshSample() {
    uint32_t now[kSampleGrid * kSampleGrid];
    if (!takeSample(now)) return;
    uint32_t hash = 2166136261u; unsigned nonBlack = 0, changed = 0;
    for (unsigned i = 0; i < kSampleGrid * kSampleGrid; ++i) {
        hash = (hash ^ now[i]) * 16777619u;
        if (now[i] & 0x00ffffff) ++nonBlack;
        if (haveBaseline && now[i] != baseline[i]) ++changed;
    }
    setProperty("Sample,Hash", hash, 32);
    setProperty("Sample,NonBlack", nonBlack, 32);
    setProperty("Sample,ChangedSinceEnable", changed, 32);
    setProperty("Sample,Count", kSampleGrid * kSampleGrid, 32);
}
bool StrixGOPFramebuffer::serializeProperties(OSSerialize *s) const {
    const_cast<StrixGOPFramebuffer *>(this)->refreshSample();
    return IOFramebuffer::serializeProperties(s);
}
IOReturn StrixGOPFramebuffer::getAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t *value) {
    if (connection) return kIOReturnBadArgument;
    // IODisplay::readFramebufferEDID probes this capability with value == NULL.
    // Success is the capability result; there is no output value to fill.
    if (attribute == kConnectionSupportsHLDDCSense)
        return edid ? kIOReturnSuccess : kIOReturnUnsupported;
    if (!value) return kIOReturnBadArgument;
    switch (attribute) {
        case kConnectionEnable:
        case kConnectionCheckEnable: *value = 1; return kIOReturnSuccess;
        case kConnectionFlags: *value = kIOConnectionBuiltIn; return kIOReturnSuccess;
        // The display identity stays with the EDID; the LCD answer is getAppleSense() below.
        case kConnectionSupportsAppleSense:
        case kConnectionSupportsLLDDCSense: return kIOReturnUnsupported;
        default: return IOFramebuffer::getAttributeForConnection(connection, attribute, value);
    }
}

// ---------------------------------------------------------------------------------------------
// Panel brightness: eDP AUX backlight (DPCD 0x720..0x726) over DCN35 DPAUX.
// ---------------------------------------------------------------------------------------------
namespace {
constexpr uint32_t kDpcdRev = 0x000, kDpcdEdpRev = 0x700, kDpcdDisplayCtl = 0x720, kDpcdBlMode = 0x721,
                   kDpcdBlLevel = 0x722, kDpcdPwmgenBits = 0x724, kDpcdPwmgenMax = 0x726;
}

bool StrixGOPFramebuffer::discoverPanel(IOPCIDevice *pci) {
    if (!aux.attach(pci)) { setProperty("Aux,Status", "bar5-unavailable"); return false; }
    char key[16], text[96];
    int found = -1;
    uint8_t caps[4] = {};
    // Pass 0: channels the firmware left enabled (the eDP one is). Pass 1: the rest, AUX_CONTROL restored.
    for (unsigned pass = 0; pass < 2 && found < 0; ++pass) {
        for (unsigned ch = 0; ch < DcnAux::kChannels && found < 0; ++ch) {
            uint32_t ctl = aux.reg(ch, DcnAux::kCtl);
            if (ctl == 0xFFFFFFFFu) { setProperty("Aux,Status", "mmio-reads-ones"); aux.detach(); return false; }
            if (bool(ctl & DcnAux::kCtlEn) == (pass == 1)) continue;
            uint8_t dp[2] = {}; uint32_t sw = 0;
            int rc = aux.read(ch, kDpcdRev, dp, 1, &sw);
            int rc2 = DcnAux::kNoMap;
            uint8_t e[4] = {};
            if (rc == DcnAux::kOk) rc2 = aux.read(ch, kDpcdEdpRev, e, 4, &sw);
            snprintf(key, sizeof key, "Aux,Ch%u", ch);
            snprintf(text, sizeof text, "pass%u ctl=%08x arb=%08x rc=%d/%d sw=%08x dpcd=%02x edp=%02x%02x%02x%02x",
                     pass, ctl, aux.reg(ch, DcnAux::kArb), rc, rc2, sw, dp[0], e[0], e[1], e[2], e[3]);
            setProperty(key, text);
            IOLog("StrixGOP: aux %s %s\n", key, text);
            if (rc == DcnAux::kOk && rc2 == DcnAux::kOk && dp[0] >= 0x10 && dp[0] <= 0x14 && e[0] <= 0x08) {
                memcpy(caps, e, sizeof caps);
                found = int(ch);
            }
        }
    }
    if (found < 0) { setProperty("Aux,Status", "no-edp-channel"); return false; }
    // Same decision NVRMEdpBL took on the NVIDIA path: TCON adjustable, AUX level supported, no PWM pin.
    bool adjust = caps[1] & 0x01, pwmPin = caps[2] & 0x01, auxSet = caps[2] & 0x02;
    setProperty("Aux,Channel", uint64_t(found), 32);
    setProperty("Aux,EdpCaps", uint64_t(caps[0]) << 16 | uint64_t(caps[1]) << 8 | caps[2], 32);
    if (!adjust || !auxSet || pwmPin) { setProperty("Aux,Status", "panel-not-aux-only"); return false; }
    blBytes = (caps[2] & 0x04) ? 2 : 1;
    blAuxEnable = caps[1] & 0x04;
    uint8_t bits = 0;
    unsigned pn = 0;
    if (aux.read(unsigned(found), kDpcdPwmgenBits, &bits, 1) == DcnAux::kOk) pn = bits & 0x1f;
    if (!pn && aux.read(unsigned(found), kDpcdPwmgenMax, &bits, 1) == DcnAux::kOk) pn = bits & 0x1f;
    if (!pn || pn > blBytes * 8) pn = blBytes * 8;
    blMax = pn >= 32 ? 0xffffffffu : (1u << pn) - 1u;
    // Where the panel is now: DPCD mode with a level -> that level; otherwise the firmware default (full).
    uint8_t cur[4] = {};
    if (aux.read(unsigned(found), kDpcdDisplayCtl, cur, 4) == DcnAux::kOk && (cur[1] & 3) == 2 && blMax) {
        uint32_t lv = blBytes == 2 ? uint32_t(cur[2]) << 8 | cur[3] : cur[2];
        blPercent = uint32_t((uint64_t(lv) * 100 + blMax / 2) / blMax);
        if (blPercent > 100) blPercent = 100;
    }
    // Read-only evidence for the panel's brightness interface: eDP caps/controls and the sink extension block
    // (OLED / SDR-AUX flags, luminance range) that decide whether level writes at 0x722 are the whole story.
    dumpDpcd(unsigned(found), 0x700, 16, "Aux,Dpcd700");
    dumpDpcd(unsigned(found), 0x720, 16, "Aux,Dpcd720");
    dumpDpcd(unsigned(found), 0x300, 16, "Aux,Dpcd300");
    dumpDpcd(unsigned(found), 0x310, 16, "Aux,Dpcd310");
    dumpDpcd(unsigned(found), 0x320, 16, "Aux,Dpcd320");
    dumpDpcd(unsigned(found), 0x330, 16, "Aux,Dpcd330");
    dumpDpcd(unsigned(found), 0x340, 16, "Aux,Dpcd340");
    dumpDpcd(unsigned(found), 0x350, 16, "Aux,Dpcd350");
    blLock = IOLockAlloc();
    if (!blLock) { setProperty("Aux,Status", "no-lock"); return false; }
    auxChannel = found;
    aux.keepEnabled = true;
    setProperty("Aux,Status", "panel-aux-brightness");
    setProperty("Backlight,Max", blMax, 32);
    setProperty("Backlight,Bytes", blBytes, 32);
    setProperty("Backlight,Percent", blPercent, 32);
    IOLog("StrixGOP: eDP AUX brightness on channel %d: rev 0x%02x caps 0x%02x 0x%02x, %u byte(s), max %u, now %u%%\n",
          found, caps[0], caps[1], caps[2], blBytes, blMax, blPercent);
    return true;
}

void StrixGOPFramebuffer::dumpDpcd(unsigned ch, uint32_t addr, unsigned n, const char *key) {
    uint8_t b[16] = {};
    if (n > sizeof b) n = sizeof b;
    int rc = aux.read(ch, addr, b, n);
    char text[64];
    if (rc != DcnAux::kOk) {
        snprintf(text, sizeof text, "rc=%d", rc);
    } else {
        unsigned o = 0;
        for (unsigned i = 0; i < n && o + 3 < sizeof text; ++i) o += unsigned(snprintf(text + o, sizeof text - o, "%02x", b[i]));
    }
    setProperty(key, text);
    IOLog("StrixGOP: dpcd %05x %s\n", addr, text);
}

void StrixGOPFramebuffer::publishBacklight() {
    backlight = StrixBacklightHandler::with(this, blPercent);
    if (!backlight) { IOLog("StrixGOP: backlight handler allocation failed\n"); return; }
    backlight->setName("backlight");
    if (!backlight->attach(this)) {
        backlight->orphan(); backlight->release(); backlight = nullptr;
        IOLog("StrixGOP: backlight handler attach failed\n");
        return;
    }
    backlight->registerService(kIOServiceSynchronous);
    setProperty("Backlight,Handler", true);
    setProperty("Backlight,SleepCount", sleepCount, 32);
    setProperty("Backlight,WakeCount", wakeCount, 32);
    IOLog("StrixGOP: backlight handler published at %u%%\n", blPercent);
}

// AppleBacklightDisplay::probe takes only an LCD connection.
IOReturn StrixGOPFramebuffer::getAppleSense(IOIndex connectIndex, UInt32 *senseType, UInt32 *primary,
                                            UInt32 *extended, UInt32 *displayType) {
    if (connectIndex != 0 || !backlight) return kIOReturnUnsupported;
    if (senseType) *senseType = 0;
    if (primary) *primary = 0;
    if (extended) *extended = 0;
    if (displayType) *displayType = kGenericLCD;
    return kIOReturnSuccess;
}

// Level first, then the mode: the panel never sits in DPCD mode with a stale level (NVRMEdpBL order).
bool StrixGOPFramebuffer::setPanelPercent(uint32_t percent) {
    if (auxChannel < 0 || !blLock || !blMax) return false;
    if (percent > 100) percent = 100;
    uint32_t level = uint32_t((uint64_t(percent) * blMax + 50) / 100);
    uint8_t b[2] = {uint8_t(level >> 8), uint8_t(level)};
    if (blBytes == 1) b[0] = uint8_t(level);
    unsigned ch = unsigned(auxChannel);
    IOLockLock(blLock);
    int rc = aux.write(ch, kDpcdBlLevel, b, blBytes);
    if (rc == DcnAux::kOk) {
        uint8_t mode = 0;
        rc = aux.read(ch, kDpcdBlMode, &mode, 1);
        if (rc == DcnAux::kOk && (mode & 3) != 2) {
            mode = uint8_t((mode & ~3) | 2);
            rc = aux.write(ch, kDpcdBlMode, &mode, 1);
        }
    }
    if (rc == DcnAux::kOk && blAuxEnable) {
        uint8_t ctl = 0;
        if (aux.read(ch, kDpcdDisplayCtl, &ctl, 1) == DcnAux::kOk && !(ctl & 1)) {
            ctl |= 1;
            rc = aux.write(ch, kDpcdDisplayCtl, &ctl, 1);
        }
    }
    uint8_t rb[4] = {};
    int rbRc = rc == DcnAux::kOk ? aux.read(ch, kDpcdDisplayCtl, rb, 4) : -1;
    bool ok = rc == DcnAux::kOk;
    if (ok) { blPercent = percent; ++blWrites; } else ++blFailures;
    unsigned writes = blWrites, failures = blFailures;
    IOLockUnlock(blLock);
    setProperty("Backlight,Writes", writes, 32);
    setProperty("Backlight,Failures", failures, 32);
    setProperty("Backlight,LastRc", uint32_t(rc), 32);
    if (ok) {
        setProperty("Backlight,Percent", percent, 32);
        setProperty("Backlight,Level", level, 32);
        char rbs[24];
        snprintf(rbs, sizeof rbs, "%s%02x%02x%02x%02x", rbRc == DcnAux::kOk ? "" : "rc!", rb[0], rb[1], rb[2], rb[3]);
        setProperty("Backlight,Readback", rbs);
        if (writes <= 40) IOLog("StrixGOP: backlight %u%% = level %u of %u, dpcd 720..723 = %s\n", percent, level, blMax, rbs);
    } else if (failures <= 8) {
        IOLog("StrixGOP: backlight %u%% write failed rc=%d\n", percent, rc);
    }
    return ok;
}

OSDefineMetaClassAndStructors(StrixBacklightHandler, IODisplayParameterHandler)

StrixBacklightHandler *StrixBacklightHandler::with(StrixGOPFramebuffer *owner, uint32_t percent) {
    auto h = OSTypeAlloc(StrixBacklightHandler);
    if (!h || !h->init()) { if (h) h->release(); return nullptr; }
    h->fb = owner;
    h->lock = IOLockAlloc();
    h->apply = thread_call_allocate(applyFire, h);
    h->level = percent <= 100 ? SInt32(percent) : 100;
    if (!h->lock || !h->apply) { h->release(); return nullptr; }
    return h;
}

void StrixBacklightHandler::orphan() {
    if (!lock) { fb = nullptr; return; }
    IOLockLock(lock);        // waits for an apply in flight
    fb = nullptr;
    IOLockUnlock(lock);
    if (apply) thread_call_cancel(apply);
}

void StrixBacklightHandler::free() {
    if (apply) {
        thread_call_cancel(apply);
        while (!thread_call_free(apply)) { thread_call_cancel(apply); IOSleep(1); }
        apply = nullptr;
    }
    if (lock) { IOLockFree(lock); lock = nullptr; }
    IODisplayParameterHandler::free();
}

// The framebuffer reports no display parameters, so the display may have no IODisplayParameters yet;
// IODisplay::setProperties() only accepts parameters listed there.
bool StrixBacklightHandler::setDisplay(IODisplay *display) {
    if (!display) return false;
    OSObject *old = display->copyProperty(gIODisplayParametersKey);
    OSDictionary *cur = OSDynamicCast(OSDictionary, old);
    OSDictionary *params = cur ? OSDictionary::withDictionary(cur) : OSDictionary::withCapacity(2);
    if (old) old->release();
    if (!params) return false;
    IODisplay::addParameter(params, gIODisplayBrightnessKey, 0, 100);
    IODisplay::setParameter(params, gIODisplayBrightnessKey, level);
    IODisplay::addParameter(params, gIODisplayLinearBrightnessKey, 0, 100);
    IODisplay::setParameter(params, gIODisplayLinearBrightnessKey, level);
    display->setProperty(gIODisplayParametersKey, params);
    params->release();
    IOLog("StrixGOP: backlight parameters on %s at %d%%\n", display->getName(), int(level));
    return true;
}

bool StrixBacklightHandler::doIntegerSet(OSDictionary *, const OSSymbol *paramName, UInt32 value) {
    if (rawCount < 40) {
        ++rawCount;
        IOLog("StrixGOP: backlight set %s = %u\n", paramName ? paramName->getCStringNoCopy() : "?", unsigned(value));
    }
    if (paramName != gIODisplayBrightnessKey && paramName != gIODisplayLinearBrightnessKey) return false;
    pending = value > 100 ? 100 : SInt32(value);
    if (apply) thread_call_enter(apply);
    return true;
}

void StrixBacklightHandler::applyFire(thread_call_param_t p, thread_call_param_t) {
    auto me = static_cast<StrixBacklightHandler *>(p);
    SInt32 v;
    do { v = me->pending; } while (!OSCompareAndSwap(UInt32(v), UInt32(-1), (volatile UInt32 *)&me->pending));
    if (v < 0) return;
    IOLockLock(me->lock);
    StrixGOPFramebuffer *owner = me->fb;
    if (owner) {
        // Level 0 is a real off: display sleep parks here, and real Macs go fully dark at slider 0.
        // (The old 5% floor kept the panel visibly on during display sleep.)
        uint32_t percent = uint32_t(v);
        if (owner->setPanelPercent(percent)) me->level = v;
    }
    IOLockUnlock(me->lock);
}
