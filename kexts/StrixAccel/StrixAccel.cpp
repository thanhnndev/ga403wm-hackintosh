// SPDX-License-Identifier: BSD-3-Clause-Clear
//
// StrixAccel: the native, display-only accelerator of the Radeon 890M (Strix Point, 1002:150e rev c1).
//
// Root cause it removes: StrixGOPFramebuffer adopts the boot GOP raster, but CoreDisplay cannot attach a framebuffer
// that has no IOAccelerator / IOAccelDisplayPipe ("Unable to find display pipe for IOFB service"), so WindowServer
// never presents to the OLED.  This kext publishes a minimal IOGraphicsAccelerator2 subclass that owns exactly one
// thing: a display pipe whose transactions are completed in software by copying the plane's IOSurface into the
// GOP raster.  No GPU command submission, no GL/CL/Metal context, no DCN/SMU/PSP access, no interrupts.
//
// Class layout comes from the machine's own IOAcceleratorFamily2 (IOAccelFamily2_decl.h is generated from the
// kernel collection by tools/ioaccel_gen_header.py); a runtime gate refuses to start on any mismatch.
// Kill switch: boot-arg -strixaccoff.
#include <IOKit/IOLib.h>
#include <IOKit/IOService.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IODeviceMemory.h>
#include <IOKit/IORangeAllocator.h>
#include <IOKit/IOKitKeys.h>
#include <libkern/OSAtomic.h>
#include <libkern/c++/OSMetaClass.h>
#include <libkern/c++/OSSymbol.h>
#include <pexpert/pexpert.h>
#include <kern/thread_call.h>
#include <kern/clock.h>
#include <mach/kmod.h>
#include <libkern/version.h>
#include "../../include/StrixNativeABI.h"
#include "StrixABIProfile.h"

#define STRIXACCEL_VERSION "0.1.12"

#include "IOAccelFamily2_decl.h"

// ---- family symbols that are not virtual (exact exported names, verified by the undefined-symbol check in build.sh) ----
extern "C" {
bool strix_IOAccelTask_init(IOAccelTask *self, IOGraphicsAccelerator2 *accel, unsigned int n, IORangeAllocator **ra)
    __asm__("__ZN11IOAccelTask4initEP22IOGraphicsAccelerator2jPP16IORangeAllocator");
IOAccelSysMemory *strix_withMemoryDescriptor(IOGraphicsAccelerator2 *accel, IOAccelResource2 *res, IOMemoryDescriptor *md)
    __asm__("__ZN16IOAccelSysMemory20withMemoryDescriptorEP22IOGraphicsAccelerator2P16IOAccelResource2P18IOMemoryDescriptor");
IOAccelEventMachine2 *strix_pipe_getEventMachine(const IOAccelDisplayPipe *p)
    __asm__("__ZNK18IOAccelDisplayPipe15getEventMachineEv");
IOFramebuffer *strix_pipe_getFramebuffer(const IOAccelDisplayPipe *p)
    __asm__("__ZNK18IOAccelDisplayPipe14getFramebufferEv");
IOSurface *strix_txn_getPlaneIOSurface(const IOAccelDisplayPipeTransaction2 *t, unsigned int plane, unsigned int idx)
    __asm__("__ZNK30IOAccelDisplayPipeTransaction217getPlaneIOSurfaceEjj");
// IOSurface (com.apple.iokit.IOSurface): non-virtual getters, `this` as first argument
IOMemoryDescriptor *strix_surf_getMemoryDescriptor(const IOSurface *s) __asm__("__ZNK9IOSurface19getMemoryDescriptorEv");
uint32_t strix_surf_getBytesPerRow(const IOSurface *s) __asm__("__ZNK9IOSurface14getBytesPerRowEv");
uint32_t strix_surf_getWidth(const IOSurface *s) __asm__("__ZNK9IOSurface8getWidthEv");
uint32_t strix_surf_getHeight(const IOSurface *s) __asm__("__ZNK9IOSurface9getHeightEv");
uint32_t strix_surf_getPixelFormat(const IOSurface *s) __asm__("__ZNK9IOSurface14getPixelFormatEv");
uint32_t strix_surf_getSurfaceID(const IOSurface *s) __asm__("__ZNK9IOSurface12getSurfaceIDEv");
uint32_t strix_surf_getBytesPerElement(const IOSurface *s) __asm__("__ZNK9IOSurface18getBytesPerElementEv");
uint32_t strix_surf_getPlaneOffset(const IOSurface *s, unsigned int plane) __asm__("__ZNK9IOSurface14getPlaneOffsetEj");
bool strix_surf_isTiled(IOSurface *s) __asm__("__ZN9IOSurface7isTiledEv");
}

// vtables (leaf and family) for the runtime gate: slot i is at index 2+i
extern "C" {
extern const uintptr_t strix_ztv_Accelerator[] __asm__("__ZTV16StrixAccelerator");
extern const uintptr_t strix_ztv_EventMachine[] __asm__("__ZTV17StrixEventMachine");
extern const uintptr_t strix_ztv_Task[] __asm__("__ZTV9StrixTask");
extern const uintptr_t strix_ztv_DisplayMachine[] __asm__("__ZTV19StrixDisplayMachine");
extern const uintptr_t strix_ztv_DisplayPipe[] __asm__("__ZTV16StrixDisplayPipe");
extern const uintptr_t strix_ztv_SysMemory[] __asm__("__ZTV14StrixSysMemory");
extern const uintptr_t strix_ztv_VidMemory[] __asm__("__ZTV14StrixVidMemory");
extern const uintptr_t strix_ztv_Resource[] __asm__("__ZTV13StrixResource");
extern const uintptr_t strix_ztv_MemoryMap[] __asm__("__ZTV14StrixMemoryMap");
extern const uintptr_t fam_ztv_Accelerator[] __asm__("__ZTV22IOGraphicsAccelerator2");
extern const uintptr_t fam_ztv_EventMachine2[] __asm__("__ZTV20IOAccelEventMachine2");
extern const uintptr_t fam_ztv_EventMachine[] __asm__("__ZTV24IOAccelEventMachineFast2");
extern const uintptr_t fam_ztv_Task[] __asm__("__ZTV11IOAccelTask");
extern const uintptr_t fam_ztv_DisplayMachine[] __asm__("__ZTV21IOAccelDisplayMachine");
extern const uintptr_t fam_ztv_DisplayPipe[] __asm__("__ZTV18IOAccelDisplayPipe");
extern const uintptr_t fam_ztv_SysMemory[] __asm__("__ZTV16IOAccelSysMemory");
extern const uintptr_t fam_ztv_VidMemory[] __asm__("__ZTV16IOAccelVidMemory");
extern const uintptr_t fam_ztv_Resource[] __asm__("__ZTV16IOAccelResource2");
extern const uintptr_t fam_ztv_MemoryMap[] __asm__("__ZTV16IOAccelMemoryMap");
}

#define SLOG(fmt, ...) IOLog("StrixAccel: " fmt "\n", ##__VA_ARGS__)

// Runtime tunables (IORegistryEntrySetCFProperties on the accelerator, see StrixAccelerator::setProperties and
// tools/strix_accel_tune.c): every present-path experiment is a property write, not a reboot.
static volatile int32_t gTuneMode = 1;       // 0 = full-frame copy, 1 = block diff against a shadow
static volatile int32_t gTuneAsync = 1;      // 1 = present on a worker thread (latest frame wins), 0 = in WindowServer's thread
static volatile int32_t gTuneSrcCache = 0;   // source mapping cache: 0 default, 1 copyback, 2 write-through.
// 3 (inhibit) and 4 (write-combine) are accepted but aliased to default: uncached/WC source reads stall the pipe
// (measured 0.1.9: SrcRead 188 ms WC vs 0.6 ms cached, copy 390 ms avg, display-link collapses to ~12 fps).
static volatile int32_t gTuneProbe = 0;      // 1 = run the bandwidth probe on the next presented frame
static volatile int32_t gTuneBlock = 128;    // diff block size in bytes (multiple of 8)
static volatile int32_t gCacheGen = 0;       // bumped when the source cache mode changes: pipes drop their mappings
static volatile int32_t gCoalesced = 0;      // frames replaced by a newer one before the worker got to them
static volatile int64_t gSubmitNs, gSubmitMaxNs, gSubmitCalls;
static volatile int64_t gCmpNs, gWriteNs, gFullNs, gProbeSrcNs, gProbeShNs, gProbeWcNs;
static volatile int64_t gCopyNs, gCopyMaxNs, gWrittenBytes, gCopyCalls, gFullFrames, gCopyBlocks;
static volatile int32_t gGate;        // 0 unchecked, 1 pass, 2 fail (fail closed for the rest of the boot)
static volatile int32_t gCounters[9]; // 0 pipes, 1 txn, 2 copied, 3 skipped, 4 begin, 5 validate fail, 6 tiled, 7 unsupported fmt, 8 no-plane

enum { kCPipes, kCTxn, kCCopied, kCSkipped, kCBegin, kCValidateFail, kCTiled, kCFormat, kCNoPlane };

class StrixAccelerator;
class StrixDisplayMachine;
class StrixDeviceControl;

// ---------------------------------------------------------------------------------------------------------------------
// classes
// ---------------------------------------------------------------------------------------------------------------------
class StrixAccelerator : public IOGraphicsAccelerator2 {
    OSDeclareDefaultStructors(StrixAccelerator)
public:
    STRIXACCEL_LEAFDECL_IOGraphicsAccelerator2

    IOPCIDevice *pci;
    IOBufferMemoryDescriptor *stampMD;
    volatile uint32_t *stampVA;
    StrixDisplayMachine *machine;      // retained
    IONotifier *fbNotifier;
    StrixDeviceControl *agdc;          // retained; created from the scan thread call
    thread_call_t scanCall;
    volatile int32_t stopping;
    volatile int32_t scanTicks;
    volatile int32_t inTick;          // thread_call_cancel_wait is private KPI: wait on this instead

    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn newUserClient(task_t task, void *securityID, unsigned int type, IOUserClient **handler) override;
    IOReturn queryNativeInfo(s89n_info *info);
    IOReturn readFoundation(s89n_foundation *info);

