// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step03: fixed GOP raster. IOGraphics/WindowServer may write only that raster.
// No DCN/SMU/PSP/GFX init, modesetting, MMIO, GPU allocator or acceleration.
#include <IOKit/graphics/IOFramebuffer.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IODeviceMemory.h>
#include <libkern/OSByteOrder.h>
#include <pexpert/pexpert.h>
#include "GopLayout.h"

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
    bool readProfile(IOPCIDevice *pci);
    bool loadEdid();
    void logAttribute(const char *where, IOIndex connection, IOSelect attribute, uintptr_t value, IOReturn rc);
    bool takeSample(uint32_t *out);
    void refreshSample();
public:
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
    setProperty("StrixGOPVersion", "0.1.4");
    setProperty("HardwareModesetting", false);
    setProperty("Acceleration", false);
    setProperty("Aperture,Base", layout.barBase + layout.offset, 64);
    setProperty("Aperture,RasterBytes", raster, 64);
    setProperty("PixelFormat,Status", "XRGB8888-selected-needs-color-validation");
    loadEdid();
    // Superclass publishes the service and handles IOGraphics lifecycle.
    return IOFramebuffer::start(provider);
}

void StrixGOPFramebuffer::free() {
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
IOItemCount StrixGOPFramebuffer::getDisplayModeCount() { return 2; }
UInt64 StrixGOPFramebuffer::getPixelFormatsForDisplayMode(IODisplayModeID, IOIndex) { return 0; }
IOReturn StrixGOPFramebuffer::getDisplayModes(IODisplayModeID *modes) {
    if (!modes) return kIOReturnBadArgument;
    modes[0] = mode60; modes[1] = mode120; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getInformationForDisplayMode(IODisplayModeID mode, IODisplayModeInformation *info) {
    if ((mode != mode60 && mode != mode120) || !info) return kIOReturnBadArgument;
    bzero(info, sizeof(*info));
    info->nominalWidth = layout.width; info->nominalHeight = layout.height;
    // Step01 EDID (ATNA40CU05-0): 60 Hz base DTD 652.270 MHz (htotal 2980,
    // vtotal 3648), 120 Hz DisplayID 652.264 MHz (htotal 2980, vtotal 1824).
    // Previously zero, which published IOFB0Hz and left CoreDisplay with no
    // display pipe (frozen boot logo while the WindowServer shadow composited
    // fine). Default is the boot scanout (120 Hz). No hardware modeset.
    info->refreshRate = mode == mode120 ? IOFixed1616(120 << 16) : IOFixed1616(60 << 16);
    info->maxDepthIndex = 0;
    info->flags = kDisplayModeValidFlag | kDisplayModeSafeFlag |
                  kDisplayModeBuiltInFlag | kDisplayModeNativeFlag |
                  kDisplayModeValidForHiResFlag;
    if (mode == mode120) info->flags |= kDisplayModeDefaultFlag;
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getTimingInfoForDisplayMode(IODisplayModeID mode, IOTimingInformation *info) {
    if ((mode != mode60 && mode != mode120) || !info) return kIOReturnBadArgument;
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
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getPixelInformation(IODisplayModeID mode, IOIndex depth,
    IOPixelAperture aperture, IOPixelInformation *info) {
    if ((mode != mode60 && mode != mode120) || depth != 0 || aperture != kIOFBSystemAperture || !info)
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
    if ((mode != mode60 && mode != mode120) || depth != 0) return kIOReturnUnsupported;
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
IOReturn StrixGOPFramebuffer::setAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t value) {
    IOReturn rc;
    switch (attribute) {
        case kConnectionPower:
        case kConnectionPostWake:
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
        default: return IOFramebuffer::getAttributeForConnection(connection, attribute, value);
    }
}
