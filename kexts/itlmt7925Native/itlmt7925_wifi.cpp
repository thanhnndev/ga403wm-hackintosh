// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// itlmt7925Wifi - native IO80211Controller front end for the MT7925 (controller ABI identical on 24H32 and 25G241; the interface
// ABI halves differ, see docs/IO80211-ABI.md "Tahoe port").
//
// Matches the core driver (`itlmt7925`) as its provider and does nothing unless boot-arg itlmt_native=1 is set. What it does
// today is exactly what IO80211Controller::start() demands of a subclass (docs/IO80211-ABI-2.md, "Controller startup" and
// "Native stub"): a work queue before start, a real CCLogStream from getLogger(), a non-null fault reporter from
// getFaultReporterFromDriver() (a null one panics in findAndAttachToFaultReporter). It creates no interface, no queues, and
// answers every request as prohibited; the data path stays on the Ethernet front end in the core kext.
//
// Stage 2 (second boot-arg itlmt_native_if=1): after the base start it also creates the native interface
// (itlmt7925_iface.cpp), in the order of AppleBCMWLANCore::createSkywalkInterface: object -> attachInterface -> RegistrationInfo
// -> interface start (which registers pool + queues) -> detachInterface on failure. Still no radio.
#include "../itlmt7925/io80211/IO80211Controller.h"
#include "../itlmt7925/io80211/IO80211WorkQueue.h"
#include "corecapture_min.h"
#include "itlmt7925_iface.h"

#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IORegistryEntry.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/network/IONetworkMedium.h>
#include <pexpert/pexpert.h>
#include <string.h>

#define LOGT "itlmt7925Wifi: "

class itlmt7925Wifi : public IO80211Controller {
    OSDeclareDefaultStructors(itlmt7925Wifi)

public:
    bool init(OSDictionary *properties = nullptr) override;
    bool start(IOService *provider) override;
    IOReturn selectMedium(const IONetworkMedium *medium) override;
    IOReturn getHardwareAddress(IOEthernetAddress *address) override;
    void stop(IOService *provider) override;
    void free() override;

    // IO80211Controller virtuals the base class needs from a subclass (see ABI-2: slots 397, 399 and the pure ones)
    bool createWorkQueue() override;
    IO80211WorkQueue *getWorkQueue() const override;
    IOWorkLoop *getWorkLoop() const override;
    CCLogStream *getLogger() const override;
    IO80211FaultReporter *getFaultReporterFromDriver() override;
    IOReturn isCommandProhibited(int cmd) override;
    IOReturn handleCardSpecific(IO80211SkywalkInterface *i, unsigned long cmd, void *data, bool set) override;
    IOReturn getDRIVER_VERSION(IO80211SkywalkInterface *i, apple80211_version_data *d) override;
    IOReturn getHARDWARE_VERSION(IO80211SkywalkInterface *i, apple80211_version_data *d) override;
    IOReturn getCARD_CAPABILITIES(IO80211SkywalkInterface *i, apple80211_capability_data *d) override;
    IOReturn getPOWER(IO80211SkywalkInterface *i, apple80211_power_data *d) override;
    IOReturn setPOWER(IO80211SkywalkInterface *i, apple80211_power_data *d) override;
    IOReturn getCOUNTRY_CODE(IO80211SkywalkInterface *i, apple80211_country_code_data *d) override;
    IOReturn setCOUNTRY_CODE(IO80211SkywalkInterface *i, apple80211_country_code_data *d) override;
    IOReturn setGET_DEBUG_INFO(IO80211SkywalkInterface *i, apple80211_debug_command *d) override;
    // Slot 240 (IOService's own); recorded only: which user-client types userland opens on the controller, and the result.
    IOReturn newUserClient(task_t task, void *securityID, UInt32 type, OSDictionary *properties, IOUserClient **handler) override;
    using IO80211Controller::newUserClient;

private:
    uint32_t tracedCommands[96] = {};
    uint32_t tracedCommandCount = 0;
    uint32_t rejectedCommands = 0;
    bool capsTraced = false;
    uint8_t stationAddress[6] = {0x02, 0x00, 0x79, 0x25, 0x00, 0x01};
    bool makeLogger(IOService *owner);
    bool makeFaultReporter(IOService *owner);
    bool makeInterface(IOService *provider);
    void dropInterface();

    // Apple's IOSkywalkLegacyEthernet shim (IOSkywalkFamily personality, IOProviderClass IOSkywalkEthernetInterface) is what turns
    // a Skywalk Ethernet interface into the IONetworkInterface that SystemConfiguration / configd's InterfaceNamer enumerate. Its
    // probe() refuses a provider that already carries IOInterfaceUnit, so role 1 leaves the unit unassigned and lets the shim's
    // IONetworkStack registration assign it. This watcher records what happens (registry property itlmt_native_shim) and, if no
    // unit shows up within itlmt_native_unit_wait seconds (default 45, 0 = no fallback), applies the previous behaviour
    // (IOInterfaceUnit = itlmt_native_unit_fb, default 9, + registerService) so the BSD interface still comes up.
    void unitWatchStart();
    void unitWatchStop();
    void unitCheck();
    void snapshotNetworkInterfaces(const char *tag);
    static void unitTick(OSObject *owner, IOTimerEventSource *);
    IOWorkLoop *unitLoop = nullptr;
    IOTimerEventSource *unitTimer = nullptr;
    uint32_t unitTicks = 0, unitWaitSec = 45, unitFallback = 9;
    bool unitSeen = false, unitFellBack = false;

    // state of the idle radio as userland sees it (no firmware behind it: values are only what userland itself set)
    uint32_t powerState = 0;                // apple80211_power_data +8
    uint8_t countryCode[3] = {'X', 'Z', 0}; // Apple's own "unknown country" code (the string the core compares against)

