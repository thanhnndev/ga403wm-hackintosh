// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// MtkBtFw: loads the Bluetooth firmware into the MediaTek MT7925 (USB 0489:e11e on the GA403WM), then gets out of the way.
//
// The chip enumerates as a standard USB Bluetooth controller (class e0/01/01) but answers HCI only after its RAM code has been
// downloaded. macOS has no loader for MediaTek parts, so bluetoothd finds no controller. This is the procedure of Linux
// drivers/bluetooth/btmtk.c (btmtk_usb_setup -> btmtk_setup_firmware_79xx, btmtk_usb_hci_wmt_sync):
//   * WMT commands are HCI vendor command 0xfc6f sent as a class request on the default control endpoint; the WMT event comes
//     back through a vendor IN request (bRequest 1, wValue 0x30) that has to be polled until it returns data.
//   * per firmware section: a PATCH_DWNLD query with the section's 52-byte spec (answer: download / already there / busy), then
//     the section in 250-byte blocks (flag 1 first, 2 middle, 3 last).
//   * endpoint reset option, then WMT FUNC_CTRL 1 (Bluetooth on).
// The interface is opened only for that and closed again, so bluetoothd (with BlueToolFixup) can use the controller. A section
// that is already loaded (warm reboot from Windows/Linux) is skipped by the chip's answer, as in Linux.
//
// IOLog of these kexts does not reach dmesg or the unified log on this machine: the result is in the registry,
//   ioreg -rc MtkBtFw -l | grep -E '"bt-state"|"bt-log"'
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/usb/IOUSBHostInterface.h>
#include <IOKit/usb/IOUSBHostPipe.h>
#include <kern/thread.h>
#include <stdarg.h>
#include <string.h>

extern "C" {
extern const uint8_t mtk_bt_fw[], mtk_bt_fw_end[];
extern const uint8_t mtk_bt_fw_7922[], mtk_bt_fw_7922_end[];
}

#define FW_HDR_SIZE       32
#define FW_GD_SIZE        64
#define FW_SEC_MAP_SIZE   64
#define SEC_COMMON_SIZE   12
#define SEC_SEND_SIZE     52

enum { WMT_PATCH_DWNLD = 0x1, WMT_FUNC_CTRL = 0x6 };
#define REG_DEV_ID        0x70010200
#define REG_FW_VER        0x80021004
#define REG_EP_RST_OPT    0x74011890
#define EP_RST_IN_OUT_OPT 0x00010001

static void startThread(void (*fn)(void *), void *arg)
{
    thread_t th = nullptr;
    if (kernel_thread_start((thread_continue_t)fn, arg, &th) == KERN_SUCCESS) thread_deallocate(th);
}

static inline uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

class MtkBtFw : public IOService {
    OSDeclareDefaultStructors(MtkBtFw)
public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
private:
    IOUSBHostInterface *intf = nullptr;
    IOUSBHostPipe *intrPipe = nullptr;
    IOBufferMemoryDescriptor *intrBuf = nullptr;
    volatile bool intrStop = false, intrBusy = false;
    uint32_t intrPackets = 0;
    uint8_t *cmd = nullptr, *ev = nullptr;          // control transfer buffers (wired)
    char log[1200] = {0};
    size_t loglen = 0;

