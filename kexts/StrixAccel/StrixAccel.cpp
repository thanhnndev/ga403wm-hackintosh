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

#define STRIXACCEL_VERSION "0.1.0"

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

static volatile int32_t gGate;        // 0 unchecked, 1 pass, 2 fail (fail closed for the rest of the boot)
static volatile int32_t gCounters[8]; // 0 pipes, 1 txn, 2 copied, 3 skipped, 4 begin, 5 validate fail, 6 tiled, 7 unsupported fmt

enum { kCPipes, kCTxn, kCCopied, kCSkipped, kCBegin, kCValidateFail, kCTiled, kCFormat };

class StrixAccelerator;
class StrixDisplayMachine;

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
    thread_call_t scanCall;
    volatile int32_t stopping;
    volatile int32_t scanTicks;
    volatile int32_t inTick;          // thread_call_cancel_wait is private KPI: wait on this instead

    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;

    IOMemoryDescriptor *getStampMemory(unsigned int *n) override;
    IOAccelEventMachine2 *newEventMachine() override;
    IOAccelTask *createUserGPUTask() override;
    IOAccelTask *createKernelGPUTask() override;
    void populateAccelConfig(IOAccelConfig *cfg) override;
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
    static void scanTick(thread_call_param_t self, thread_call_param_t);
    static bool onFramebuffer(void *target, void *ref, IOService *svc, IONotifier *n);
    bool layoutGate();
};

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

    bool init(IOGraphicsAccelerator2 *accel, IOAccelDisplayMachine *machine, IOFramebuffer *fb, unsigned int index) override;
    void free() override;
    uintptr_t initFramebufferResource(unsigned int index, IOAccelResource2 *res) override;
    uintptr_t validateTransaction(IOAccelDisplayPipeTransaction2 *t) override;
    bool isTransactionComplete(IOAccelDisplayPipeTransaction2 *t) override;
    IOReturn submitTransaction(IOAccelDisplayPipeTransaction2 *t) override;
    void beginTransaction(IOAccelEvent *ev) override;

    bool prepareFramebuffer();
    uint8_t *mapSurface(IOSurface *s, uint32_t id);
    bool copySurface(IOSurface *s, unsigned n);
};

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
        uint64_t dl;
        clock_interval_to_deadline(500, NSEC_PER_MSEC, &dl);
        thread_call_enter_delayed(scanCall, dl);
    }
    publishCounters();
    return true;
}

void StrixAccelerator::stop(IOService *provider)
{
    OSIncrementAtomic(&stopping);
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
    SLOG("pipe init(fb=%p index=%u) -> %d", fb, index, ok);
    if (ok && lock) OSIncrementAtomic(&gCounters[kCPipes]);
    return ok && lock;
}

void StrixDisplayPipe::free()
{
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
    IOMemoryMap *map = md->map(kIOMapAnywhere | kIOMapReadOnly);
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
    for (uint32_t y = 0; y < rows; ++y) {
        const uint8_t *sp = src + uint64_t(y) * bpr;
        uint8_t *dp = dst + uint64_t(y) * fbStride;
        if (plain) {
            bcopy(sp, dp, size_t(cols) * 4);
        } else {
            const uint32_t *s32 = reinterpret_cast<const uint32_t *>(sp);
            uint32_t *d32 = reinterpret_cast<uint32_t *>(dp);
            for (uint32_t x = 0; x < cols; ++x) {
                uint32_t v = s32[x];
                d32[x] = 0xff000000u | (((v >> 22) & 0xff) << 16) | (((v >> 12) & 0xff) << 8) | ((v >> 2) & 0xff);
            }
        }
    }
    __asm__ volatile("sfence" ::: "memory");   // flush the write-combining buffers
    return true;
}

uintptr_t StrixDisplayPipe::validateTransaction(IOAccelDisplayPipeTransaction2 *t)
{
    // AppleParavirtDisplayPipe::validateTransaction: a transaction without a plane-0 IOSurface is an error
    if (strix_txn_getPlaneIOSurface(t, 0, 0)) return 0;
    OSIncrementAtomic(&gCounters[kCValidateFail]);
    return 0xE00002BC;
}

bool StrixDisplayPipe::isTransactionComplete(IOAccelDisplayPipeTransaction2 *)
{
    return true;   // submitTransaction completes synchronously
}

IOReturn StrixDisplayPipe::submitTransaction(IOAccelDisplayPipeTransaction2 *t)
{
    const unsigned n = unsigned(OSIncrementAtomic(&gCounters[kCTxn])) + 1;
    IOSurface *s = strix_txn_getPlaneIOSurface(t, 0, 0);
    bool copied = false;
    if (s && lock) {
        IOLockLock(lock);
        copied = copySurface(s, n);
        IOLockUnlock(lock);
    }
    OSIncrementAtomic(&gCounters[copied ? kCCopied : kCSkipped]);
    if (owner && (n <= 8 || (n % 120) == 0)) owner->publishCounters();
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