    IOMemoryDescriptor *getStampMemory(unsigned int *n) override;
    IOAccelEventMachine2 *newEventMachine() override;
    IOAccelTask *createUserGPUTask() override;
    IOAccelTask *createKernelGPUTask() override;
    void populateAccelConfig(IOAccelConfig *cfg) override;
    uint32_t savedClassCode;
    bool classCodeRestored;
    void restoreClassCode(IOService *provider);
    bool configureDevice(IOPCIDevice *dev) override;
    void teardownDevice(IOPCIDevice *dev) override;
    IOAccelDisplayMachine *newDisplayMachine() override;
    uintptr_t newGLContext() override;
    uintptr_t newCLContext() override;
    uintptr_t newSurface() override;
    uintptr_t new2DContext() override;
    uintptr_t newVideoContext() override;
    IOAccelDisplayPipe *newDisplayPipe() override;
    IOAccelSysMemory *newSysMemory() override;
    uintptr_t newVidMemory() override;
    uintptr_t newResource() override;
    uintptr_t newMemoryMap() override;

    void scan(const char *why);
    void publishCounters();
    IOReturn setProperties(OSObject *props) override;
    static void scanTick(thread_call_param_t self, thread_call_param_t);
    static bool onFramebuffer(void *target, void *ref, IOService *svc, IONotifier *n);
    bool layoutGate();
};

// Read-only S89N endpoint. No userspace BAR maps, GPU BOs or submissions.
// The admin-only foundation selector reads three fixed bootstrap registers.
class StrixNativeClient : public IOUserClient {
    OSDeclareDefaultStructors(StrixNativeClient)
    bool negotiated = false;
public:
    IOReturn clientClose() override { terminate(); return kIOReturnSuccess; }
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                           IOExternalMethodDispatch *dispatch = nullptr,
                           OSObject *target = nullptr, void *reference = nullptr) override;
    static IOReturn hello(OSObject *target, void *, IOExternalMethodArguments *args);
    static IOReturn query(OSObject *target, void *, IOExternalMethodArguments *args);
    static IOReturn foundation(OSObject *target, void *, IOExternalMethodArguments *args);
};
OSDefineMetaClassAndStructors(StrixNativeClient, IOUserClient)

class StrixEventMachine : public IOAccelEventMachineFast2 {
    OSDeclareDefaultStructors(StrixEventMachine)
public:
    bool init(IOGraphicsAccelerator2 *accel, unsigned int n, int timeout) override;
    // Fast2 pure slots 84..87 + the forwarded slot 70
    void writeStamp(int, vendevtCommandRec *, unsigned int) override;
    void prepareBarrier(vendevtBarrierRec *) override;
    bool completeBarrier(vendevtBarrierRec *) override;
    void writeBarrierElement(vendevtBarrierRec *, int, unsigned int) override;
    STRIXACCEL_LEAFDECL_IOAccelEventMachineFast2
};

class StrixTask : public IOAccelTask {
    OSDeclareDefaultStructors(StrixTask)
public:
    bool setup(IOGraphicsAccelerator2 *accel);
};

class StrixDisplayMachine : public IOAccelDisplayMachine {
    OSDeclareDefaultStructors(StrixDisplayMachine)
public:
    bool displayModeWillChange() override;
    bool displayModeDidChange() override;
    uintptr_t found_framebuffer(IOFramebuffer *fb) override;
};

class StrixSysMemory : public IOAccelSysMemory {
    OSDeclareDefaultStructors(StrixSysMemory)
public:
    STRIXACCEL_LEAFDECL_IOAccelSysMemory
};

class StrixVidMemory : public IOAccelVidMemory {
    OSDeclareDefaultStructors(StrixVidMemory)
public:
    STRIXACCEL_LEAFDECL_IOAccelVidMemory
    uint64_t getPhysicalSegment(unsigned long long, unsigned long long *) override;
    uintptr_t allocPhysical() override;
    uintptr_t deallocPhysical() override;
};

class StrixResource : public IOAccelResource2 {
    OSDeclareDefaultStructors(StrixResource)
public:
    STRIXACCEL_LEAFDECL_IOAccelResource2
    uintptr_t rebuildPagingBuffer() override;
    uintptr_t getLevelOffset(unsigned char, unsigned char, int *) override;
    uintptr_t getBackingLevelOffset(unsigned char, unsigned char, int *) override;
    uintptr_t calculateIOSurfaceDeviceCacheVRAMBytes(unsigned long long *, unsigned long long *) override;
    uintptr_t addToAperture() override;
    uintptr_t removeFromAperture() override;
    uintptr_t getApertureMemoryDescriptor(unsigned long long *) override;
};

class StrixMemoryMap : public IOAccelMemoryMap {
    OSDeclareDefaultStructors(StrixMemoryMap)
public:
    STRIXACCEL_LEAFDECL_IOAccelMemoryMap
    uintptr_t commitIntoGPUPageTable() override;
    uintptr_t releaseFromGPUPageTable() override;
    uintptr_t updateGPUPageTable() override;
};

// IOSurface is only forward-declared by the family header; it is an OSObject at offset 0.
static inline void strix_surf_release(IOSurface *s) { reinterpret_cast<OSObject *>(s)->release(); }

class StrixDisplayPipe : public IOAccelDisplayPipe {
    OSDeclareDefaultStructors(StrixDisplayPipe)
public:
    static constexpr unsigned kCache = 4;
    struct SurfMap {
        const void *surface;
        uint32_t id;
        IOMemoryDescriptor *md;
        IOMemoryMap *map;
        bool prepared;
        uint64_t used;
    };

    StrixAccelerator *owner;
    IOLock *lock;
    IODeviceMemory *fbMemory;
    IOMemoryMap *fbMap;
    uint32_t fbWidth, fbHeight, fbStride;
    bool fbReady;
    uint64_t tick;
    SurfMap cache[kCache];
    // Copy shadow: what we last wrote to the aperture (+ one row of scratch).  The aperture is write-combined VRAM, so
    // a full 20 MB frame per transaction is the expensive part; only blocks that differ from the shadow are written.
    IOBufferMemoryDescriptor *shadowMD;
    uint8_t *shadow;
    bool shadowValid;
    unsigned sinceFull;
    // Async present: submitTransaction parks the newest surface here and returns; the worker copies it.
    thread_call_t worker;
    IOLock *qlock;
    IOSurface *pending;
    unsigned pendingN;
    volatile int32_t workerBusy;
    volatile int32_t closing;
    int32_t cacheGen;
    static void workerFire(thread_call_param_t self, thread_call_param_t);
    void presentPending();

    bool init(IOGraphicsAccelerator2 *accel, IOAccelDisplayMachine *machine, IOFramebuffer *fb, unsigned int index) override;
    void free() override;
    uintptr_t initFramebufferResource(unsigned int index, IOAccelResource2 *res) override;
    uintptr_t validateTransaction(IOAccelDisplayPipeTransaction2 *t) override;
    bool isTransactionComplete(IOAccelDisplayPipeTransaction2 *t) override;
    IOReturn submitTransaction(IOAccelDisplayPipeTransaction2 *t) override;
    void beginTransaction(IOAccelEvent *ev) override;

    bool prepareFramebuffer();
    uint8_t *ensureShadow();
    uint8_t *mapSurface(IOSurface *s, uint32_t id);
    bool copySurface(IOSurface *s, unsigned n);
};

#include "StrixAgdc.h"

OSDefineMetaClassAndStructors(StrixAccelerator, IOGraphicsAccelerator2)
OSDefineMetaClassAndStructors(StrixEventMachine, IOAccelEventMachineFast2)
OSDefineMetaClassAndStructors(StrixTask, IOAccelTask)
OSDefineMetaClassAndStructors(StrixDisplayMachine, IOAccelDisplayMachine)
OSDefineMetaClassAndStructors(StrixSysMemory, IOAccelSysMemory)
OSDefineMetaClassAndStructors(StrixVidMemory, IOAccelVidMemory)
OSDefineMetaClassAndStructors(StrixResource, IOAccelResource2)
OSDefineMetaClassAndStructors(StrixMemoryMap, IOAccelMemoryMap)
OSDefineMetaClassAndStructors(StrixDisplayPipe, IOAccelDisplayPipe)

static_assert(sizeof(StrixAccelerator) >= STRIXACCEL_IOGraphicsAccelerator2_SIZE, "accelerator smaller than family");
static_assert(sizeof(StrixEventMachine) >= STRIXACCEL_IOAccelEventMachineFast2_SIZE, "event machine smaller than family");
static_assert(sizeof(StrixTask) >= STRIXACCEL_IOAccelTask_SIZE, "task smaller than family");
static_assert(sizeof(StrixDisplayMachine) >= STRIXACCEL_IOAccelDisplayMachine_SIZE, "display machine smaller than family");
static_assert(sizeof(StrixDisplayPipe) >= STRIXACCEL_IOAccelDisplayPipe_SIZE, "display pipe smaller than family");
static_assert(sizeof(StrixSysMemory) >= STRIXACCEL_IOAccelSysMemory_SIZE, "sys memory smaller than family");
static_assert(sizeof(StrixVidMemory) >= STRIXACCEL_IOAccelVidMemory_SIZE, "vid memory smaller than family");
static_assert(sizeof(StrixResource) >= STRIXACCEL_IOAccelResource2_SIZE, "resource smaller than family");
static_assert(sizeof(StrixMemoryMap) >= STRIXACCEL_IOAccelMemoryMap_SIZE, "memory map smaller than family");

// slots the family does not export a symbol for: naked tail-jumps into the family's own vtable entry
STRIXACCEL_FWD_IOGraphicsAccelerator2(StrixAccelerator)
STRIXACCEL_FWD_IOAccelEventMachineFast2(StrixEventMachine)
STRIXACCEL_FWD_IOAccelSysMemory(StrixSysMemory)
STRIXACCEL_FWD_IOAccelVidMemory(StrixVidMemory)
STRIXACCEL_FWD_IOAccelResource2(StrixResource)
STRIXACCEL_FWD_IOAccelMemoryMap(StrixMemoryMap)