    static void worker(void *arg);
    void run();
    void say(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
    void state(const char *s) { setProperty("bt-state", s); }
    IOReturn ctrl(uint8_t type, uint8_t req, uint16_t value, uint16_t index, void *buf, uint16_t len, uint32_t *done);
    bool regRead(uint32_t reg, uint32_t *val);
    bool uhwWrite(uint32_t reg, uint32_t val);
    int wmt(uint8_t op, uint8_t flag, const uint8_t *data, uint16_t dlen, uint8_t *evFlag);
    bool download(uint32_t chipId);
    void intrArm();
    static void intrDone(void *owner, void *param, IOReturn status, uint32_t bytes);
};

OSDefineMetaClassAndStructors(MtkBtFw, IOService)

void MtkBtFw::say(const char *fmt, ...)
{
    char line[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    IOLog("MtkBtFw: %s\n", line);
    size_t n = strlen(line);
    if (loglen + n + 2 >= sizeof(log)) return;      // keep the beginning: that is where things go wrong
    memcpy(log + loglen, line, n);
    loglen += n;
    log[loglen++] = ';';
    log[loglen] = 0;
    setProperty("bt-log", log);
}

IOReturn MtkBtFw::ctrl(uint8_t type, uint8_t req, uint16_t value, uint16_t index, void *buf, uint16_t len, uint32_t *done)
{
    StandardUSB::DeviceRequest r;
    r.bmRequestType = type;
    r.bRequest = req;
    r.wValue = value;
    r.wIndex = index;
    r.wLength = len;
    uint32_t n = 0;
    IOReturn ret = intf->deviceRequest(r, len ? buf : nullptr, n, 1000);
    if (done) *done = n;
    return ret;
}

// btmtk_usb_reg_read: vendor IN, bRequest 0x63
bool MtkBtFw::regRead(uint32_t reg, uint32_t *val)
{
    uint32_t n = 0;
    IOReturn r = ctrl(0xc0, 0x63, (uint16_t)(reg >> 16), (uint16_t)(reg & 0xffff), ev, 4, &n);
    if (r != kIOReturnSuccess || n != 4) { say("reg %08x read failed %08x n=%u", reg, r, n); return false; }
    *val = le32(ev);
    return true;
}

// btmtk_usb_uhw_reg_write: request type 0x5e, bRequest 0x02
bool MtkBtFw::uhwWrite(uint32_t reg, uint32_t val)
{
    cmd[0] = (uint8_t)val; cmd[1] = (uint8_t)(val >> 8); cmd[2] = (uint8_t)(val >> 16); cmd[3] = (uint8_t)(val >> 24);
    IOReturn r = ctrl(0x5e, 0x02, (uint16_t)(reg >> 16), (uint16_t)(reg & 0xffff), cmd, 4, nullptr);
    if (r != kIOReturnSuccess) { say("uhw %08x write failed %08x", reg, r); return false; }
    return true;
}

// One WMT command and its event. Returns 0 and the event's flag byte, or -1.
int MtkBtFw::wmt(uint8_t op, uint8_t flag, const uint8_t *data, uint16_t dlen, uint8_t *evFlag)
{
    uint32_t hlen = 5u + dlen;
    if (hlen > 255) return -1;
    cmd[0] = 0x6f; cmd[1] = 0xfc; cmd[2] = (uint8_t)hlen;           // HCI command 0xfc6f
    cmd[3] = 1; cmd[4] = op; cmd[5] = (uint8_t)(dlen + 1); cmd[6] = (uint8_t)((dlen + 1) >> 8); cmd[7] = flag;
    if (dlen) memcpy(cmd + 8, data, dlen);
    IOReturn r = ctrl(0x20, 0x00, 0, 0, cmd, (uint16_t)(3 + hlen), nullptr);
    if (r != kIOReturnSuccess) { say("wmt op %u send failed %08x", op, r); return -1; }
    for (int i = 0; i < 4000; i++) {                                // ~2 s at 0.5 ms per empty poll
        uint32_t n = 0;
        r = ctrl(0xc0, 0x01, 0x30, 0, ev, 64, &n);
        if (r == kIOReturnSuccess && n >= 7) {
            if (ev[0] != 0xe4 || ev[3] != op) { say("wmt op %u: other event %02x op %u n=%u", op, ev[0], ev[3], n); continue; }
            if (evFlag) *evFlag = ev[6];
            return 0;
        }
        IODelay(500);
    }
    say("wmt op %u flag %u: no event", op, flag);
    return -1;
}

bool MtkBtFw::download(uint32_t chipId)
{
    const uint8_t *fw = chipId == 0x7922 ? mtk_bt_fw_7922 : mtk_bt_fw;
    const uint8_t *end = chipId == 0x7922 ? mtk_bt_fw_7922_end : mtk_bt_fw_end;
    size_t fwlen = (size_t)(end - fw);
    if (fwlen < FW_HDR_SIZE + FW_GD_SIZE) { say("firmware blob too small"); return false; }
    uint32_t nsec = le32(fw + FW_HDR_SIZE + 12);
    char date[17] = {0};
    memcpy(date, fw, 16);
    say("firmware %s, %u sections, %lu bytes", date, nsec, (unsigned long)fwlen);
    if (nsec > 16 || FW_HDR_SIZE + FW_GD_SIZE + (size_t)FW_SEC_MAP_SIZE * nsec > fwlen) { say("bad section count"); return false; }
    for (uint32_t i = 0; i < nsec; i++) {
        const uint8_t *map = fw + FW_HDR_SIZE + FW_GD_SIZE + FW_SEC_MAP_SIZE * i;
        uint32_t off = le32(map + 4), dl = le32(map + 12 + 4);    // secoffset, bin_info_spec.dlsize
        if (!dl) continue;
        if ((size_t)off + dl > fwlen) { say("section %u out of range", i); return false; }
        uint8_t q[1 + SEC_SEND_SIZE];
        q[0] = 0;                                                  // legacy download mode
        memcpy(q + 1, map + SEC_COMMON_SIZE, SEC_SEND_SIZE);
        uint8_t f = 0;
        int tries = 20;
        for (; tries > 0; tries--) {
            if (wmt(WMT_PATCH_DWNLD, 0, q, sizeof(q), &f) < 0) return false;
            if (f == 1) { IOSleep(100); continue; }                // in progress
            break;
        }
        if (!tries) { say("section %u: chip stays busy", i); return false; }
        if (f == 2) { say("section %u: already loaded", i); continue; }
        if (f != 0) { say("section %u: status %u", i, f); return false; }
        const uint8_t *p = fw + off;
        uint32_t left = dl, blocks = 0;
        bool first = true;
        while (left) {
            uint16_t n = (uint16_t)(left > 250 ? 250 : left);
            uint8_t flag = first ? 1 : (left - n == 0 ? 3 : 2);
            first = false;
            if (wmt(WMT_PATCH_DWNLD, flag, p, n, &f) < 0) { say("section %u: block %u failed", i, blocks); return false; }
            if (f == 1) { say("section %u: busy during download", i); return false; }
            p += n;
            left -= n;
            blocks++;
        }
        say("section %u: %u bytes in %u blocks", i, dl, blocks);
    }
    IOSleep(110);                                                  // firmware activation
    return true;
}

void MtkBtFw::intrDone(void *owner, void *, IOReturn status, uint32_t)
{
    MtkBtFw *me = (MtkBtFw *)owner;
    me->intrBusy = false;
    if (status == kIOReturnSuccess) me->intrPackets++;
    if (!me->intrStop && status != kIOReturnAborted && status != kIOReturnNotOpen) me->intrArm();
}

// HCI events the chip also queues on the interrupt endpoint during setup are read and dropped (Linux has its interrupt URB
// running at that time too), so they cannot back up while we poll the control endpoint.
void MtkBtFw::intrArm()
{
    if (!intrPipe || !intrBuf || intrStop) return;
    IOUSBHostCompletion c = { this, intrDone, nullptr };
    intrBusy = true;
    if (intrPipe->io(intrBuf, (uint32_t)intrBuf->getLength(), &c, 0) != kIOReturnSuccess) intrBusy = false;
}

void MtkBtFw::worker(void *arg)
{
    MtkBtFw *me = (MtkBtFw *)arg;
    me->run();
    me->release();
}

void MtkBtFw::run()
{
    uint64_t t0 = 0, t1 = 0;
    clock_get_uptime(&t0);
    state("loading");
    if (!intf->open(this)) { say("interface busy (open failed)"); state("error"); return; }

    // the interrupt IN endpoint of this interface, from the raw configuration descriptor (bLength / bDescriptorType walk)
    const uint8_t *cfg = (const uint8_t *)intf->getConfigurationDescriptor();
    const uint8_t *idesc = (const uint8_t *)intf->getInterfaceDescriptor();
    if (cfg && idesc) {
        uint32_t total = (uint32_t)cfg[2] | (uint32_t)cfg[3] << 8, off = 0;
        bool mine = false;
        while (off + 2 <= total && cfg[off] >= 2 && off + cfg[off] <= total) {
            const uint8_t *d = cfg + off;
            if (d[1] == 4 && d[0] >= 9) mine = d[2] == idesc[2] && d[3] == idesc[3];      // interface: number / alternate
            else if (d[1] == 5 && d[0] >= 7 && mine && (d[3] & 3) == 3 && (d[2] & 0x80)) {  // endpoint: interrupt, IN
                intrPipe = intf->copyPipe(d[2]);
                break;
            }
            off += d[0];
        }
    }
    if (intrPipe) {
        intrBuf = IOBufferMemoryDescriptor::withCapacity(1024, kIODirectionIn);
        intrArm();
    }

    uint32_t devId = 0, fwVer = 0;
    bool ok = regRead(REG_DEV_ID, &devId) && regRead(REG_FW_VER, &fwVer);
    if (ok) say("chip %04x fw_ver %08x", devId & 0xffff, fwVer);
    const uint32_t chipId = devId & 0xffff;
    if (ok && chipId != 0x7925 && chipId != 0x7922) { say("not an MT7925 or MT7922, leaving it alone"); ok = false; }
    // Linux btmtk_fw_get_filename(): MT7922_1_<((fwVer & 0xff) + 1)>_hdr.bin.
    if (ok && chipId == 0x7922 && (fwVer & 0xff) != 0) {
        say("MT7922 needs firmware suffix %x; only _1_1 is embedded", (fwVer & 0xff) + 1);
        ok = false;
    }
    if (ok) ok = download(chipId);
    if (ok) ok = uhwWrite(REG_EP_RST_OPT, EP_RST_IN_OUT_OPT);
    uint8_t on = 1, f = 0;
    if (ok && wmt(WMT_FUNC_CTRL, 0, &on, 1, &f) < 0) ok = false;
    if (ok) say("bluetooth function on (flag %u)", f);

    intrStop = true;
    if (intrPipe) {
        intrPipe->abort(IOUSBHostIOSource::kAbortSynchronous, kIOReturnAborted, this);
        for (int i = 0; i < 100 && intrBusy; i++) IOSleep(10);
        intrPipe->release();
        intrPipe = nullptr;
    }
    intf->close(this);
    clock_get_uptime(&t1);
    uint64_t ns = 0;
    absolutetime_to_nanoseconds(t1 - t0, &ns);
    say("%s in %llu ms, %u interrupt packets dropped", ok ? "ready" : "failed", ns / 1000000ull, intrPackets);
    state(ok ? "ready" : "error");
}

bool MtkBtFw::start(IOService *provider)
{
    if (!IOService::start(provider)) return false;
    intf = OSDynamicCast(IOUSBHostInterface, provider);
    if (!intf) return false;
    cmd = (uint8_t *)IOMalloc(512);
    ev = (uint8_t *)IOMalloc(64);
    if (!cmd || !ev) return false;
    state("starting");
    registerService();
    retain();                                                       // released by the worker
    startThread(worker, this);
    return true;
}

void MtkBtFw::stop(IOService *provider)
{
    intrStop = true;
    IOService::stop(provider);
}

void MtkBtFw::free()
{
    if (intrBuf) intrBuf->release();
    if (cmd) IOFree(cmd, 512);
    if (ev) IOFree(ev, 64);
    IOService::free();
}