    IO80211WorkQueue *wq = nullptr;
    bool started = false;                   // IO80211Controller::start returned (getWorkLoop mode 1 switches to wq after it)
    uint32_t wlMode = 1;                    // itlmt_native_wl (default 1)
    IOWorkLoop *loop = nullptr;             // fallback IOWorkLoop when the provider has none (a real thread, unlike wq)
    CCPipe *logPipe = nullptr;
    CCStream *logStream = nullptr;          // a CCLogStream (options type 0)
    bool logPipeStarted = false;            // CCPipe::startPipe ran on it (the factories only init)
    CCPipe *dataPipe = nullptr;
    CCStream *dataStream = nullptr;         // a CCDataStream (options type 1)
    bool faultPipeStarted = false;          // ditto for the fault pipe; without it the first fault flush panics corecapture
    CCFaultReporter *ccFault = nullptr;
    IO80211FaultReporter *fault = nullptr;
    itlmt7925WifiInterface *iface = nullptr;
};

#define super IO80211Controller
OSDefineMetaClassAndStructors(itlmt7925Wifi, IO80211Controller)

namespace {

const char kOwnerId[] = "com.itlmt7925.native";

template <typename T>
inline void put(uint8_t *block, size_t off, T v)
{
    memcpy(block + off, &v, sizeof(v));
}

inline void rel(void *o)
{
    if (o) ((OSObject *)o)->release();
}

// errno-style value Apple's BCM driver returns from isCommandProhibited() when it rejects commands (ENOTSUP)
const IOReturn kProhibited = 0x3a;

}

bool itlmt7925Wifi::init(OSDictionary *properties)
{
    return super::init(properties);
}

// CCPipeOptions / CCStreamOptions as Apple fills them (ABI-2 section 1; keys of the CoreCapture registry entry in brackets).
// Pipe options (zeroed, 0x350 bytes): +0 [PipeType], +0x10 [PipeSize], +0x18 [MinLogSizeToNotify], +0x20 [NotifyThreshold],
// +0x24 [Filename], +0x124 [LogIdentifier], +0x224 [FileSize], +0x228 [NumberOfFiles], +0x244 [DirectoryName].
bool itlmt7925Wifi::makeLogger(IOService *owner)
{
    uint8_t *po = (uint8_t *)IOMalloc(kCCPipeOptionsSize);
    uint8_t *so = (uint8_t *)IOMalloc(kCCStreamOptionsSize);
    bool ok = false;
    if (po && so) {
        bzero(po, kCCPipeOptionsSize);
        bzero(so, kCCStreamOptionsSize);
        // The values of Apple's ControlPath pipe (IO80211Controller::setupControlPathLogging)
        put<uint32_t>(po, 0x000, 0);                    // CCLogPipe
        put<uint64_t>(po, 0x010, 0x10000);
        put<uint64_t>(po, 0x018, 0x6666);
        put<uint32_t>(po, 0x020, 0x3e8);
        strlcpy((char *)po + 0x024, "itlmt7925Wifi", 0x100);
        strlcpy((char *)po + 0x124, "itlmt7925Wifi", 0x100);
        put<uint32_t>(po, 0x224, 0x200000);
        put<uint32_t>(po, 0x228, 2);
        strlcpy((char *)po + 0x244, "WiFi", 0x100);
        // Stream: class CCLogStream, level -1 (Apple's default, 5 only when io80211isDebuggable())
        put<uint32_t>(so, 0x000, 0);
        put<uint32_t>(so, 0x008, 0xffffffffu);
        put<uint32_t>(so, 0x00c, 0xffffffffu);
        strlcpy((char *)so + 0x058, "itlmt7925Wifi", 0xf0);

        logPipe = CCPipe::withOwnerNameCapacity(owner, kOwnerId, "itlmt7925Wifi", (const CCPipeOptions *)po);
        // CCLogStream::initWithPipeAndName casts the pipe to CCLogPipe without a null check: never pass a null pipe
        if (logPipe)
            logStream = CCStream::withPipeAndName(logPipe, "itlmt7925Wifi", (const CCStreamOptions *)so);
        // Apple starts every pipe it hands to CoreCapture (see ccPipeStartPipe); the factory only inits.
        if (logPipe && logStream) {
            logPipeStarted = ccPipeStartPipe(logPipe);
            if (!logPipeStarted) itlmtTrace(this, "ctl:logPipe start failed");
        }
        ok = logPipe && logStream;
    }
    if (po) IOFree(po, kCCPipeOptionsSize);
    if (so) IOFree(so, kCCStreamOptionsSize);
    return ok;
}