// ---------------------------------------------------------------------------------------------------------------------
// the runtime layout gate: refuse to run when the family does not look like the one the header was generated from
// ---------------------------------------------------------------------------------------------------------------------
bool StrixAccelerator::layoutGate()
{
    // Class sizes alone cannot detect reordered private slots after an OS update.
    auto root = IORegistryEntry::getRegistryRoot();
    auto kernelBuild = root ? OSDynamicCast(OSString, root->getProperty("IOKitBuildVersion")) : nullptr;
    if (version_major != STRIXABI_DARWIN_MAJOR || !kernelBuild ||
        !kernelBuild->isEqualTo(STRIXABI_KERNEL_BUILD)) {
        SLOG("gate FAIL: OS build does not match reviewed profile %s", STRIXABI_PROFILE_ID);
        return false;
    }
    if (gGate) return gGate == 1;
    struct Gate {
        const char *ours, *fam;
        const uintptr_t *zo, *zf;
        uint32_t slots, size;
    };
    const Gate gates[] = {
        {"StrixAccelerator", "IOGraphicsAccelerator2", strix_ztv_Accelerator, fam_ztv_Accelerator,
         STRIXACCEL_IOGraphicsAccelerator2_SLOTS, STRIXACCEL_IOGraphicsAccelerator2_SIZE},
        {"StrixEventMachine", "IOAccelEventMachineFast2", strix_ztv_EventMachine, fam_ztv_EventMachine,
         STRIXACCEL_IOAccelEventMachineFast2_SLOTS, STRIXACCEL_IOAccelEventMachineFast2_SIZE},
        {"StrixTask", "IOAccelTask", strix_ztv_Task, fam_ztv_Task,
         STRIXACCEL_IOAccelTask_SLOTS, STRIXACCEL_IOAccelTask_SIZE},
        {"StrixDisplayMachine", "IOAccelDisplayMachine", strix_ztv_DisplayMachine, fam_ztv_DisplayMachine,
         STRIXACCEL_IOAccelDisplayMachine_SLOTS, STRIXACCEL_IOAccelDisplayMachine_SIZE},
        {"StrixDisplayPipe", "IOAccelDisplayPipe", strix_ztv_DisplayPipe, fam_ztv_DisplayPipe,
         STRIXACCEL_IOAccelDisplayPipe_SLOTS, STRIXACCEL_IOAccelDisplayPipe_SIZE},
        {"StrixSysMemory", "IOAccelSysMemory", strix_ztv_SysMemory, fam_ztv_SysMemory,
         STRIXACCEL_IOAccelSysMemory_SLOTS, STRIXACCEL_IOAccelSysMemory_SIZE},
        {"StrixVidMemory", "IOAccelVidMemory", strix_ztv_VidMemory, fam_ztv_VidMemory,
         STRIXACCEL_IOAccelVidMemory_SLOTS, STRIXACCEL_IOAccelVidMemory_SIZE},
        {"StrixResource", "IOAccelResource2", strix_ztv_Resource, fam_ztv_Resource,
         STRIXACCEL_IOAccelResource2_SLOTS, STRIXACCEL_IOAccelResource2_SIZE},
        {"StrixMemoryMap", "IOAccelMemoryMap", strix_ztv_MemoryMap, fam_ztv_MemoryMap,
         STRIXACCEL_IOAccelMemoryMap_SLOTS, STRIXACCEL_IOAccelMemoryMap_SIZE},
    };
    // IOAccelEventMachine2 slot 36 is pure in the family: its value is the kernel's __cxa_pure_virtual
    const uintptr_t pure = fam_ztv_EventMachine2[2 + 36];
    bool ok = true;
    for (const Gate &g : gates) {
        const OSSymbol *sym = OSSymbol::withCString(g.fam);
        const OSMetaClass *mc = sym ? OSMetaClass::getMetaClassWithName(sym) : nullptr;
        if (sym) sym->release();
        if (!mc || mc->getClassSize() != g.size) {
            SLOG("gate FAIL %s: family size %u, expected %u", g.fam, mc ? (unsigned)mc->getClassSize() : 0u, g.size);
            ok = false;
            break;
        }
        unsigned stillPure = 0, firstPure = 0;
        for (uint32_t i = 0; i < g.slots; ++i) {
            if (g.zo[2 + i] == pure) {   // our own vtable still holds __cxa_pure_virtual
                if (!stillPure) firstPure = i;
                ++stillPure;
            }
        }
        if (stillPure) {
            SLOG("gate FAIL %s: %u pure slot(s) not overridden, first %u", g.ours, stillPure, firstPure);
            ok = false;
            break;
        }
        SLOG("gate %s vs %s: ok (%u slots, size %u)", g.ours, g.fam, g.slots, g.size);
    }
    OSCompareAndSwap(0, ok ? 1 : 2, &gGate);
    return gGate == 1;
}

// ---------------------------------------------------------------------------------------------------------------------
// accelerator
// ---------------------------------------------------------------------------------------------------------------------
IOService *StrixAccelerator::probe(IOService *provider, SInt32 *score)
{
    if (PE_parse_boot_argn("-strixaccoff", nullptr, 0)) return nullptr;
    auto dev = OSDynamicCast(IOPCIDevice, provider);
    if (!dev || dev->configRead32(0) != 0x150e1002 || (dev->configRead32(8) & 255) != 0xc1 ||
        dev->configRead32(0x2c) != 0x39981043)
        return nullptr;
    return IOService::probe(provider, score);
}

// The EFI hides the iGPU from stock drivers with class-code FFFFFFFF on the PCI node.  IOPresentment (CoreDisplay's
// display-pipe path) walks the IOService parents of every accelerator, framebuffer and AGDC service and only accepts a
// PCI node whose class-code is a display class; with the spoof it finds no PCI node, so the accelerator never joins the
// association map ("IOAccelerator = 0") and CoreDisplay reports "Unable to find display pipe".  The hardware value is
// still in config space, so publish that on the node once our own driver owns the device and put the spoof back on stop.
void StrixAccelerator::restoreClassCode(IOService *provider)
{
    auto dev = OSDynamicCast(IOPCIDevice, provider);
    if (!dev) return;
    uint32_t hw = dev->configRead32(8) >> 8;
    uint32_t cur = 0;
    if (OSData *d = OSDynamicCast(OSData, dev->getProperty("class-code"))) {
        if (d->getLength() >= 4) memcpy(&cur, d->getBytesNoCopy(), 4);
    }
    setProperty("StrixAccel,ClassCodeHW", hw, 32);
    setProperty("StrixAccel,ClassCodeSpoof", cur, 32);
    dev->setProperty("model", "AMD Radeon 890M");
    dev->setProperty("VRAM,totalMB", 512ull, 32);
    if ((hw >> 16) != 0x03 || cur == hw) return;
    if (OSData *v = OSData::withBytes(&hw, 4)) {
        dev->setProperty("class-code", v);
        v->release();
        savedClassCode = cur;
        classCodeRestored = true;
        SLOG("class-code 0x%08x -> 0x%08x on the PCI node (IOPresentment node map)", cur, hw);
    }
}

bool StrixAccelerator::start(IOService *provider)
{
    if (PE_parse_boot_argn("-strixaccoff", nullptr, 0)) return false;
    if (!OSDynamicCast(IOPCIDevice, provider)) return false;
    if (!layoutGate()) {
        setProperty("StrixAccel,Gate", "FAIL");
        return false;
    }
    setProperty("StrixAccel,Gate", "PASS");
    setProperty("StrixAccel,Version", STRIXACCEL_VERSION);
    restoreClassCode(provider);
    setProperty("StrixAccel,ABIProfile", STRIXABI_PROFILE_ID);
    setProperty("StrixNative,ABIMajor", S89N_ABI_MAJOR, 32);
    setProperty("StrixNative,MetalReady", false);
    // Display identity: without a "model" property system_profiler falls back to the EFI hide name
    // "#display" and shows "unknown" graphics; without VRAM it reports the 20 MB raster as 19 MB.
    // "model" is informational (matching uses vendor/device/class), VRAM,totalMB is the WhateverGreen
    // convention (512 MiB UMA, not the 256 MiB BAR0 window, not the raster). Both also go on the PCI
    // node in restoreClassCode() so enumerators that walk parents see them.
    setProperty("model", "AMD Radeon 890M");
    setProperty("VRAM,totalMB", 512ull, 32);
    // CoreDisplay only looks for a display pipe (and sends plane transactions) on accelerators that advertise this; the
    // personality carries it too, but the property must not depend on how the match dictionary was merged.
    if (OSDictionary *caps = OSDictionary::withCapacity(2)) {
        OSNumber *one = OSNumber::withNumber(1ULL, 32);
        if (one) {
            caps->setObject("DisplayPipeSupported", one);
            caps->setObject("TransactionsSupported", one);
            one->release();
        }
        setProperty("IOAccelDisplayPipeCapabilities", caps);
        caps->release();
    }

    // 32 stamps, page backed: user clients may map the stamp memory
    stampMD = IOBufferMemoryDescriptor::withOptions(kIODirectionInOut | kIOMemoryKernelUserShared, 4096, 4096);
    if (!stampMD) {
        SLOG("stamp memory allocation failed");
        return false;
    }
    stampVA = static_cast<volatile uint32_t *>(stampMD->getBytesNoCopy());
    bzero((void *)stampVA, 4096);

    SLOG("start: family start");
    if (!IOGraphicsAccelerator2::start(provider)) {
        SLOG("start: IOGraphicsAccelerator2::start failed");
        stampMD->release();
        stampMD = nullptr;
        stampVA = nullptr;
        return false;
    }
    SLOG("start: family start ok, display machine %p", machine);

    scanCall = thread_call_allocate(&StrixAccelerator::scanTick, this);
    OSDictionary *match = IOService::serviceMatching("IOFramebuffer");
    if (match) {
        fbNotifier = IOService::addMatchingNotification(gIOPublishNotification, match,
                                                        &StrixAccelerator::onFramebuffer, this, nullptr, 10);
        match->release();
    }
    registerService();
    scan("start");
    if (scanCall) {
        thread_call_enter(scanCall);    // creates the AGDC service off the registry thread
    }
    publishCounters();
    return true;
}

void StrixAccelerator::stop(IOService *provider)
{
    OSIncrementAtomic(&stopping);
    if (classCodeRestored) {
        if (OSData *v = OSData::withBytes(&savedClassCode, 4)) {
            provider->setProperty("class-code", v);
            v->release();
        }
        classCodeRestored = false;
    }
    if (fbNotifier) {
        fbNotifier->remove();
        fbNotifier = nullptr;
    }
    if (scanCall) {
        thread_call_t c = scanCall;
        scanCall = nullptr;
        thread_call_cancel(c);
        while (inTick) IOSleep(10);   // a callout that was already running finishes before we free
        thread_call_free(c);
    }
    if (agdc) {
        strixAgdcDown(agdc);
        agdc = nullptr;
    }
    IOGraphicsAccelerator2::stop(provider);
}

