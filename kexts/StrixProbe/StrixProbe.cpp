// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Step 02: opt-in IOResources diagnostic service, never a GPU driver.
// No provider open, MMIO mapping, config writes, DMA, mailbox or ACPI methods.
#include <IOKit/IOService.h>
#include <IOKit/IOPlatformExpert.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <IOKit/IOLib.h>
#include <libkern/OSByteOrder.h>
#include <pexpert/pexpert.h>

class StrixProbe : public IOService {
    OSDeclareDefaultStructors(StrixProbe)
public:
    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
private:
    IONotifier *pciNotifier = nullptr;
    static bool pciPublished(void *target, void *, IOService *service, IONotifier *);
    void capturePCI();
    void captureConsole();
    void captureVFCT();
};
OSDefineMetaClassAndStructors(StrixProbe, IOService)

bool StrixProbe::pciPublished(void *target, void *, IOService *service, IONotifier *) {
    auto pci = OSDynamicCast(IOPCIDevice, service);
    if (!pci || pci->configRead32((UInt8)0) != 0x150e1002) return true;
    auto self = static_cast<StrixProbe *>(target);
    self->capturePCI();
    self->setProperty("PCI,Acquisition", "target-publish-notification");
    return true;
}

void StrixProbe::stop(IOService *provider) {
    if (pciNotifier) { pciNotifier->remove(); pciNotifier = nullptr; }
    IOService::stop(provider);
}

IOService *StrixProbe::probe(IOService *provider, SInt32 *score) {
    int enabled = 0;
    if (!PE_parse_boot_argn("strix-probe", &enabled, sizeof(enabled)) || enabled != 1)
        return nullptr;
    return IOService::probe(provider, score);
}

void StrixProbe::capturePCI() {
    auto matching = serviceMatching("IOPCIDevice");
    auto iterator = matching ? getMatchingServices(matching) : nullptr;
    // Kernel getMatchingServices borrows the dictionary (unlike user-space IOKit).
    if (matching) matching->release();
    if (!iterator) { setProperty("PCI,Status", "iterator-unavailable"); return; }
    unsigned matches = 0;
    while (auto object = iterator->getNextObject()) {
        auto pci = OSDynamicCast(IOPCIDevice, object);
        if (!pci || pci->configRead32((UInt8)0) != 0x150e1002) continue;
        char name[32];
        snprintf(name, sizeof(name), "GPU%u", matches++);
        auto entry = OSDictionary::withCapacity(16);
        if (!entry) continue;
        auto put = [&](const char *key, UInt64 value, unsigned bits = 64) {
            auto number = OSNumber::withNumber(value, bits);
            if (number) { entry->setObject(key, number); number->release(); }
        };
        put("VendorDevice", pci->configRead32((UInt8)0), 32);
        put("RevisionClass", pci->configRead32((UInt8)8), 32);
        put("CommandStatus", pci->configRead32((UInt8)4), 32);
        put("Subsystem", pci->configRead32((UInt8)0x2c), 32);
        put("RegistryID", pci->getRegistryEntryID());
        char path[512]; int length = sizeof(path);
        if (pci->getPath(path, &length, gIOServicePlane)) {
            auto string = OSString::withCString(path);
            if (string) { entry->setObject("RegistryPath", string); string->release(); }
        }
        const char *keys[] = {"class-code", "name", "IOName", "disable-gpu"};
        for (auto key : keys)
            if (auto value = pci->getProperty(key)) entry->setObject(key, value);
        for (unsigned bar = 0; bar < 6; ++bar) {
            UInt8 reg = static_cast<UInt8>(0x10 + 4 * bar);
            char key[40];
            snprintf(key, sizeof(key), "BAR%u,Config", bar);
            put(key, pci->configRead32(reg), 32);
            // Uses OS-owned resource descriptors. Does not map the aperture or size BARs by writing all-ones.
            if (auto memory = pci->getDeviceMemoryWithRegister(reg)) {
                snprintf(key, sizeof(key), "BAR%u,OSBase", bar); put(key, memory->getPhysicalAddress());
                snprintf(key, sizeof(key), "BAR%u,OSLength", bar); put(key, memory->getLength());
            }
        }
        UInt8 config[256];
        for (unsigned offset = 0; offset < sizeof(config); offset += 4) {
            UInt32 value = pci->configRead32((UInt8)offset);
            OSWriteLittleInt32(config, offset, value);
        }
        auto bytes = OSData::withBytes(config, sizeof(config));
        if (bytes) { entry->setObject("PCIConfig256", bytes); bytes->release(); }
        setProperty(name, entry); entry->release();
        IOLog("StrixProbe: step02 %s PCI 1002:150e enumerated; no GPU writes\n", name);
    }
    iterator->release();
    setProperty("PCI,MatchCount", (UInt64)matches, 32);
    setProperty("PCI,Status", matches == 1 ? "one-target" : matches ? "ambiguous" : "not-found-at-snapshot");
}