// Fault reporter: IO80211FaultReporter(CCFaultReporter(CCDataStream(CCDataPipe))). The data pipe/stream take the option
// values Apple uses for its crash-tracer log in AppleBCMWLANBusInterfacePCIe::createCrashTracerLogger (pipe type 1,
// +4 = 2 [LogType], +8 = 6 [LogDataType], +0x10 = 0x40 [PipeSize], +0x230 = the owner; stream type 1, +8 = -1 as a qword).
bool itlmt7925Wifi::makeFaultReporter(IOService *owner)
{
    uint8_t *po = (uint8_t *)IOMalloc(kCCPipeOptionsSize);
    uint8_t *so = (uint8_t *)IOMalloc(kCCStreamOptionsSize);
    bool ok = false;
    if (po && so && wq) {
        bzero(po, kCCPipeOptionsSize);
        bzero(so, kCCStreamOptionsSize);
        put<uint32_t>(po, 0x000, 1);                    // CCDataPipe
        put<uint32_t>(po, 0x004, 2);
        put<uint64_t>(po, 0x008, 6);
        put<uint64_t>(po, 0x010, 0x40);
        strlcpy((char *)po + 0x024, "itlmt7925WifiFault", 0x100);
        strlcpy((char *)po + 0x124, "itlmt7925WifiFault", 0x100);
        strlcpy((char *)po + 0x244, "WiFi", 0x100);
        put<uint64_t>(po, 0x230, (uint64_t)(uintptr_t)owner);
        put<uint32_t>(so, 0x000, 1);                    // CCDataStream
        put<uint64_t>(so, 0x008, ~0ull);

        dataPipe = CCPipe::withOwnerNameCapacity(owner, kOwnerId, "itlmt7925WifiFault", (const CCPipeOptions *)po);
        if (dataPipe)
            dataStream = CCStream::withPipeAndName(dataPipe, "itlmt7925WifiFault", (const CCStreamOptions *)so);
        // The step the factory does not do and AppleBCMWLANBusInterfacePCIe::createCrashTracerLogger ends with: without a
        // started pipe the first fault-report flush panics in corecapture (ccPipeStartPipe has the whole story). Keep the
        // reporter even when it fails - a null one panics the family at findAndAttachToFaultReporter - but say so.
        if (dataPipe && dataStream) {
            faultPipeStarted = ccPipeStartPipe(dataPipe);
            itlmtTrace(this, "ctl:faultPipe=%u", (unsigned)(faultPipeStarted ? 1 : 0));
            if (!faultPipeStarted) IOLog(LOGT "fault pipe start failed (fault flushes will panic)\n");
        }
        if (dataStream)
            ccFault = CCFaultReporter::withStreamWorkloop((CCDataStream *)dataStream, (IOWorkLoop *)wq);
        if (ccFault)
            fault = IO80211FaultReporter::allocWithParams(ccFault);
        ok = fault != nullptr;
    }
    if (po) IOFree(po, kCCPipeOptionsSize);
    if (so) IOFree(so, kCCStreamOptionsSize);
    return ok;
}

bool itlmt7925Wifi::start(IOService *provider)
{
    uint32_t on = 0;
    if (!PE_parse_boot_argn("itlmt_native", &on, sizeof(on)) || !on) {
        IOLog(LOGT "idle (boot-arg itlmt_native not set)\n");
        return false;
    }
    itlmtCallInit();
    itlmtTrace(this, "ctl:start");
    itlmtTrace(this, "ctl:createWorkQueue begin");
    if (!createWorkQueue()) {
        IOLog(LOGT "no work queue\n");
        return false;
    }
    itlmtTrace(this, "ctl:workQueue ok");
    if (!makeLogger(provider)) {
        IOLog(LOGT "no logger\n");
        return false;
    }
    itlmtTrace(this, "ctl:logger ok");
    if (!makeFaultReporter(provider)) {
        IOLog(LOGT "no fault reporter\n");
        return false;
    }
    itlmtTrace(this, "ctl:faultReporter ok; base start begin");
    if (!super::start(provider)) {
        IOLog(LOGT "IO80211Controller::start failed\n");
        return false;
    }
    itlmtTrace(this, "ctl:base start ok");
    PE_parse_boot_argn("itlmt_native_wl", &wlMode, sizeof(wlMode));
    started = true;
    // Round 12: the inherited Skywalk media getter reads our dictionary;
    // a missing dictionary is converted to EIO by ioctl_gifmedia.
    // Advertise automatic Wi-Fi selection, without claiming a radio link.
    OSDictionary *media = OSDictionary::withCapacity(1);
    IONetworkMedium *automatic = IONetworkMedium::medium(kIOMediumIEEE80211Auto, 0);
    bool mediaOK = media && automatic && IONetworkMedium::addMedium(media, automatic)
        && publishMediumDictionary(media) && setSelectedMedium(automatic);
    if (automatic) automatic->release();
    if (media) media->release();
    itlmtTrace(this, "ctl:media auto=%u", mediaOK);
    if (!mediaOK) {
        IOLog(LOGT "media publication failed, controller only\n");
        registerService();
        return true;
    }
    registerService();
    uint32_t withIf = 0;
    if (PE_parse_boot_argn("itlmt_native_if", &withIf, sizeof(withIf)) && withIf) {
        if (!makeInterface(provider)) {
            // the controller stays up without an interface; nothing else depends on it
            IOLog(LOGT "interface creation failed, controller only\n");
            return true;
        }
        IOLog(LOGT "controller and interface started (no radio)\n");
        return true;
    }
    IOLog(LOGT "controller started (no interface: itlmt_native_if not set)\n");
    return true;
}

// The core driver's Ethernet front end publishes IOMACAddress on itself (IOEthernetController::start); it is a child of the core.
IOReturn itlmt7925Wifi::selectMedium(const IONetworkMedium *medium)
{
    if (!medium || medium->getType() != kIOMediumIEEE80211Auto)
        return kIOReturnUnsupported;
    return setSelectedMedium(medium) ? kIOReturnSuccess : kIOReturnError;
}

IOReturn itlmt7925Wifi::getHardwareAddress(IOEthernetAddress *address)
{
    if (!address) return kIOReturnBadArgument;
    // Supply the station identity independently of Family interface/MAC-agent
    // initialization. The default getter depends on those objects being ready.
    memcpy(address, stationAddress, sizeof(stationAddress));
    return kIOReturnSuccess;
}

static bool findMac(IOService *provider, uint8_t out[6])
{
    bool found = false;
    // the core publishes the station address on itself in native mode (itlmt7925_m2.cpp)
    if (OSData *d = OSDynamicCast(OSData, provider->getProperty("IOMACAddress"))) {
        if (d->getLength() == 6) {
            memcpy(out, d->getBytesNoCopy(), 6);
            return true;
        }
    }
    if (IORegistryIterator *it = IORegistryIterator::iterateOver(provider, gIOServicePlane)) {
        while (!found) {
            IORegistryEntry *e = it->getNextObject();
            if (!e) break;
            if (OSData *d = OSDynamicCast(OSData, e->getProperty("IOMACAddress"))) {
                if (d->getLength() == 6) {
                    memcpy(out, d->getBytesNoCopy(), 6);
                    found = true;
                }
            }
        }
        it->release();
    }
    return found;
}