void StrixAccelerator::free()
{
    if (machine) {
        machine->release();
        machine = nullptr;
    }
    if (stampMD) {
        stampMD->release();
        stampMD = nullptr;
    }
    IOGraphicsAccelerator2::free();
}

void StrixAccelerator::scan(const char *why)
{
    if (stopping || !machine) return;
    IOService *p = getProvider();
    if (!p) return;
    OSIterator *it = p->getChildIterator(gIOServicePlane);
    if (!it) return;
    unsigned seen = 0;
    while (OSObject *o = it->getNextObject()) {
        IOFramebuffer *fb = OSDynamicCast(IOFramebuffer, o);
        if (!fb) continue;
        ++seen;
        uintptr_t r = machine->found_framebuffer(fb);
        SLOG("scan(%s): framebuffer %p -> found_framebuffer %lu", why, fb, (unsigned long)(r & 0xff));
    }
    it->release();
    if (seen) publishCounters();
}

void StrixAccelerator::scanTick(thread_call_param_t self, thread_call_param_t)
{
    auto a = static_cast<StrixAccelerator *>(self);
    if (!a || a->stopping) return;
    OSIncrementAtomic(&a->inTick);
    int32_t n = OSIncrementAtomic(&a->scanTicks);
    if (!a->stopping && !a->agdc && a->getProvider()) {
        a->agdc = strixAgdcUp(a->getProvider());
    }
    if (!a->stopping) {
        a->scan("poll");
        a->publishCounters();
        thread_call_t c = a->scanCall;
        if (n < 240 && c && !a->stopping) {
            uint64_t dl;
            clock_interval_to_deadline(gCounters[kCPipes] ? 2000 : 500, NSEC_PER_MSEC, &dl);
            thread_call_enter_delayed(c, dl);
        }
    }
    OSDecrementAtomic(&a->inTick);
}

bool StrixAccelerator::onFramebuffer(void *target, void *, IOService *svc, IONotifier *)
{
    auto a = static_cast<StrixAccelerator *>(target);
    if (!a || a->stopping || !OSDynamicCast(IOFramebuffer, svc)) return true;
    if (svc->getProvider() != a->getProvider()) return true;
    SLOG("framebuffer %p published", svc);
    if (a->scanCall) thread_call_enter(a->scanCall);   // never create the pipe on the registry thread
    return true;
}

IOReturn StrixAccelerator::setProperties(OSObject *props)
{
    // Live tunables: `strix_accel_tune Mode=1 Async=1 SrcCache=0 Block=128 Probe=1 Reset=1`.  Local development machine,
    // so no privilege gate; every value is clamped.
    OSDictionary *d = OSDynamicCast(OSDictionary, props);
    if (!d) return IOGraphicsAccelerator2::setProperties(props);
    auto num = [&](const char *key, int32_t lo, int32_t hi, volatile int32_t *dst) -> bool {
        OSNumber *v = OSDynamicCast(OSNumber, d->getObject(key));
        if (!v) return false;
        int64_t x = int64_t(v->unsigned64BitValue());
        if (x < lo) x = lo;
        if (x > hi) x = hi;
        *dst = int32_t(x);
        return true;
    };
    num("StrixAccel,Mode", 0, 1, &gTuneMode);
    num("StrixAccel,Async", 0, 1, &gTuneAsync);
    num("StrixAccel,Probe", 0, 1, &gTuneProbe);
    num("StrixAccel,Block", 32, 4096, &gTuneBlock);
    volatile int32_t cm = gTuneSrcCache;
    if (num("StrixAccel,SrcCache", 0, 4, &cm) && cm != gTuneSrcCache) {
        gTuneSrcCache = cm;
        OSIncrementAtomic(&gCacheGen);
    }
    OSNumber *r = OSDynamicCast(OSNumber, d->getObject("StrixAccel,Reset"));
    if (r && r->unsigned64BitValue()) {
        gCopyNs = gCopyMaxNs = gWrittenBytes = gCopyCalls = gFullFrames = gCopyBlocks = 0;
        gCmpNs = gWriteNs = gFullNs = 0;
        gSubmitNs = gSubmitMaxNs = gSubmitCalls = 0;
        gCoalesced = 0;
    }
    SLOG("tune: mode=%d async=%d srccache=%d block=%d", (int)gTuneMode, (int)gTuneAsync, (int)gTuneSrcCache, (int)gTuneBlock);
    publishCounters();
    return kIOReturnSuccess;
}

void StrixAccelerator::publishCounters()
{
    setProperty("StrixAccel,Pipes", (unsigned long long)gCounters[kCPipes], 32);
    setProperty("StrixAccel,Transactions", (unsigned long long)gCounters[kCTxn], 32);
    setProperty("StrixAccel,Copied", (unsigned long long)gCounters[kCCopied], 32);
    setProperty("StrixAccel,Skipped", (unsigned long long)gCounters[kCSkipped], 32);
    setProperty("StrixAccel,Begin", (unsigned long long)gCounters[kCBegin], 32);
    setProperty("StrixAccel,ValidateFail", (unsigned long long)gCounters[kCValidateFail], 32);
    setProperty("StrixAccel,Tiled", (unsigned long long)gCounters[kCTiled], 32);
    setProperty("StrixAccel,UnsupportedFormat", (unsigned long long)gCounters[kCFormat], 32);
    setProperty("StrixAccel,NoPlane", (unsigned long long)gCounters[kCNoPlane], 32);
    setProperty("StrixAccel,Tune,Mode", (unsigned long long)gTuneMode, 32);
    setProperty("StrixAccel,Tune,Async", (unsigned long long)gTuneAsync, 32);
    setProperty("StrixAccel,Tune,SrcCache", (unsigned long long)gTuneSrcCache, 32);
    setProperty("StrixAccel,Tune,Block", (unsigned long long)gTuneBlock, 32);
    if (gCopyCalls) {
        setProperty("StrixAccel,Copy,AvgUs", (unsigned long long)(uint64_t(gCopyNs) / 1000 / uint64_t(gCopyCalls)), 32);
        setProperty("StrixAccel,Copy,MaxUs", (unsigned long long)(uint64_t(gCopyMaxNs) / 1000), 32);
        setProperty("StrixAccel,Copy,AvgKB", (unsigned long long)(uint64_t(gWrittenBytes) / 1024 / uint64_t(gCopyCalls)), 32);
        setProperty("StrixAccel,Copy,Frames", (unsigned long long)gCopyCalls, 32);
        setProperty("StrixAccel,Present,SubmitUsAvg", (unsigned long long)(gSubmitCalls ? uint64_t(gSubmitNs) / 1000 / uint64_t(gSubmitCalls) : 0), 32);
        setProperty("StrixAccel,Present,SubmitUsMax", (unsigned long long)(uint64_t(gSubmitMaxNs) / 1000), 32);
        setProperty("StrixAccel,Present,Submits", (unsigned long long)gSubmitCalls, 32);
        setProperty("StrixAccel,Present,Coalesced", (unsigned long long)gCoalesced, 32);
        unsigned long long diffFrames = (unsigned long long)(gCopyCalls > gFullFrames ? gCopyCalls - gFullFrames : 1);
        setProperty("StrixAccel,Copy,DiffCompareUsAvg", (unsigned long long)(uint64_t(gCmpNs) / 1000 / diffFrames), 32);
        setProperty("StrixAccel,Copy,DiffWriteUsAvg", (unsigned long long)(uint64_t(gWriteNs) / 1000 / diffFrames), 32);
        setProperty("StrixAccel,Copy,FullFrameUs", (unsigned long long)(uint64_t(gFullNs) / 1000), 32);
        setProperty("StrixAccel,Probe,SrcReadUs", (unsigned long long)(uint64_t(gProbeSrcNs) / 1000), 32);
        setProperty("StrixAccel,Probe,ShadowReadUs", (unsigned long long)(uint64_t(gProbeShNs) / 1000), 32);
        setProperty("StrixAccel,Probe,ApertureWriteUs", (unsigned long long)(uint64_t(gProbeWcNs) / 1000), 32);
        setProperty("StrixAccel,Copy,FullFrames", (unsigned long long)gFullFrames, 32);
    }
    setProperty("StrixAccel,AGDC,Up", agdc != nullptr);
    setProperty("StrixAccel,AGDC,Commands", (unsigned long long)strix_agdc::gStats.commands, 32);
    setProperty("StrixAccel,AGDC,VendorInfo", (unsigned long long)strix_agdc::gStats.vendorInfo, 32);
    setProperty("StrixAccel,AGDC,GpuCap", (unsigned long long)strix_agdc::gStats.gpuCap, 32);
    setProperty("StrixAccel,AGDC,LinkConfig", (unsigned long long)strix_agdc::gStats.linkConfig, 32);
    setProperty("StrixAccel,AGDC,FbCap", (unsigned long long)strix_agdc::gStats.fbCap, 32);
    setProperty("StrixAccel,AGDC,Refused", (unsigned long long)strix_agdc::gStats.refused, 32);
    setProperty("StrixAccel,AGDC,RefusedSeen", strix_agdc::gRefusedSeen);
    setProperty("StrixAccel,AGDC,ClientSet", (unsigned long long)strix_agdc::gStats.clientSet, 32);
    setProperty("StrixAccel,AGDC,ClientSetValue", (unsigned long long)(uint32_t)strix_agdc::gStats.lastClientSetValue, 32);
    setProperty("StrixAccel,AGDC,LinkIndex", (unsigned long long)(uint32_t)strix_agdc::gStats.lastLinkIndex, 32);
    setProperty("StrixAccel,AGDC,CapIndex", (unsigned long long)(uint32_t)strix_agdc::gStats.lastCapIndex, 32);
    setProperty("StrixAccel,AGDC,CapType", (unsigned long long)(uint32_t)strix_agdc::gStats.lastCapType, 32);
    setProperty("StrixAccel,AGDC,BadSize", (unsigned long long)strix_agdc::gStats.badSize, 32);
    setProperty("StrixAccel,AGDC,NoFramebuffer", (unsigned long long)strix_agdc::gStats.noFramebuffer, 32);
}

