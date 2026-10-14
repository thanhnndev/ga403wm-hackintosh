// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
//
// Gives WindowServer a Metal device on a laptop whose only display is not on the NVIDIA GPU (docs/890M-TRACE.md).
//
// With StrixAccel publishing a display pipe, CoreDisplay takes the Metal compositor path and asserts "Failed to create
// MetalDevice" when WindowServer has no device. NullMoth's NVAccel withholds MetalPluginName until an NVIDIA display head
// registers; NVRMFB starts no head with no NVIDIA monitor, so after 60 s NVAccel's headless check restores the name AND
// sets debug.nvaccel_headless=1, and the NVMTLDriver plugin then refuses WindowServer a device (it expects the display's
// own GPU to have one; the 890M has no Metal driver). Without the headless flag the plugin hands WindowServer the NVIDIA
// device, exactly as on a boot with an HDMI monitor, with the OLED presented through StrixAccel's display pipe.
//
// So: when NVAccel has no NVIDIA display head, put MetalPluginName back ourselves before its 60 s check; the check then
// finds "plugin name already back" and leaves debug.nvaccel_headless at 0. Nothing is written when a head exists (the
// vendor's own arming owns that case). Boot-arg -strixmetalgateoff disables it.
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <libkern/OSAtomic.h>
#include <libkern/c++/OSMetaClass.h>
#include <pexpert/pexpert.h>
#include <kern/thread_call.h>
#include <kern/clock.h>

#define GLOG(fmt, ...) IOLog("StrixMetalGate: " fmt "\n", ##__VA_ARGS__)

namespace {
constexpr unsigned kPeriodSec = 2;      // poll period
constexpr unsigned kHoldSec = 40;       // after NVAccel appears: leave the vendor's arming this long (it gives up ~34 s)
constexpr unsigned kGiveUpSec = 300;    // stop polling
// NVAccel's own Info.plist value: it removes the property at start() and keeps the object to restore later
const char kPluginName[] = "../../../Library/GPUBundles/NVMTLDriver";

// first service of a class (retained), count of all of them
IOService *findOne(const char *cls, unsigned *count)
{
    IOService *first = nullptr;
    unsigned n = 0;
    if (OSDictionary *m = IOService::serviceMatching(cls)) {
        if (OSIterator *it = IOService::getMatchingServices(m)) {
            while (OSObject *o = it->getNextObject()) {
                IOService *s = OSDynamicCast(IOService, o);
                if (!s) continue;
                if (!first) { first = s; first->retain(); }
                n++;
            }
            it->release();
        }
        m->release();
    }
    if (count) *count = n;
    return first;
}
}

class StrixMetalGate : public IOService {
    OSDeclareDefaultStructors(StrixMetalGate)
    thread_call_t call = nullptr;
    volatile int32_t stopping = 0;
    volatile int32_t inTick = 0;
    unsigned elapsed = 0;       // seconds since start
    unsigned seenAt = 0;        // elapsed when NVAccel was first seen
    bool seen = false;
    bool finished = false;
    static void fire(thread_call_param_t self, thread_call_param_t);
    void tick();
    void arm();
    void state(const char *s) { setProperty("GateState", s); }
public:
    IOService *probe(IOService *provider, SInt32 *score) override;
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
};
OSDefineMetaClassAndStructors(StrixMetalGate, IOService)

IOService *StrixMetalGate::probe(IOService *provider, SInt32 *score)
{
    char b[8];
    if (PE_parse_boot_argn("-strixmetalgateoff", b, sizeof b)) return nullptr;
    return IOService::probe(provider, score);
}

void StrixMetalGate::arm()
{
    if (stopping || !call) return;
    uint64_t dl;
    clock_interval_to_deadline(kPeriodSec, NSEC_PER_SEC, &dl);
    thread_call_enter_delayed(call, dl);
}

void StrixMetalGate::fire(thread_call_param_t self, thread_call_param_t)
{
    StrixMetalGate *g = static_cast<StrixMetalGate *>(self);
    OSIncrementAtomic(&g->inTick);
    if (!g->stopping) g->tick();
    OSDecrementAtomic(&g->inTick);
}

void StrixMetalGate::tick()
{
    elapsed += kPeriodSec;
    if (finished) return;
    if (elapsed > kGiveUpSec) { state("gave-up"); GLOG("gave up after %u s", elapsed); finished = true; return; }

    IOService *accel = findOne("NVAccel", nullptr);
    if (!accel) { arm(); return; }
    if (!seen) { seen = true; seenAt = elapsed; state("nvaccel-seen"); GLOG("NVAccel is up (%u s)", elapsed); }

    if (accel->getProperty("MetalPluginName")) {
        state("plugin-name-present");
        GLOG("MetalPluginName is already published (%u s) -- nothing to do", elapsed);
        finished = true;
    } else if (elapsed - seenAt < kHoldSec) {
        arm();
    } else {
        unsigned heads = 0;
        if (IOService *h = findOne("NVRMNVDAFramebuffer", &heads)) h->release();
        if (heads) {
            // an NVIDIA head published: the vendor arming restores the name itself; keep watching in case it never does
            state("nvidia-head-waiting");
            arm();
        } else {
            accel->setProperty("MetalPluginName", kPluginName);
            accel->setProperty("StrixMetalGate", kOSBooleanTrue);
            state("plugin-name-restored");
            setProperty("RestoredAtSeconds", (unsigned long long)elapsed, 32);
            GLOG("no NVIDIA display head %u s after NVAccel: MetalPluginName restored so WindowServer gets the NVIDIA "
                 "Metal device (debug.nvaccel_headless stays 0)", elapsed - seenAt);
            finished = true;
        }
    }
    accel->release();
}

bool StrixMetalGate::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    call = thread_call_allocate(&StrixMetalGate::fire, this);
    if (!call) { GLOG("thread_call_allocate failed"); return false; }
    setProperty("GateVersion", "0.1.0");
    state("started");
    registerService();
    arm();
    GLOG("started");
    return true;
}

void StrixMetalGate::stop(IOService *provider)
{
    OSIncrementAtomic(&stopping);
    if (call) {
        thread_call_t c = call;
        call = nullptr;
        thread_call_cancel(c);
        while (inTick) IOSleep(10);   // a callout that was already running finishes before we free
        thread_call_free(c);
    }
    IOService::stop(provider);
}