// Mirrors AppleBCMWLANCore::createSkywalkInterface (0xffffff800163aaf8, ABI-2 "Native stub, stage 2"). Role 2 (LowLatency) is the
// only role that gets a BSD name prefix + unit in the RegistrationInfo; role 1 (primary) sets [info+0x10] = 1 and nothing else.
bool itlmt7925Wifi::makeInterface(IOService *provider)
{
    uint8_t mac[6];
    if (!findMac(provider, mac)) {
        // locally administered placeholder: the Ethernet front end has not published a MAC (or is not loaded)
        static const uint8_t fallback[6] = {0x02, 0x00, 0x79, 0x25, 0x00, 0x01};
        memcpy(mac, fallback, 6);
        IOLog(LOGT "no IOMACAddress under the core driver, using a placeholder\n");
    }
    memcpy(stationAddress, mac, sizeof(stationAddress));
    itlmtTrace(this, "mk:mac %s", (mac[0] == 0x02 && mac[1] == 0x00 && mac[2] == 0x79 && mac[3] == 0x25) ? "placeholder" : "from core");
    // Role 1 is the primary station interface. Role 2 (LowLatency) is a secondary one: IO80211SkywalkInterface::start needs
    // ivars->parentInterface for it (it logs a failure at IO80211SkywalkInterface.cpp:0x1f8 otherwise), createSkywalkInterface only
    // makes it from a bus flag and passes the parent as its 4th argument. itlmt_native_role=2 keeps the old path for comparison.
    uint32_t role = 1;
    PE_parse_boot_argn("itlmt_native_role", &role, sizeof(role));
    // Role 1: createSkywalkInterface leaves the BSD name to the family. An explicit name/unit is only used when itlmt_native_unit is
    // given (or for role 2, where Apple always passes one).
    uint32_t unit = 9;
    bool explicitName = PE_parse_boot_argn("itlmt_native_unit", &unit, sizeof(unit)) || role == 2;

    itlmtTrace(this, "mk:start role=%u unit=%u explicit=%d", role, unit, explicitName);
    itlmt7925WifiInterface *ifc = itlmt7925WifiInterface::withController(this, 0, role);
    itlmtTrace(this, "mk:withController=%s", ifc ? "ok" : "null");
    if (!ifc) return false;
    bool att = attachInterface(ifc, this);
    itlmtTrace(this, "mk:attachInterface=%d", att);
    if (!att) {
        ifc->release();
        return false;
    }
    uint8_t block[0x130];
    bzero(block, sizeof(block));
    IOSkywalkEthernetInterface::RegistrationInfo *info = (IOSkywalkEthernetInterface::RegistrationInfo *)block;
    ifc->initRegistrationInfo(info, 1, 0x130);
    // The fields createSkywalkInterface sets after initRegistrationInfo (offsets from its disassembly; meaning of +0x14, +0x24,
    // +0x28 and +0xc is only partly known): +0x14 = 2, MAC at +0x108, +0x24 = +0x28 = 0x80, +0xc = 3, +0x3c (u16) = 0x40,
    // +0x40 flags = 4 for role 2 (| 2 when the provider has IOPMResetPowerStateOnWake: not replicated), BSD prefix at +0x30,
    // unit at +0x38.
    static const char kPrefix[] = "en";
    put<uint32_t>(block, 0x14, 2);
    memcpy(block + 0x108, mac, 6);
    put<uint32_t>(block, 0x24, 0x80);
    put<uint32_t>(block, 0x28, 0x80);
    put<uint32_t>(block, 0x0c, 3);
    put<uint16_t>(block, 0x3c, 0x40);
    if (role == 1) put<uint32_t>(block, 0x10, 1);       // createSkywalkInterface: [info+0x10] = 1 for role 1 (meaning chưa xác định)
    // Role 1: initRegistrationInfo leaves +0x38 = 0xFFFFFFFF (unit not assigned) and registerNetworkInterface only sets
    // IOInterfaceUnit for unit >= 0. That is Apple's own state for its interface: the IOSkywalkLegacyEthernet shim (see unitCheck)
    // assigns the unit when it publishes the IONetworkInterface. A pre-assigned unit made its probe() refuse (build ef42853: en9
    // existed as a Skywalk BSD interface but SystemConfiguration listed nothing). itlmt_native_unit still forces the old explicit
    // behaviour; role 2 keeps the explicit prefix/flags Apple passes.
    if (role == 2 || explicitName) {
        put<uint32_t>(block, 0x38, unit);
        put<uint32_t>(block, 0x40, 4);
        put<uint64_t>(block, 0x30, (uint64_t)(uintptr_t)kPrefix);
    }

    if (!ifc->startWithInfo(this, info)) {
        itlmtTrace(this, "mk:startWithInfo failed");
        detachInterface(ifc, false);
        ifc->release();
        return false;
    }
    itlmtTrace(this, "mk:startWithInfo ok");
    iface = ifc;
    // AppleBCMWLANCore::setupDriver clears the deferral on its interface with deferBSDAttach(false) (removeProperty
    // IODeferBSDAttach + registerService(0)), which lets IOSkywalkNetworkBSDClient attach. itlmt_native_publish >= 2 does it here.
    uint32_t publish = 2;
    PE_parse_boot_argn("itlmt_native_publish", &publish, sizeof(publish));
    {
        // Evidence for the IO80211Glue.cpp:417 panic: which work loop each layer sees and the gate/thread state right now.
        IOWorkLoop *pl = getProvider() ? getProvider()->getWorkLoop() : nullptr;
        IOWorkLoop *cl = getWorkLoop();
        IOWorkLoop *il = ifc->getWorkLoop();
        IOWorkLoop *w = (IOWorkLoop *)wq;
        itlmtTrace(this, "lp:wq=%p prov=%p", w, pl);
        itlmtTrace(this, "lp:ctl=%p if=%p", cl, il);
        itlmtTrace(this, "lp:inGate=%d onThread=%d wl=%u", w ? (int)w->inGate() : -1, w ? (int)w->onThread() : -1, wlMode);
    }
    if (role == 1 && publish >= 2) {
        IOReturn dr = ifc->deferBSDAttach(false);
        itlmtTrace(this, "mk:deferBSDAttach(false)=%x", dr);
    }
    if (role == 1 && !explicitName) unitWatchStart();
    return true;
}