IOMemoryDescriptor *StrixAccelerator::getStampMemory(unsigned int *n)
{
    if (n) *n = 0;
    return stampMD;
}

IOAccelEventMachine2 *StrixAccelerator::newEventMachine()
{
    return OSTypeAlloc(StrixEventMachine);
}

IOAccelTask *StrixAccelerator::createUserGPUTask()
{
    StrixTask *t = OSTypeAlloc(StrixTask);
    if (t && !t->setup(this)) {
        t->release();
        t = nullptr;
    }
    return t;
}

IOAccelTask *StrixAccelerator::createKernelGPUTask()
{
    return createUserGPUTask();
}

void StrixAccelerator::populateAccelConfig(IOAccelConfig *cfg)
{
    // AppleParavirtAccelerator::populateAccelConfig values (the family's smallest known-good configuration):
    // 32 stamps, 8 displays, no GPU memory of our own.
    static const char name[] = "StrixAccel";
    uint8_t *c = reinterpret_cast<uint8_t *>(cfg);
    *reinterpret_cast<const char **>(c + 0x00) = name;
    *reinterpret_cast<uint32_t *>(c + 0x08) = 0x480000;
    *reinterpret_cast<uint32_t *>(c + 0x0c) = 7;
    *reinterpret_cast<uint32_t *>(c + 0x10) = 0;
    *reinterpret_cast<uint32_t *>(c + 0x14) = 0;
    *reinterpret_cast<uint32_t *>(c + 0x18) = 0x20;
    *reinterpret_cast<uint64_t *>(c + 0x20) = 0x40000000;
    *reinterpret_cast<uint32_t *>(c + 0x28) = 8;
    *reinterpret_cast<uint32_t *>(c + 0x2c) = 0x1000;
    *reinterpret_cast<uint32_t *>(c + 0x30) = 0x40004000;
    *reinterpret_cast<uint8_t *>(c + 0x47) = 1;
    *reinterpret_cast<uint32_t *>(c + 0x5c) = 4;
    *reinterpret_cast<uint32_t *>(c + 0x64) = 2;
    *reinterpret_cast<uint32_t *>(c + 0x68) = 0xa;
    *reinterpret_cast<uint32_t *>(c + 0x6c) = 1;
    *reinterpret_cast<uint64_t *>(c + 0x88) = 0;
    SLOG("populateAccelConfig");
}

bool StrixAccelerator::configureDevice(IOPCIDevice *dev)
{
    pci = dev;
    SLOG("configureDevice (no hardware access)");
    return true;
}

void StrixAccelerator::teardownDevice(IOPCIDevice *)
{
    SLOG("teardownDevice");
    pci = nullptr;
}

IOReturn StrixAccelerator::queryNativeInfo(s89n_info *info)
{
    if (!info || stopping || isInactive()) return kIOReturnNotReady;
    auto device = OSDynamicCast(IOPCIDevice, getProvider());
    if (!device || device->configRead32(0) != 0x150e1002) return kIOReturnNotReady;
    bzero(info, sizeof(*info));
    info->magic = S89N_MAGIC; info->major = S89N_ABI_MAJOR; info->minor = S89N_ABI_MINOR;
    info->size = sizeof(*info);
    info->capabilities = S89N_CAP_FOUNDATION_READ | (gCounters[kCPipes] ? S89N_CAP_DISPLAY_PIPE : 0);
    info->accelerator_registry_id = getRegistryEntryID(); info->pci_registry_id = device->getRegistryEntryID();
    info->vendor_device = device->configRead32(0); info->revision_class = device->configRead32(8);
    info->subsystem = device->configRead32(0x2c);
    info->readiness = S89N_READY_DISPLAY_ONLY; info->backend = S89N_BACKEND_NONE;
    // Expected target from Linux captures; discovered IP remains0 until read on macOS.
    info->expected_gc_ip = 0x000b0500;
    strlcpy(info->os_build, STRIXABI_OS_BUILD, sizeof(info->os_build));
    return kIOReturnSuccess;
}

IOReturn StrixAccelerator::readFoundation(s89n_foundation *info)
{
    if (!info || stopping || isInactive()) return kIOReturnNotReady;
    auto device = OSDynamicCast(IOPCIDevice, getProvider());
    if (!device || device->configRead32(0) != 0x150e1002) return kIOReturnNotReady;
    if (!(device->configRead32(4) & 2)) return kIOReturnNotReady; // Never enable memory decoding ourselves.
    // Linux amdgpu_discovery.c: fixed bootstrap registers, consistent across SOCs.
    // No arbitrary offsets, indirect MM_INDEX transport, mailbox writes or waits.
    constexpr unsigned offsets[] = {0xde3 * 4, 0x16a00 * 4, 0x16061 * 4};
    auto resources = OSDynamicCast(OSArray, device->getProperty("IODeviceMemory"));
    if (!resources) return kIOReturnNotReady;
    for (unsigned i = 0; i < resources->getCount(); ++i) {
        auto memory = OSDynamicCast(IOMemoryDescriptor, resources->getObject(i));
        if (!memory || (memory->getTag() & 255) != 0x24) continue;
        uint32_t bar = device->configRead32(0x24);
        if ((bar & 1) || (bar & 6) || memory->getLength() < offsets[1] + sizeof(uint32_t))
            return kIOReturnBadArgument;
        IOByteCount segment = 0;
        if (memory->getPhysicalSegment(0, &segment, kIOMemoryMapperNone) != (bar & ~15u) ||
            segment < memory->getLength()) return kIOReturnBadArgument;
        auto map = memory->map(kIOMapInhibitCache | kIOMapReadOnly);
        if (!map) return kIOReturnNoMemory;
        auto bytes = reinterpret_cast<volatile uint8_t *>(map->getVirtualAddress());
        if (!bytes) { map->release(); return kIOReturnNoMemory; }
        bzero(info, sizeof(*info)); info->magic = S89N_MAGIC; info->size = sizeof(*info);
        info->rcc_memsize_mib = *reinterpret_cast<volatile uint32_t *>(bytes + offsets[0]);
        info->ip_discovery_version = *reinterpret_cast<volatile uint32_t *>(bytes + offsets[1]);
        info->psp_discovery_status = *reinterpret_cast<volatile uint32_t *>(bytes + offsets[2]);
        map->release();
        return info->rcc_memsize_mib == 0xffffffff ? kIOReturnNotReady : kIOReturnSuccess;
    }
    return kIOReturnNotFound;
}

IOReturn StrixAccelerator::newUserClient(task_t task, void *securityID, unsigned int type, IOUserClient **handler)
{
    if (type != S89N_UC_TYPE) return IOGraphicsAccelerator2::newUserClient(task, securityID, type, handler);
    if (!handler) return kIOReturnBadArgument;
    *handler = nullptr;
    if (stopping || isInactive()) return kIOReturnNotReady;
    auto client = OSTypeAlloc(StrixNativeClient);
    if (!client) return kIOReturnNoMemory;
    if (!client->initWithTask(task, securityID, type)) {
        client->release(); return kIOReturnNoResources;
    }
    // Serialize Hello/Query/close through the kernel user-client IPC lock.
    client->setProperty("IOUserClientDefaultLocking", true);
    client->setProperty("IOUserClientDefaultLockingSetProperties", true);
    client->setProperty("IOUserClientDefaultLockingSingleThreadExternalMethod", true);
    if (!client->attach(this)) {
        client->release(); return kIOReturnNoResources;
    }
    if (!client->start(this)) {
        client->detach(this); client->release(); return kIOReturnNoResources;
    }
    *handler = client;
    return kIOReturnSuccess;
}

IOReturn StrixNativeClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                         IOExternalMethodDispatch *, OSObject *, void *)
{
    static const IOExternalMethodDispatch methods[] = {
        {hello, 0, sizeof(s89n_hello_request), 0, sizeof(s89n_hello_reply)},
        {query, 0, 0, 0, sizeof(s89n_info)},
        {foundation, 0, 0, 0, sizeof(s89n_foundation)}
    };
    if (!args || selector >= S89N_SELECTOR_COUNT || isInactive()) return kIOReturnUnsupported;
    return IOUserClient::externalMethod(selector, args,
        const_cast<IOExternalMethodDispatch *>(&methods[selector]), this, nullptr);
}

IOReturn StrixNativeClient::hello(OSObject *target, void *, IOExternalMethodArguments *args)
{
    auto client = OSDynamicCast(StrixNativeClient, target);
    if (!client || !args->structureInput || !args->structureOutput) return kIOReturnBadArgument;
    client->negotiated = false;
    const auto request = static_cast<const s89n_hello_request *>(args->structureInput);
    if (request->reserved[0] || request->reserved[1]) return kIOReturnBadArgument;
    if (request->major != S89N_ABI_MAJOR || request->minor > S89N_ABI_MINOR) return kIOReturnUnsupported;
    auto provider = OSDynamicCast(StrixAccelerator, client->getProvider());
    s89n_info info {};
    IOReturn result = provider ? provider->queryNativeInfo(&info) : kIOReturnNotReady;
    if (result != kIOReturnSuccess) return result;
    auto reply = static_cast<s89n_hello_reply *>(args->structureOutput);
    bzero(reply, sizeof(*reply));
    reply->magic = S89N_MAGIC; reply->major = S89N_ABI_MAJOR; reply->minor = S89N_ABI_MINOR;
    reply->size = sizeof(*reply); reply->capabilities = info.capabilities;
    client->negotiated = true; return kIOReturnSuccess;
}

IOReturn StrixNativeClient::query(OSObject *target, void *, IOExternalMethodArguments *args)
{
    auto client = OSDynamicCast(StrixNativeClient, target);
    if (!client || !args->structureOutput) return kIOReturnBadArgument;
    if (!client->negotiated) return kIOReturnNotReady;
    auto provider = OSDynamicCast(StrixAccelerator, client->getProvider());
    return provider ? provider->queryNativeInfo(static_cast<s89n_info *>(args->structureOutput)) : kIOReturnNotReady;
}