void StrixProbe::captureConsole() {
    PE_Video video {};
    auto platform = getPlatform();
    if (!platform || platform->getConsoleInfo(&video) != kIOReturnSuccess) {
        setProperty("Console,Status", "unavailable"); return;
    }
    setProperty("Console,RawBase", (UInt64)video.v_baseAddr, 64);
    // A candidate only: no claim that this physical range belongs to 890M.
    setProperty("Console,PageAlignedCandidate", (UInt64)video.v_baseAddr & ~0xfffull, 64);
    setProperty("Console,Width", (UInt64)video.v_width, 64);
    setProperty("Console,Height", (UInt64)video.v_height, 64);
    setProperty("Console,RowBytes", (UInt64)video.v_rowBytes, 64);
    setProperty("Console,Depth", (UInt64)video.v_depth, 64);
    setProperty("Console,Offset", (UInt64)video.v_offset, 64);
    setProperty("Console,Length", (UInt64)video.v_length, 64);
    setProperty("Console,PixelFormatRaw", video.v_pixelFormat, sizeof(video.v_pixelFormat));
    setProperty("Console,Status", "captured-owner-unverified");
}

void StrixProbe::captureVFCT() {
    auto matching = serviceMatching("IOACPIPlatformDevice");
    auto iterator = matching ? getMatchingServices(matching) : nullptr;
    if (matching) matching->release();
    if (!iterator) { setProperty("VFCT,Status", "acpi-iterator-unavailable"); return; }
    bool found = false;
    while (auto object = iterator->getNextObject()) {
        auto acpi = OSDynamicCast(IOACPIPlatformDevice, object);
        if (!acpi) continue;
        // Query a table through the platform API; never evaluate _OFF/ATPX or any AML method.
        const OSData *table = acpi->getACPITableData("VFCT", 0);
        if (!table) continue;
        found = true;
        UInt32 length = table->getLength();
        if (length < 76 || length > 1024 * 1024) {
            setProperty("VFCT,Status", "length-rejected"); break;
        }
        const auto data = static_cast<const UInt8 *>(table->getBytesNoCopy());
        unsigned sum = 0;
        for (unsigned i = 0; i < length; ++i) sum += data[i];
        if (data[0] != 'V' || data[1] != 'F' || data[2] != 'C' || data[3] != 'T' ||
            OSReadLittleInt32(data, 4) != length || (sum & 255)) {
            setProperty("VFCT,Status", "header-or-checksum-rejected"); break;
        }
        setProperty("VFCT,Raw", const_cast<OSData *>(table));
        setProperty("VFCT,Length", (UInt64)length, 32);
        setProperty("VFCT,Status", "captured-parse-offline");
        break;
    }
    iterator->release();
    if (!found) setProperty("VFCT,Status", "not-published-through-acpi-device-api");
}

bool StrixProbe::start(IOService *provider) {
    if (!IOService::start(provider)) return false;
    setProperty("TraceStep", "890M-02");
    setProperty("ProbeVersion", "0.1.1");
    setProperty("GPUWrites", false);
    setProperty("IPDiscovery,Status", "not-acquired-no-mmio-or-indirect-writes");
    capturePCI(); captureConsole(); captureVFCT();
    auto matching = serviceMatching("IOPCIDevice");
    if (matching) {
        pciNotifier = addMatchingNotification(gIOFirstPublishNotification, matching,
                                             pciPublished, this);
        matching->release();
    }
    setProperty("PCI,NotificationInstalled", pciNotifier != nullptr);
    registerService();
    IOLog("StrixProbe: step02 snapshot published; no driver init, MMIO or GPU power changes\n");
    return true;
}