// ---- unit watcher / fallback -----------------------------------------------------------------------------------------------

// One snapshot of every IONetworkInterface in the registry (class, BSD name, unit) and of the registry children of our Skywalk
// interface, as a single overwritten property so it can never fill the append-only trace.
void itlmt7925Wifi::snapshotNetworkInterfaces(const char *tag)
{
    char buf[512];
    snprintf(buf, sizeof(buf), "%s t=%us:", tag, unitTicks * 5);
    OSDictionary *match = IOService::serviceMatching("IONetworkInterface");
    OSIterator *it = match ? IOService::getMatchingServices(match) : nullptr;
    if (match) match->release();
    if (it) {
        int n = 0;
        while (OSObject *o = it->getNextObject()) {
            IOService *s = OSDynamicCast(IOService, o);
            if (!s || n >= 8) continue;
            n++;
            OSString *bs = OSDynamicCast(OSString, s->getProperty("BSD Name"));
            OSNumber *un = OSDynamicCast(OSNumber, s->getProperty("IOInterfaceUnit"));
            char one[96];
            snprintf(one, sizeof(one), " [%s %s u=%d]", s->getMetaClass()->getClassName(), bs ? bs->getCStringNoCopy() : "-",
                     un ? (int)un->unsigned32BitValue() : -1);
            strlcat(buf, one, sizeof(buf));
        }
        it->release();
    }
    if (iface) {
        OSNumber *u = OSDynamicCast(OSNumber, iface->getProperty("IOInterfaceUnit"));
        OSObject *d = iface->getProperty("IODeferBSDAttach");
        char one[96];
        snprintf(one, sizeof(one), " | skywalk unit=%d defer=%s", u ? (int)u->unsigned32BitValue() : -1, d ? "y" : "n");
        strlcat(buf, one, sizeof(buf));
        if (IORegistryIterator *ri = IORegistryIterator::iterateOver(iface, gIOServicePlane, kIORegistryIterateRecursively)) {
            int n = 0;
            while (IORegistryEntry *e = ri->getNextObject()) {
                if (n++ >= 6) break;
                char one2[64];
                snprintf(one2, sizeof(one2), " >%s", e->getMetaClass()->getClassName());
                strlcat(buf, one2, sizeof(buf));
            }
            ri->release();
        }
    }
    setProperty("itlmt_native_shim", buf);
    IOLog(LOGT "%s\n", buf);
}

void itlmt7925Wifi::unitTick(OSObject *owner, IOTimerEventSource *)
{
    itlmt7925Wifi *self = (itlmt7925Wifi *)owner;
    if (self) self->unitCheck();
}

void itlmt7925Wifi::unitCheck()
{
    itlmt7925WifiInterface *ifc = iface;
    if (!ifc || !unitTimer) return;
    unitTicks++;
    bool hasUnit = ifc->getProperty("IOInterfaceUnit") != nullptr;
    if (hasUnit && !unitSeen) {
        unitSeen = true;
        itlmtTrace(this, "unit:assigned t=%us fb=%d", unitTicks * 5, unitFellBack);
        snapshotNetworkInterfaces("assigned");
        return;                              // done: no further ticks
    }
    if (unitTicks == 1) snapshotNetworkInterfaces("first");
    if (!unitSeen && !unitFellBack && unitWaitSec && unitTicks * 5 >= unitWaitSec) {
        unitFellBack = true;
        itlmtTrace(this, "unit:none after %us, explicit unit %u", unitTicks * 5, unitFallback);
        if (OSNumber *n = OSNumber::withNumber((uint64_t)unitFallback, 32)) {
            ifc->setProperty("IOInterfaceUnit", n);
            n->release();
        }
        ifc->registerService(kIOServiceAsynchronous);
    }
    if (unitTicks >= 40) {                   // 200 s: stop whatever happened
        snapshotNetworkInterfaces("final");
        return;
    }
    unitTimer->setTimeoutMS(5000);
}

void itlmt7925Wifi::unitWatchStart()
{
    if (unitTimer) return;
    PE_parse_boot_argn("itlmt_native_unit_wait", &unitWaitSec, sizeof(unitWaitSec));
    PE_parse_boot_argn("itlmt_native_unit_fb", &unitFallback, sizeof(unitFallback));
    unitLoop = IOWorkLoop::workLoop();
    if (unitLoop) unitTimer = IOTimerEventSource::timerEventSource(this, (IOTimerEventSource::Action)&itlmt7925Wifi::unitTick);
    if (!unitLoop || !unitTimer || unitLoop->addEventSource(unitTimer) != kIOReturnSuccess) {
        itlmtTrace(this, "unit:watcher unavailable");
        unitWatchStop();
        return;
    }
    unitTicks = 0;
    unitTimer->setTimeoutMS(5000);
    itlmtTrace(this, "unit:watch wait=%us fb=%u", unitWaitSec, unitFallback);
}