IOReturn StrixNativeClient::foundation(OSObject *target, void *, IOExternalMethodArguments *args)
{
    auto client = OSDynamicCast(StrixNativeClient, target);
    if (!client || !args->structureOutput) return kIOReturnBadArgument;
    if (!client->negotiated) return kIOReturnNotReady;
    if (IOUserClient::clientHasPrivilege(current_task(), kIOClientPrivilegeAdministrator) != kIOReturnSuccess)
        return kIOReturnNotPrivileged;
    auto provider = OSDynamicCast(StrixAccelerator, client->getProvider());
    return provider ? provider->readFoundation(static_cast<s89n_foundation *>(args->structureOutput)) : kIOReturnNotReady;
}

IOAccelDisplayMachine *StrixAccelerator::newDisplayMachine()
{
    StrixDisplayMachine *m = OSTypeAlloc(StrixDisplayMachine);
    if (m) {
        m->retain();
        if (machine) machine->release();
        machine = m;
    }
    SLOG("newDisplayMachine %p", m);
    return m;
}

uintptr_t StrixAccelerator::newGLContext() { return 0; }
uintptr_t StrixAccelerator::newCLContext() { return 0; }
uintptr_t StrixAccelerator::newSurface() { return 0; }
uintptr_t StrixAccelerator::new2DContext() { return 0; }
uintptr_t StrixAccelerator::newVideoContext() { return 0; }

IOAccelDisplayPipe *StrixAccelerator::newDisplayPipe()
{
    StrixDisplayPipe *p = OSTypeAlloc(StrixDisplayPipe);
    SLOG("newDisplayPipe %p", p);
    return p;
}

IOAccelSysMemory *StrixAccelerator::newSysMemory() { return OSTypeAlloc(StrixSysMemory); }
uintptr_t StrixAccelerator::newVidMemory() { return reinterpret_cast<uintptr_t>(OSTypeAlloc(StrixVidMemory)); }
uintptr_t StrixAccelerator::newResource() { return reinterpret_cast<uintptr_t>(OSTypeAlloc(StrixResource)); }
uintptr_t StrixAccelerator::newMemoryMap() { return reinterpret_cast<uintptr_t>(OSTypeAlloc(StrixMemoryMap)); }

// ---------------------------------------------------------------------------------------------------------------------
// event machine: stamps live in plain memory, nothing ever increments them
// ---------------------------------------------------------------------------------------------------------------------
bool StrixEventMachine::init(IOGraphicsAccelerator2 *accel, unsigned int n, int timeout)
{
    bool ok = IOAccelEventMachineFast2::init(accel, n, timeout);   // first: the family sets up its own state
    StrixAccelerator *a = OSDynamicCast(StrixAccelerator, accel);
    if (ok && a && a->stampVA) setStampBaseAddress(a->stampVA);
    SLOG("eventMachine init(n=%u timeout=%d) -> %d", n, timeout, ok);
    return ok && a && a->stampVA;
}
void StrixEventMachine::writeStamp(int, vendevtCommandRec *, unsigned int) {}
void StrixEventMachine::prepareBarrier(vendevtBarrierRec *) {}
bool StrixEventMachine::completeBarrier(vendevtBarrierRec *) { return true; }
void StrixEventMachine::writeBarrierElement(vendevtBarrierRec *, int, unsigned int) {}

// ---------------------------------------------------------------------------------------------------------------------
// task: only an address-space bookkeeping object (AppleParavirtTask recipe)
// ---------------------------------------------------------------------------------------------------------------------
bool StrixTask::setup(IOGraphicsAccelerator2 *accel)
{
    IORangeAllocator *ra = IORangeAllocator::withRange(0x400000000ULL - 1, 0x1000, 0x400, 0);
    if (!ra) return false;
    if (!ra->allocateRange(0, 0x1000)) {   // page 0 stays reserved
        ra->release();
        return false;
    }
    bool ok = strix_IOAccelTask_init(this, accel, 1, &ra);
    if (ra) ra->release();
    SLOG("task init -> %d", ok);
    return ok;
}

// ---------------------------------------------------------------------------------------------------------------------
// display machine
// ---------------------------------------------------------------------------------------------------------------------
bool StrixDisplayMachine::displayModeWillChange()
{
    SLOG("displayModeWillChange");
    return true;
}
bool StrixDisplayMachine::displayModeDidChange()
{
    SLOG("displayModeDidChange");
    return true;
}
uintptr_t StrixDisplayMachine::found_framebuffer(IOFramebuffer *fb)
{
    uintptr_t r = IOAccelDisplayMachine::found_framebuffer(fb);
    SLOG("found_framebuffer(%p) -> %lu", fb, (unsigned long)(r & 0xff));
    return r;
}

// ---------------------------------------------------------------------------------------------------------------------
// memory / resource / map objects: real family classes, no GPU behind them
// ---------------------------------------------------------------------------------------------------------------------
uint64_t StrixVidMemory::getPhysicalSegment(unsigned long long, unsigned long long *) { return 0; }
uintptr_t StrixVidMemory::allocPhysical() { return 0; }
uintptr_t StrixVidMemory::deallocPhysical() { return 0; }

uintptr_t StrixResource::rebuildPagingBuffer() { return 0; }
uintptr_t StrixResource::getLevelOffset(unsigned char, unsigned char, int *off)
{
    if (off) *off = 0;
    return 0;
}
uintptr_t StrixResource::getBackingLevelOffset(unsigned char, unsigned char, int *off)
{
    if (off) *off = 0;
    return 0;
}
uintptr_t StrixResource::calculateIOSurfaceDeviceCacheVRAMBytes(unsigned long long *a, unsigned long long *b)
{
    if (a) *a = 0;
    if (b) *b = 0;
    return 0;
}
uintptr_t StrixResource::addToAperture() { return 0; }
uintptr_t StrixResource::removeFromAperture() { return 0; }
uintptr_t StrixResource::getApertureMemoryDescriptor(unsigned long long *) { return 0; }

uintptr_t StrixMemoryMap::commitIntoGPUPageTable() { return 1; }
uintptr_t StrixMemoryMap::releaseFromGPUPageTable() { return 1; }
uintptr_t StrixMemoryMap::updateGPUPageTable() { return 1; }

// ---------------------------------------------------------------------------------------------------------------------
// display pipe
// ---------------------------------------------------------------------------------------------------------------------
static inline uint32_t fourcc(char a, char b, char c, char d)
{
    return (uint32_t(uint8_t(a)) << 24) | (uint32_t(uint8_t(b)) << 16) | (uint32_t(uint8_t(c)) << 8) | uint8_t(d);
}

bool StrixDisplayPipe::init(IOGraphicsAccelerator2 *accel, IOAccelDisplayMachine *m, IOFramebuffer *fb, unsigned int index)
{
    bool ok = IOAccelDisplayPipe::init(accel, m, fb, index);
    owner = OSDynamicCast(StrixAccelerator, accel);
    lock = IOLockAlloc();
    qlock = IOLockAlloc();
    worker = thread_call_allocate(&StrixDisplayPipe::workerFire, this);
    cacheGen = gCacheGen;
    SLOG("pipe init(fb=%p index=%u) -> %d", fb, index, ok);
    if (ok && lock) OSIncrementAtomic(&gCounters[kCPipes]);
    return ok && lock && qlock && worker;
}

void StrixDisplayPipe::free()
{
    OSIncrementAtomic(&closing);
    if (worker) {
        thread_call_cancel(worker);
        IOSleep(5);
        while (workerBusy) IOSleep(5);
        thread_call_free(worker);
        worker = nullptr;
    }
    if (pending) {
        strix_surf_release(pending);
        pending = nullptr;
    }
    if (qlock) {
        IOLockFree(qlock);
        qlock = nullptr;
    }
    if (shadowMD) {
        shadowMD->release();
        shadowMD = nullptr;
        shadow = nullptr;
    }
    for (auto &c : cache) {
        if (c.map) c.map->release();
        if (c.md) {
            if (c.prepared) c.md->complete();
            c.md->release();
        }
        c = SurfMap{};
    }
    if (fbMap) {
        fbMap->release();
        fbMap = nullptr;
    }
    if (fbMemory) {
        fbMemory->release();
        fbMemory = nullptr;
    }
    if (lock) {
        IOLockFree(lock);
        lock = nullptr;
    }
    IOAccelDisplayPipe::free();
}

uintptr_t StrixDisplayPipe::initFramebufferResource(unsigned int index, IOAccelResource2 *res)
{
    shadowValid = false;   // a mode change may have repainted or moved the raster
    // AppleParavirtDisplayPipe::initFramebufferResource: wrap the framebuffer's own memory in an IOAccelSysMemory
    IOFramebuffer *fb = strix_pipe_getFramebuffer(this);
    IODeviceMemory *md = fb ? fb->getApertureRange(kIOFBSystemAperture) : nullptr;   // one reference for us
    IOAccelSysMemory *mem = nullptr;
    if (md && owner) mem = strix_withMemoryDescriptor(owner, res, md);
    SLOG("pipe initFramebufferResource(index=%u res=%p) fb=%p md=%p -> %p", index, res, fb, md, mem);
    if (md) md->release();
    return reinterpret_cast<uintptr_t>(mem);
}

bool StrixDisplayPipe::prepareFramebuffer()
{
    if (fbReady) return true;
    IOFramebuffer *fb = strix_pipe_getFramebuffer(this);
    if (!fb) return false;
    IODisplayModeID mode = 0;
    IOIndex depth = 0;
    IOPixelInformation pi;
    bzero(&pi, sizeof(pi));
    if (fb->getCurrentDisplayMode(&mode, &depth) != kIOReturnSuccess ||
        fb->getPixelInformation(mode, depth, kIOFBSystemAperture, &pi) != kIOReturnSuccess) {
        SLOG("prepareFramebuffer: mode/pixel query failed");
        return false;
    }
    fbMemory = fb->getApertureRange(kIOFBSystemAperture);
    if (!fbMemory) {
        SLOG("prepareFramebuffer: no aperture");
        return false;
    }
    fbMap = fbMemory->map(kIOMapWriteCombineCache);
    if (!fbMap || !fbMap->getVirtualAddress()) {
        SLOG("prepareFramebuffer: aperture map failed");
        return false;
    }
    fbWidth = pi.activeWidth;
    fbHeight = pi.activeHeight;
    fbStride = pi.bytesPerRow;
    fbReady = true;
    SLOG("prepareFramebuffer: %ux%u stride %u at %p (mode %u depth %d bpp %u)", fbWidth, fbHeight, fbStride,
         (void *)fbMap->getVirtualAddress(), (unsigned)mode, (int)depth, (unsigned)pi.bitsPerPixel);
    if (owner) {
        owner->setProperty("StrixAccel,Raster,Width", fbWidth, 32);
        owner->setProperty("StrixAccel,Raster,Height", fbHeight, 32);
        owner->setProperty("StrixAccel,Raster,Stride", fbStride, 32);
    }
    return true;
}

