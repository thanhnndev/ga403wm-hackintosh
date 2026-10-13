// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step03: fixed GOP raster. IOGraphics/WindowServer may write only that raster.
// No DCN/SMU/PSP/GFX init, modesetting, MMIO, GPU allocator or acceleration.
#include <IOKit/graphics/IOFramebuffer.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/IODeviceMemory.h>
#include <libkern/OSByteOrder.h>
#include "GopLayout.h"

class StrixGOPFramebuffer : public IOFramebuffer {
    OSDeclareDefaultStructors(StrixGOPFramebuffer)
    GopLayout layout {};
    uint64_t raster = 0;
    IODeviceMemory *surface = nullptr;
    static constexpr IODisplayModeID fixedMode = 1;
    bool readProfile(IOPCIDevice *pci);
public:
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
    setProperty("StrixGOPVersion", "0.1.0");
    setProperty("HardwareModesetting", false);
    setProperty("Acceleration", false);
    setProperty("Aperture,Base", layout.barBase + layout.offset, 64);
    setProperty("Aperture,RasterBytes", raster, 64);
    setProperty("PixelFormat,Status", "XRGB8888-selected-needs-color-validation");
    // Superclass publishes the service and handles IOGraphics lifecycle.
    return IOFramebuffer::start(provider);
}

void StrixGOPFramebuffer::free() {
    if (surface) { surface->release(); surface = nullptr; }
    IOFramebuffer::free();
}

IOReturn StrixGOPFramebuffer::enableController() {
    IOLog("StrixGOP: fixed raster %ux%u stride %u; no hardware modeset\n",
          layout.width, layout.height, layout.stride);
    setProperty("Controller,Enabled", surface != nullptr);
    return surface ? kIOReturnSuccess : kIOReturnNotReady;
}

IODeviceMemory *StrixGOPFramebuffer::getApertureRange(IOPixelAperture aperture) {
    if (aperture != kIOFBSystemAperture || !surface) return nullptr;
    surface->retain(); return surface; // One consumed reference per call.
}
IODeviceMemory *StrixGOPFramebuffer::getVRAMRange() { return getApertureRange(kIOFBSystemAperture); }
const char *StrixGOPFramebuffer::getPixelFormats() { return IO32BitDirectPixels "\0"; }
IOItemCount StrixGOPFramebuffer::getDisplayModeCount() { return 1; }
UInt64 StrixGOPFramebuffer::getPixelFormatsForDisplayMode(IODisplayModeID, IOIndex) { return 0; }
IOReturn StrixGOPFramebuffer::getDisplayModes(IODisplayModeID *modes) {
    if (!modes) return kIOReturnBadArgument;
    modes[0] = fixedMode; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getInformationForDisplayMode(IODisplayModeID mode, IODisplayModeInformation *info) {
    if (mode != fixedMode || !info) return kIOReturnBadArgument;
    bzero(info, sizeof(*info));
    info->nominalWidth = layout.width; info->nominalHeight = layout.height;
    info->maxDepthIndex = 0;
    // Refresh is unspecified: no fabricated timing from EDID or changed scanout.
    info->flags = kDisplayModeValidFlag | kDisplayModeSafeFlag | kDisplayModeDefaultFlag |
                  kDisplayModeBuiltInFlag | kDisplayModeNativeFlag;
    return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getPixelInformation(IODisplayModeID mode, IOIndex depth,
    IOPixelAperture aperture, IOPixelInformation *info) {
    if (mode != fixedMode || depth != 0 || aperture != kIOFBSystemAperture || !info)
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
    *mode = fixedMode; *depth = 0; return kIOReturnSuccess;
}
IOReturn StrixGOPFramebuffer::getStartupDisplayMode(IODisplayModeID *mode, IOIndex *depth) {
    return getCurrentDisplayMode(mode, depth);
}
IOReturn StrixGOPFramebuffer::setDisplayMode(IODisplayModeID mode, IOIndex depth) {
    return mode == fixedMode && depth == 0 ? kIOReturnSuccess : kIOReturnUnsupported;
}
IOReturn StrixGOPFramebuffer::setStartupDisplayMode(IODisplayModeID mode, IOIndex depth) {
    return setDisplayMode(mode, depth);
}
IOReturn StrixGOPFramebuffer::getAttribute(IOSelect attribute, uintptr_t *value) {
    if (!value) return kIOReturnBadArgument;
    if (attribute == kIOHardwareCursorAttribute) { *value = 0; return kIOReturnSuccess; }
    return IOFramebuffer::getAttribute(attribute, value);
}
IOReturn StrixGOPFramebuffer::getAttributeForConnection(IOIndex connection, IOSelect attribute, uintptr_t *value) {
    if (connection || !value) return kIOReturnBadArgument;
    switch (attribute) {
        case kConnectionEnable:
        case kConnectionCheckEnable: *value = 1; return kIOReturnSuccess;
        case kConnectionFlags: *value = kIOConnectionBuiltIn; return kIOReturnSuccess;
        default: return IOFramebuffer::getAttributeForConnection(connection, attribute, value);
    }
}