void itlmt7925Wifi::unitWatchStop()
{
    if (unitTimer) {
        unitTimer->cancelTimeout();
        if (unitLoop) unitLoop->removeEventSource(unitTimer);
        unitTimer->release();
        unitTimer = nullptr;
    }
    if (unitLoop) {
        unitLoop->release();
        unitLoop = nullptr;
    }
}

void itlmt7925Wifi::dropInterface()
{
    unitWatchStop();
    if (!iface) return;
    itlmt7925WifiInterface *ifc = iface;
    iface = nullptr;
    detachInterface(ifc, false);
    ifc->release();
}

void itlmt7925Wifi::stop(IOService *provider)
{
    dropInterface();
    super::stop(provider);
}

void itlmt7925Wifi::free()
{
    // reverse order of creation; the reporter chain holds the stream and the work queue
    dropInterface();
    rel(fault);       fault = nullptr;
    rel(ccFault);     ccFault = nullptr;
    rel(dataStream);  dataStream = nullptr;
    rel(dataPipe);    dataPipe = nullptr;
    rel(logStream);   logStream = nullptr;
    rel(logPipe);     logPipe = nullptr;
    rel(wq);          wq = nullptr;
    rel(loop);        loop = nullptr;
    itlmtCallFree();
    super::free();
}

// The base class never calls createWorkQueue() from start(): getWorkQueue() must already return a queue (ABI-2 round 2).
// Apple's own BCM driver takes IO80211WorkQueue::workQueue() when boot-arg wlan.workQueue.create is set.
bool itlmt7925Wifi::createWorkQueue()
{
    if (!wq) wq = IO80211WorkQueue::workQueue();
    return wq != nullptr;
}

IO80211WorkQueue *itlmt7925Wifi::getWorkQueue() const
{
    return wq;
}

// IONetworkController::start (24H32, +0x1d4) compares this->getWorkLoop() with provider->getWorkLoop() and, when they
// differ, calls ml_thread_policy(workLoop->getThread(), ...). IO80211WorkQueue::getThread is an 8-byte stub returning
// NULL, so returning the queue (what IO80211Controller::getWorkLoop evidently does) panicked at 0.47 s in stage A.
// Return the provider's real work loop, so the compare matches and the call is skipped; fall back to an own IOWorkLoop
// (real thread) so the call would be harmless if it were reached.
// Round 10 settled this: IO80211SkywalkInterface::start stores W = controller->getWorkQueue() in ivars+0x38 and IO80211Glue keeps it;
// IO80211Controller::getWorkLoop() is a tail call to the same getWorkQueue slot (0xffffff800222aec0). IOSkywalkBSDClient::start gets
// its loop through the plain IOService::getWorkLoop chain (interface -> controller) and attaches its IOCommandGate to it, and
// prepareBSDInterface -> updateStaticProperties -> IO80211Glue::sendIOUCToWcl panics unless W->inGate() && !W->onThread(), i.e. unless
// the BSD client's gate sits on W. So after IO80211Controller::start has returned the answer must be the IO80211WorkQueue, as in
// Apple's controller. The early answer stays the provider's loop (stage-A ml_thread_policy(NULL) panic). itlmt_native_wl=0 disables.
IOWorkLoop *itlmt7925Wifi::getWorkLoop() const
{
    if (started && wlMode == 1 && wq) return (IOWorkLoop *)wq;
    IOService *p = getProvider();
    IOWorkLoop *l = p ? p->getWorkLoop() : nullptr;
    if (l) return l;
    itlmt7925Wifi *self = const_cast<itlmt7925Wifi *>(this);
    if (!self->loop) self->loop = IOWorkLoop::workLoop();
    return self->loop;
}

CCLogStream *itlmt7925Wifi::getLogger() const
{
    return (CCLogStream *)logStream;
}

IO80211FaultReporter *itlmt7925Wifi::getFaultReporterFromDriver()
{
    return fault;
}