uint8_t *StrixDisplayPipe::mapSurface(IOSurface *s, uint32_t id)
{
    if (cacheGen != gCacheGen) {   // the source cache mode changed: drop every mapping, remap on demand
        cacheGen = gCacheGen;
        for (auto &c : cache) {
            if (c.map) c.map->release();
            if (c.md) {
                if (c.prepared) c.md->complete();
                c.md->release();
            }
            c = SurfMap{};
        }
    }
    ++tick;
    SurfMap *victim = &cache[0];
    for (auto &c : cache) {
        if (c.surface == s && c.id == id && c.map) {
            c.used = tick;
            return reinterpret_cast<uint8_t *>(c.map->getVirtualAddress());
        }
        if (c.used < victim->used) victim = &c;
    }
    IOMemoryDescriptor *md = strix_surf_getMemoryDescriptor(s);
    if (!md) return nullptr;
    if (victim->map) victim->map->release();
    if (victim->md) {
        if (victim->prepared) victim->md->complete();
        victim->md->release();
    }
    *victim = SurfMap{};
    md->retain();
    bool prepared = md->prepare() == kIOReturnSuccess;
    IOOptionBits co = 0;
    switch (gTuneSrcCache) {
    case 1: co = kIOMapCopybackCache; break;
    case 2: co = kIOMapWriteThruCache; break;
    default: break;   // 0 default, 3/4 aliased to default (see above)
    }
    IOMemoryMap *map = md->map(kIOMapAnywhere | kIOMapReadOnly | co);
    if (!map && co) map = md->map(kIOMapAnywhere | kIOMapReadOnly);   // that cache mode is not allowed for this memory
    if (!map) {
        if (prepared) md->complete();
        md->release();
        return nullptr;
    }
    victim->surface = s;
    victim->id = id;
    victim->md = md;
    victim->map = map;
    victim->prepared = prepared;
    victim->used = tick;
    return reinterpret_cast<uint8_t *>(map->getVirtualAddress());
}

// bcmp in xnu is a "repe cmps" loop; a plain 64-bit OR-of-XOR loop is several times faster on the 20 MB per frame.
static inline bool strix_equal(const uint8_t *a, const uint8_t *b, size_t n)
{
    const uint64_t *x = reinterpret_cast<const uint64_t *>(a), *y = reinterpret_cast<const uint64_t *>(b);
    uint64_t acc = 0;
    size_t q = n / 8;
    while (q >= 8) {
        acc |= (x[0] ^ y[0]) | (x[1] ^ y[1]) | (x[2] ^ y[2]) | (x[3] ^ y[3]) |
               (x[4] ^ y[4]) | (x[5] ^ y[5]) | (x[6] ^ y[6]) | (x[7] ^ y[7]);
        x += 8; y += 8; q -= 8;
    }
    while (q--) acc |= *x++ ^ *y++;
    for (size_t i = n & ~size_t(7); i < n; ++i) acc |= uint64_t(a[i] ^ b[i]);
    return acc == 0;
}

static inline uint64_t strix_ns(uint64_t t0)
{
    uint64_t ns = 0;
    absolutetime_to_nanoseconds(mach_absolute_time() - t0, &ns);
    return ns;
}

uint8_t *StrixDisplayPipe::ensureShadow()
{
    if (shadow) return shadow;
    const size_t bytes = size_t(fbWidth) * fbHeight * 4 + size_t(fbWidth) * 4;
    shadowMD = IOBufferMemoryDescriptor::inTaskWithOptions(kernel_task, kIODirectionInOut, bytes, PAGE_SIZE);
    if (!shadowMD) return nullptr;
    shadow = static_cast<uint8_t *>(shadowMD->getBytesNoCopy());
    if (!shadow) {
        shadowMD->release();
        shadowMD = nullptr;
        return nullptr;
    }
    shadowValid = false;
    return shadow;
}

bool StrixDisplayPipe::copySurface(IOSurface *s, unsigned n)
{
    if (!prepareFramebuffer()) return false;
    const uint32_t id = strix_surf_getSurfaceID(s);
    const uint32_t w = strix_surf_getWidth(s), h = strix_surf_getHeight(s);
    const uint32_t bpr = strix_surf_getBytesPerRow(s);
    const uint32_t fmt = strix_surf_getPixelFormat(s);
    const uint32_t bpe = strix_surf_getBytesPerElement(s);
    const uint32_t off = strix_surf_getPlaneOffset(s, 0);
    const bool tiled = strix_surf_isTiled(s);
    if (n < 16 || (n % 600) == 0)
        SLOG("txn %u: surface %u %ux%u bpr %u fmt '%c%c%c%c' (0x%x) bpe %u off %u tiled %d -> raster %ux%u stride %u", n,
             id, w, h, bpr, char(fmt >> 24), char(fmt >> 16), char(fmt >> 8), char(fmt), fmt, bpe, off, tiled, fbWidth,
             fbHeight, fbStride);
    if (tiled) {
        OSIncrementAtomic(&gCounters[kCTiled]);
        return false;
    }
    const bool plain = fmt == fourcc('B', 'G', 'R', 'A') || (fmt == 0 && bpe == 4);
    const bool l10r = fmt == fourcc('l', '1', '0', 'r');
    if (!plain && !l10r) {
        OSIncrementAtomic(&gCounters[kCFormat]);
        return false;
    }
    if (!w || !h || bpr < w * 4) return false;
    uint8_t *src = mapSurface(s, id);
    if (!src) return false;
    src += off;
    uint8_t *dst = reinterpret_cast<uint8_t *>(fbMap->getVirtualAddress());
    const uint32_t cols = w < fbWidth ? w : fbWidth;
    const uint32_t rows = h < fbHeight ? h : fbHeight;
    const size_t rowBytes = size_t(cols) * 4;
    const size_t kBlock = size_t(gTuneBlock < 32 ? 32 : (gTuneBlock > 4096 ? 4096 : (gTuneBlock & ~7)));
    uint8_t *sh = ensureShadow();
    uint32_t *rowTmp = sh ? reinterpret_cast<uint32_t *>(sh + size_t(fbWidth) * fbHeight * 4) : nullptr;
    if (!plain && !rowTmp) return false;   // l10r needs a scratch row
    bool full = gTuneMode == 0 || !shadowValid || !sh || ++sinceFull >= 1800;   // a periodic full refresh also heals anything else that wrote the aperture
    if (full) sinceFull = 0;
    const uint64_t t0 = mach_absolute_time();
    uint64_t written = 0, blocks = 0, writeNs = 0;
    if (gTuneProbe) {   // on-demand bandwidth probe: where is the time going?
        gTuneProbe = 0;
        uint64_t sum = 0, p0 = mach_absolute_time();
        for (uint32_t y = 0; y < rows; ++y) {
            const uint64_t *q = reinterpret_cast<const uint64_t *>(src + uint64_t(y) * bpr);
            for (uint32_t i = 0; i < cols / 2; i += 8) sum += q[i] + q[i + 1] + q[i + 2] + q[i + 3];
        }
        gProbeSrcNs = int64_t(strix_ns(p0));
        if (sh) {
            p0 = mach_absolute_time();
            for (uint32_t y = 0; y < rows; ++y) {
                const uint64_t *q = reinterpret_cast<const uint64_t *>(sh + size_t(y) * fbWidth * 4);
                for (uint32_t i = 0; i < cols / 2; i += 8) sum += q[i] + q[i + 1] + q[i + 2] + q[i + 3];
            }
            gProbeShNs = int64_t(strix_ns(p0));
        }
        gProbeWcNs = int64_t(sum & 1);   // keeps the reads alive
        if (plain) {                     // write the same rows back (identical pixels): time the aperture write alone
            p0 = mach_absolute_time();
            for (uint32_t y = 0; y < rows; ++y)
                bcopy(src + uint64_t(y) * bpr, dst + uint64_t(y) * fbStride, size_t(cols) * 4);
            __asm__ volatile("sfence" ::: "memory");
            gProbeWcNs = int64_t(strix_ns(p0));
        }
    }
    for (uint32_t y = 0; y < rows; ++y) {
        const uint8_t *sp = src + uint64_t(y) * bpr;
        uint8_t *dp = dst + uint64_t(y) * fbStride;
        uint8_t *shp = sh ? sh + size_t(y) * fbWidth * 4 : nullptr;
        if (!plain) {
            const uint32_t *s32 = reinterpret_cast<const uint32_t *>(sp);
            for (uint32_t x = 0; x < cols; ++x) {
                uint32_t v = s32[x];
                rowTmp[x] = 0xff000000u | (((v >> 22) & 0xff) << 16) | (((v >> 12) & 0xff) << 8) | ((v >> 2) & 0xff);
            }
            sp = reinterpret_cast<const uint8_t *>(rowTmp);
        }
        if (full) {
            bcopy(sp, dp, rowBytes);
            if (shp) bcopy(sp, shp, rowBytes);
            written += rowBytes;
            continue;
        }
        size_t x = 0;
        while (x < rowBytes) {
            size_t blk = rowBytes - x < kBlock ? rowBytes - x : kBlock;
            if (strix_equal(sp + x, shp + x, blk)) {
                x += blk;
                continue;
            }
            const size_t start = x;
            x += blk;
            while (x < rowBytes) {          // extend the run to the next unchanged block
                blk = rowBytes - x < kBlock ? rowBytes - x : kBlock;
                if (strix_equal(sp + x, shp + x, blk)) break;
                x += blk;
            }
            const uint64_t w0 = mach_absolute_time();
            bcopy(sp + start, dp + start, x - start);
            bcopy(sp + start, shp + start, x - start);
            writeNs += strix_ns(w0);
            written += x - start;
            ++blocks;
        }
    }
    if (sh) shadowValid = true;
    __asm__ volatile("sfence" ::: "memory");   // flush the write-combining buffers
    uint64_t ns = 0;
    absolutetime_to_nanoseconds(mach_absolute_time() - t0, &ns);
    if (full) gFullNs = int64_t(ns); else { gWriteNs += int64_t(writeNs); gCmpNs += int64_t(ns - writeNs); }
    OSAddAtomic64(int64_t(ns), &gCopyNs);
    OSAddAtomic64(int64_t(written), &gWrittenBytes);
    OSAddAtomic64(1, &gCopyCalls);
    OSAddAtomic64(int64_t(blocks), &gCopyBlocks);
    if (full) OSAddAtomic64(1, &gFullFrames);
    if (int64_t(ns) > gCopyMaxNs) gCopyMaxNs = int64_t(ns);
    if (n <= 16 || (n % 240) == 0)
        SLOG("txn %u: copy %s %llu us, wrote %llu KB in %llu runs (avg %llu us / %llu KB over %lld frames)", n,
             full ? "FULL" : "diff", ns / 1000, written / 1024, blocks, uint64_t(gCopyNs) / 1000 / uint64_t(gCopyCalls),
             uint64_t(gWrittenBytes) / 1024 / uint64_t(gCopyCalls), (long long)gCopyCalls);
    return true;
}