// Every request is refused until an interface exists.
// Only the two static-property ioctls IO80211InfraInterface::updateStaticProperties sends during BSD attach (0x2c HARDWARE_VERSION,
// 0x2b DRIVER_VERSION) are allowed; everything else stays refused until the matching handler exists.
//
// 0xc CARD_CAPABILITIES joined the allowed set after the live trace of build 3b4ff24 showed userland asking for it right after
// the version pair and getting 0x3a (registry: `ioctl:cmd=c prohibited`, `itlmt_ioctl_rejected` in the thousands while the
// interface was otherwise up). Apple's client library asks DRIVER_VERSION then CARD_CAPABILITIES when it binds an interface;
// a refusal there ends the bind before CoreWLAN lists the device.
//
// Round 14 (the boot after ef42853 showed what airportd/CoreWLAN ask for once the interface exists: 0x13 POWER x71, 0x33
// COUNTRY_CODE, 0xf OP_MODE x20, 0x1b, 4, 5, 0x10, 0x103, 0xcf, 0xd8, 0x16b, 0x1d5, 0x200) the commands that now have a handler
// with an Apple-derived layout are let through: POWER and COUNTRY_CODE on the controller; CHANNEL, POWERSAVE, RATE, OP_MODE, RSSI,
// USB_HOST_NOTIFICATION, OS_FEATURE_FLAGS and INFRA_ENUMERATED on the interface. 0x1b/0xcf/0xd8/0x103 stay refused (their data
// comes from firmware tables this driver does not have; nothing is invented for them).
//
// Round 15 (scan and join): 0x1b / 0xfe (supported channels), 0x1b9 SCAN_REQ, 0x1b3 SCAN_ABORT, 0x1ba ASSOCIATE, 0x1b6 JOIN_ABORT,
// 0x1a9 LEAVE_NETWORK and 0x1b1 WCL_BSS_INFO have handlers with Apple-derived layouts. The rest of the group are let through only
// so the call recorder shows who asks for them and when (their stubs answer kIOReturnUnsupported, as the layout is not known):
// 0x3 CIPHER_KEY, 0x7 TXPOWER, 0x1c LOCALE, 0xcf CHANNELS_INFO, 0xd8 ROAM_PROFILE, 0xff BTCOEX_PROFILE, 0x103 MAX_NSS_FOR_AP,
// 0x17b COUNTRY_CHANNELS_INFO, 0x1aa REASSOC, 0x1bc LINK_UP_DONE, 0x1c1 WCL_CHANNELS_INFO, 0x1c6 LINK_STATE_UPDATE,
// 0x1cc WCL_EXTENDED_BSS_INFO, 0x1eb WNM_OPS, 0x216 PLATFORM_CONFIG.
//
// Round 16 (the boot after 4b9273b: scan listed networks, a join aborted with 58): WCLJoinManager::handleJoinRequest asks the
// driver for 0x1ab WCL_LOW_LATENCY_INFO before anything else and aborts on a nonzero answer; the rest of its sequence is
// 0x170 SET_MAC_ADDRESS, 0x1ba ASSOCIATE (1b6 JOIN_ABORT / 1b7 TRIGGER_CC on the abort path), and the link-up path then sends
// 0x1bc LINK_UP_DONE, 0x1c6 LINK_STATE_UPDATE and 0x1be SET_SCAN_HOME_AWAY_TIME. All of them have handlers now.
static bool commandAllowed(int cmd)
{
    switch (cmd) {
    case 0x04: case 0x05: case 0x08: case 0x0c: case 0x0f: case 0x10: case 0x13: case 0x16b: case 0x1d5: case 0x200:
    case 0x2b: case 0x2c: case 0x33:
    case 0x1b: case 0xfe: case 0x1b9: case 0x1b3: case 0x1ba: case 0x1b6: case 0x1a9: case 0x1b1:
    case 0x03: case 0x07: case 0x1c: case 0xcf: case 0xd8: case 0xff: case 0x103: case 0x17b: case 0x1aa: case 0x1bc:
    case 0x1c1: case 0x1c6: case 0x1cc: case 0x1eb: case 0x216:
    case 0x170: case 0x1ab: case 0x1be: case 0x1b7:
    // round 19: what WCLNetManager::setCurrentBSS / linkUp / startProtectIp send once the family has the link
    case 0x1f6: case 0x1b2: case 0x188: case 0x1b5: case 0x1bb: case 0x1ac:
    // round 27: NSS is polled about once a second while linked and was refused until the handler existed (512 refusals in one
    // 10-minute boot); getNSS answers with the core's negotiated stream count
    case 0x161:
        return true;
    default:
        return false;
    }
}

IOReturn itlmt7925Wifi::isCommandProhibited(int cmd)
{
    // every request, with the three return addresses above this frame (decode against the dumps: docs/TEST-NATIVE-WIFI.md)
    uint32_t callers[3];
    itlmtCallers(callers, (uintptr_t)__builtin_frame_address(0));
    itlmtCall(this, 'I', (uint32_t)cmd, callers);
    bool seen = false;
    for (uint32_t n = 0; n < tracedCommandCount; n++) if (tracedCommands[n] == (uint32_t)cmd) seen = true;
    if (!seen && tracedCommandCount < 96) {
        tracedCommands[tracedCommandCount++] = (uint32_t)cmd;
        itlmtTrace(this, "ioctl:cmd=%x %s", cmd, commandAllowed(cmd) ? "allowed" : "prohibited");
    }
    if (commandAllowed(cmd))
        return kIOReturnSuccess;
    if ((++rejectedCommands & 63) == 1)
        setProperty("itlmt_ioctl_rejected", (uint64_t)rejectedCommands, 64);
    return kProhibited;
}

IOReturn itlmt7925Wifi::handleCardSpecific(IO80211SkywalkInterface *, unsigned long cmd, void *, bool set)
{
    itlmtCall(this, 'H', (uint32_t)cmd | (set ? 0x80000000u : 0));
    return kIOReturnUnsupported;
}

// Layout of apple80211_version_data (IOKit/80211/apple80211_ioctl.h): u32 version, u16 string_len, char string[256].
struct VersionLayout {
    uint32_t version;
    uint16_t stringLen;
    char string[256];
};

static IOReturn fillVersion(apple80211_version_data *data, const char *text)
{
    if (!data)
        return kIOReturnBadArgument;
    VersionLayout *d = (VersionLayout *)data;
    d->version = 1;
    size_t n = strlen(text);
    if (n > sizeof(d->string) - 1)
        n = sizeof(d->string) - 1;
    memcpy(d->string, text, n);
    d->string[n] = 0;
    d->stringLen = (uint16_t)n;
    return kIOReturnSuccess;
}

IOReturn itlmt7925Wifi::getDRIVER_VERSION(IO80211SkywalkInterface *, apple80211_version_data *d)
{
    itlmtCall(this, 'C', 0x2b);
    return fillVersion(d, "itlmt7925Native 0.1");
}

IOReturn itlmt7925Wifi::getHARDWARE_VERSION(IO80211SkywalkInterface *, apple80211_version_data *d)
{
    itlmtCall(this, 'C', 0x2c);
    return fillVersion(d, "MediaTek MT7925");
}