// Raw views of the family's transaction/pipe plane state (IOAccelDisplayPipeTransaction2 +0x38 -> 2 planes of 0x70 bytes:
// +0x10 deviceCache[2], +0x20 IOSurface[2], +0x30 resource[2], +0x40 gamma, +0x48..0x78 geometry). Layout from
// IOAccelDisplayPipeTransaction2::set_transaction_args / getPlaneIOSurface (macOS 15 24H32, family 485.2); diagnostics only.
static const uint8_t *strix_txn_planes(const IOAccelDisplayPipeTransaction2 *t)
{
    return *reinterpret_cast<const uint8_t *const *>(reinterpret_cast<const uint8_t *>(t) + 0x38);
}

static void strix_dump_plane(const char *tag, unsigned n, unsigned p, const uint8_t *pl)
{
    if (!pl) return;
    const uint64_t *q = reinterpret_cast<const uint64_t *>(pl + p * 0x70);
    SLOG("txn %u %s plane%u: devCache %llx %llx surf %llx %llx res %llx %llx gamma %llx geom %llx %llx %llx %llx %llx %llx", n,
         tag, p, q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9], q[10], q[11], q[12], q[13], q[14]);
}

static IOSurface *strix_pick_surface(const IOAccelDisplayPipeTransaction2 *t)
{
    // plane 0 is the desktop; plane 1 only counts when it is a full-size surface (never a cursor/overlay)
    for (unsigned p = 0; p < 2; ++p) {
        for (unsigned i = 0; i < 2; ++i) {
            IOSurface *s = strix_txn_getPlaneIOSurface(t, p, i);
            if (!s) continue;
            if (strix_surf_getWidth(s) >= 1024 && strix_surf_getHeight(s) >= 600) return s;
        }
    }
    return nullptr;
}

static void strix_diag_txn(const IOAccelDisplayPipe *pipe, const IOAccelDisplayPipeTransaction2 *t, unsigned n, const char *what)
{
    const uint8_t *tb = reinterpret_cast<const uint8_t *>(t);
    SLOG("txn %u %s: flags %llx +50 %x +54 %x", n, what, *reinterpret_cast<const uint64_t *>(tb + 0x48),
         *reinterpret_cast<const uint32_t *>(tb + 0x50), *reinterpret_cast<const uint32_t *>(tb + 0x54));
    const uint8_t *tp = strix_txn_planes(t);
    for (unsigned p = 0; p < 2; ++p) strix_dump_plane("txn", n, p, tp);
    const uint8_t *pp = *reinterpret_cast<const uint8_t *const *>(reinterpret_cast<const uint8_t *>(pipe) + 0x240);
    for (unsigned p = 0; p < 2; ++p) strix_dump_plane("pipe", n, p, pp);
    for (unsigned p = 0; p < 2; ++p) {
        for (unsigned i = 0; i < 2; ++i) {
            IOSurface *s = strix_txn_getPlaneIOSurface(t, p, i);
            if (s)
                SLOG("txn %u plane%u[%u] surface %u %ux%u bpr %u fmt 0x%x bpe %u", n, p, i, strix_surf_getSurfaceID(s),
                     strix_surf_getWidth(s), strix_surf_getHeight(s), strix_surf_getBytesPerRow(s), strix_surf_getPixelFormat(s),
                     strix_surf_getBytesPerElement(s));
            const uint64_t *q = tp ? reinterpret_cast<const uint64_t *>(tp + p * 0x70) : nullptr;
            const OSObject *r = q ? reinterpret_cast<const OSObject *>(q[6 + i]) : nullptr;
            if (r) SLOG("txn %u plane%u[%u] resource class %s", n, p, i, r->getMetaClass()->getClassName());
        }
    }
}

static volatile int32_t gValidateSeen;

static inline uint64_t strix_txn_flags(const IOAccelDisplayPipeTransaction2 *t)
{
    return *reinterpret_cast<const uint64_t *>(reinterpret_cast<const uint8_t *>(t) + 0x48);   // bit p = plane p carried
}

// Only surfaces copySurface() can present are accepted; anything else fails the transaction so the caller keeps its CPU path.
static bool strix_surface_supported(IOSurface *s)
{
    const uint32_t fmt = strix_surf_getPixelFormat(s), bpe = strix_surf_getBytesPerElement(s);
    const bool plain = fmt == fourcc('B', 'G', 'R', 'A') || (fmt == 0 && bpe == 4);
    const bool l10r = fmt == fourcc('l', '1', '0', 'r');
    if (!plain && !l10r) return false;
    if (strix_surf_isTiled(s)) return false;
    return strix_surf_getBytesPerRow(s) >= strix_surf_getWidth(s) * 4;
}

uintptr_t StrixDisplayPipe::validateTransaction(IOAccelDisplayPipeTransaction2 *t)
{
    const unsigned v = unsigned(OSIncrementAtomic(&gValidateSeen)) + 1;
    if (!(strix_txn_flags(t) & 3)) {
        // pipe-level update only (gamma/CSC tables): nothing to present, nothing wrong
        if (v <= 4) strix_diag_txn(this, t, v, "validate-noplane");
        return 0;
    }
    IOSurface *s = strix_pick_surface(t);
    if (s && strix_surface_supported(s)) {
        if (v <= 4 || (v % 1200) == 0) strix_diag_txn(this, t, v, "validate-ok");
        return 0;
    }
    OSIncrementAtomic(&gCounters[kCValidateFail]);
    if (v <= 12 || (v % 600) == 0) strix_diag_txn(this, t, v, s ? "validate-FAIL-unsupported" : "validate-FAIL-nosurface");
    return 0xE00002BC;
}

bool StrixDisplayPipe::isTransactionComplete(IOAccelDisplayPipeTransaction2 *)
{
    return true;   // submitTransaction completes synchronously
}

void StrixDisplayPipe::presentPending()
{
    for (;;) {
        IOLockLock(qlock);
        IOSurface *s = pending;
        const unsigned n = pendingN;
        pending = nullptr;
        IOLockUnlock(qlock);
        if (!s) return;
        bool copied = false;
        IOLockLock(lock);
        copied = copySurface(s, n);
        IOLockUnlock(lock);
        strix_surf_release(s);
        OSIncrementAtomic(&gCounters[copied ? kCCopied : kCSkipped]);
        if (owner && (n <= 8 || (n % 120) == 0)) owner->publishCounters();
    }
}

void StrixDisplayPipe::workerFire(thread_call_param_t self, thread_call_param_t)
{
    auto p = static_cast<StrixDisplayPipe *>(self);
    OSIncrementAtomic(&p->workerBusy);
    if (!p->closing) p->presentPending();
    OSDecrementAtomic(&p->workerBusy);
}

IOReturn StrixDisplayPipe::submitTransaction(IOAccelDisplayPipeTransaction2 *t)
{
    const unsigned n = unsigned(OSIncrementAtomic(&gCounters[kCTxn])) + 1;
    if (!(strix_txn_flags(t) & 3)) {
        OSIncrementAtomic(&gCounters[kCNoPlane]);   // no plane changed: what is on screen is still current
        if (owner && n <= 8) owner->publishCounters();
        return kIOReturnSuccess;
    }
    const uint64_t t0 = mach_absolute_time();
    IOSurface *s = strix_pick_surface(t);
    if (s && gTuneAsync && worker && qlock && !closing) {
        // The caller is WindowServer: park the newest surface and return. A frame the worker has not started yet is
        // replaced (coalesced), so a slow copy can only drop frames, never queue them or stall the other display.
        reinterpret_cast<OSObject *>(s)->retain();
        IOLockLock(qlock);
        IOSurface *old = pending;
        pending = s;
        pendingN = n;
        IOLockUnlock(qlock);
        if (old) {
            strix_surf_release(old);
            OSIncrementAtomic(&gCoalesced);
        }
        thread_call_enter(worker);
    } else {
        bool copied = false;
        if (s && lock) {
            IOLockLock(lock);
            copied = copySurface(s, n);
            IOLockUnlock(lock);
        }
        OSIncrementAtomic(&gCounters[copied ? kCCopied : kCSkipped]);
        if (!s && n <= 8) strix_diag_txn(this, t, n, "submit-nosurface");
        if (owner && (n <= 8 || (n % 120) == 0)) owner->publishCounters();
    }
    const int64_t ns = int64_t(strix_ns(t0));
    OSAddAtomic64(ns, &gSubmitNs);
    OSAddAtomic64(1, &gSubmitCalls);
    if (ns > gSubmitMaxNs) gSubmitMaxNs = ns;
    return kIOReturnSuccess;
}

void StrixDisplayPipe::beginTransaction(IOAccelEvent *ev)
{
    // empty event: the family only needs it initialised, nothing will ever wait on a GPU stamp
    IOAccelEventMachine2 *em = strix_pipe_getEventMachine(this);
    OSIncrementAtomic(&gCounters[kCBegin]);
    if (em) {
        em->cleanEvent(ev);
        em->initEvent(ev);
    }
}