// apple80211_capability_data, only the extent Apple's driver writes (AppleBCMWLANCore::getCARD_CAPABILITIES, 0xffffff80015f16ca,
// 24H32): u32 version at +0 and a 20-byte capability bit array at +4..+0x17 (every byte of it is stored by that function, either
// by an immediate or by the qword/byte clears at +7/+0xf/+0x17). Nothing past +0x17 is written there, so nothing past it is
// written here; sizeof the struct is not known and the caller's buffer is at least that large.
//
// Which bit means which capability is not established by the dumps (the names live in userland). Policy: report only what Apple's
// function reports without consulting chip state: (a) the stores of constants at +4/+5/+6/+9/+0xc/+0xd, (b) the two unconditional
// ORs (+7 |= 4, +0xa |= 4), (c) the two bits it sets when BCM firmware feature flags 1 and 7 are *absent* (+6 |= 0x10|0x02, +9 |= 1),
// which is literally true here because there is no BCM feature table. Every bit that Apple derives from a firmware feature flag,
// chip revision or radio state (about 100 bits) stays clear: we claim nothing we cannot back.
IOReturn itlmt7925Wifi::getCARD_CAPABILITIES(IO80211SkywalkInterface *, apple80211_capability_data *data)
{
    itlmtCall(this, 'C', 0x0c);
    if (!data)
        return kIOReturnBadArgument;
    uint8_t *d = (uint8_t *)data;
    bzero(d, 0x18);
    put<uint32_t>(d, 0x00, 1);                  // version
    d[0x04] = 0x6f;                             // word 0xe66f at +4
    d[0x05] = 0xe6;
    d[0x06] = 0x61 | 0x10 | 0x02;               // constant 0x61, + flags 1 and 7 absent
    d[0x07] = 0x04;                             // unconditional OR
    d[0x09] = 0x40 | 0x01;                      // constant 0x40, + flag 1 absent
    d[0x0a] = 0x04;                             // unconditional OR
    d[0x0c] = 0x01;                             // word 0x0201 at +0xc
    d[0x0d] = 0x02;
    // userland polls this one; the trace buffer is small, so only the first answer is recorded
    if (!capsTraced) {
        capsTraced = true;
        itlmtTrace(this, "ioctl:CARD_CAPABILITIES answered");
    }
    return kIOReturnSuccess;
}

// AppleBCMWLANCore::getPOWER (0xffffff80015f238a): [data+8] = current power state, [data+4] = 1, returns 0. The state lives in
// the core context; here it is only what userland last set (setPOWER), initially 0 (off: the radio is idle).
IOReturn itlmt7925Wifi::getPOWER(IO80211SkywalkInterface *, apple80211_power_data *data)
{
    itlmtCall(this, 'C', 0x13);
    if (!data) return kIOReturnBadArgument;
    uint8_t *d = (uint8_t *)data;
    put<uint32_t>(d, 0x08, powerState);
    put<uint32_t>(d, 0x04, 1);
    return kIOReturnSuccess;
}

// AppleBCMWLANCore::setPOWER (0xffffff800160d63e) compares [data+8] with the state it holds at core+0x4cd4, returns 0 when equal,
// otherwise runs handlePowerStateChange and posts a message to the interface. There is no firmware here, so the request is only
// recorded; it neither starts nor stops anything.
IOReturn itlmt7925Wifi::setPOWER(IO80211SkywalkInterface *, apple80211_power_data *data)
{
    itlmtCall(this, 'C', 0x80000013);
    if (!data) return kIOReturnBadArgument;
    uint32_t want;
    memcpy(&want, (const uint8_t *)data + 8, sizeof(want));
    if (want != powerState) {
        powerState = want;
        itlmtTrace(this, "ioctl:setPOWER=%u (recorded only)", want);
    }
    return kIOReturnSuccess;
}

// AppleBCMWLANCore::getCOUNTRY_CODE (0xffffff800162c94c): three bytes of the stored code copied to data+4..+6, returns 0.
// The stored code starts as "XZ", the string getCHANNELS_INFO compares against for "no country set".
IOReturn itlmt7925Wifi::getCOUNTRY_CODE(IO80211SkywalkInterface *, apple80211_country_code_data *data)
{
    itlmtCall(this, 'C', 0x33);
    if (!data) return kIOReturnBadArgument;
    memcpy((uint8_t *)data + 4, countryCode, sizeof(countryCode));
    return kIOReturnSuccess;
}

// setCOUNTRY_CODE in Apple's core (0xffffff8001611aba) pushes the code to firmware and rebuilds the channel list; this driver
// has neither, so the code is stored and returned by getCOUNTRY_CODE and nothing else changes.
IOReturn itlmt7925Wifi::setCOUNTRY_CODE(IO80211SkywalkInterface *, apple80211_country_code_data *data)
{
    itlmtCall(this, 'C', 0x80000033);
    if (!data) return kIOReturnBadArgument;
    const uint8_t *d = (const uint8_t *)data + 4;
    if (memcmp(countryCode, d, sizeof(countryCode)) != 0) {
        memcpy(countryCode, d, sizeof(countryCode));
        char cc[4] = {(char)d[0], (char)d[1], (char)d[2], 0};
        for (int i = 0; i < 3; i++) if (cc[i] && (cc[i] < 0x20 || cc[i] > 0x7e)) cc[i] = '?';
        itlmtTrace(this, "ioctl:setCOUNTRY_CODE=%s (recorded only)", cc);
    }
    return kIOReturnSuccess;
}

IOReturn itlmt7925Wifi::setGET_DEBUG_INFO(IO80211SkywalkInterface *, apple80211_debug_command *)
{
    itlmtCall(this, 'C', 0x80000f00);       // chưa xác định ioctl number: marker for "setGET_DEBUG_INFO"
    return kIOReturnUnsupported;
}

IOReturn itlmt7925Wifi::newUserClient(task_t task, void *securityID, UInt32 type, OSDictionary *properties, IOUserClient **handler)
{
    itlmtCall(this, 'U', type);
    IOReturn r = super::newUserClient(task, securityID, type, properties, handler);
    itlmtCall(this, 'u', (type << 16) | ((uint32_t)r & 0xffff));
    return r;
}
