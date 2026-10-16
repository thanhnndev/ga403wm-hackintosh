// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Portions derived from the Linux mt76 driver, Copyright (C) 2020, 2023 MediaTek Inc. (BSD-3-Clause-Clear)
// itlmt7925 - M1: WFDMA rings (polled), MCU command transport, patch + RAM firmware download.
// A line-by-line port of the connac3 path in Linux mt76 (BSD-3-Clause-Clear, Copyright (C) MediaTek Inc.):
//   mt7925/pci.c      mt7925_pci_probe, mt7925_dma_init
//   mt792x_dma.c      mt792x_dma_alloc_queues / _disable / _enable, mt792x_wfsys_reset
//   mt792x_core.c     mt792x_load_firmware, mt792xe_mcu_{fw,drv}_pmctrl
//   mt76_connac_mcu.c patch semaphore, init_download, scatter, start_patch, send_ram_firmware
//   mt7925/mcu.c      mt7925_mcu_fill_message, mt7925_mcu_parse_response
// Runs only with boot-arg itlmt_m1=<seconds to wait first>; progress is logged with m1log() (dmesg + "m1-log"
// registry property) so a stall shows exactly which stage it died in.
#include "itlmt7925.hpp"
#include "mt7925_regs.h"

#include <string.h>
#include <stdarg.h>
#include <libkern/libkern.h>
#include <pexpert/pexpert.h>

extern "C" {
extern const uint8_t itl_fw_patch[], itl_fw_patch_end[];
extern const uint8_t itl_fw_ram[], itl_fw_ram_end[];
}

#define ITL_TIMEOUT -110
#define ITL_EIO     -5
#define ITL_EINVAL  -22

static inline uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static inline uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static inline void put32(uint8_t *p, uint32_t v) { memcpy(p, &v, 4); }
static inline void put16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }
static inline void membar() { __sync_synchronize(); }

// ---------------------------------------------------------------------------------------------
// Register access through the fixed BAR0 windows (+ L1 remap for the rest), like __mt7925_reg_addr()
// ---------------------------------------------------------------------------------------------
uint32_t itlmt7925::mapAddr(uint32_t addr, uint32_t *restoreL1)
{
    *restoreL1 = 0xffffffffu;
    if (addr < MT_BAR0_DIRECT_LIMIT) return addr;

    for (size_t i = 0; i < ITL_FIXED_MAP_N; i++) {
        if (addr < itl_fixed_map[i].phys) continue;
        uint32_t ofs = addr - itl_fixed_map[i].phys;
        if (ofs > itl_fixed_map[i].size) continue;
        return itl_fixed_map[i].maps + ofs;
    }

    if ((addr >= 0x18000000u && addr < 0x18c00000u) || (addr >= 0x70000000u && addr < 0x78000000u) ||
        (addr >= 0x7c000000u && addr < 0x7c400000u)) {
        uint32_t cur = rd(MT_HIF_REMAP_L1);
        wr(MT_HIF_REMAP_L1, (cur & ~MT_HIF_REMAP_L1_MASK) | (addr & MT_HIF_REMAP_L1_MASK));
        (void)rd(MT_HIF_REMAP_L1);                    // read back to push the write
        *restoreL1 = cur;
        return MT_HIF_REMAP_BASE_L1 + (addr & 0xffffu);
    }
    return 0xffffffffu;
}

uint32_t itlmt7925::rdA(uint32_t addr)
{
    uint32_t restore, off = mapAddr(addr, &restore);
    if (off == 0xffffffffu) return 0xffffffffu;
    uint32_t v = rd(off);
    if (restore != 0xffffffffu) wr(MT_HIF_REMAP_L1, restore);
    return v;
}

void itlmt7925::wrA(uint32_t addr, uint32_t val)
{
    uint32_t restore, off = mapAddr(addr, &restore);
    if (off == 0xffffffffu) return;
    wr(off, val);
    if (restore != 0xffffffffu) wr(MT_HIF_REMAP_L1, restore);
}

void itlmt7925::rmwA(uint32_t addr, uint32_t clr, uint32_t set)
{
    wrA(addr, (rdA(addr) & ~clr) | set);
}

bool itlmt7925::pollA(uint32_t addr, uint32_t mask, uint32_t val, uint32_t timeoutMs)
{
    for (uint32_t us = 0; us < timeoutMs * 1000; us += 100) {
        if ((rdA(addr) & mask) == val) return true;
        IODelay(100);
    }
    return (rdA(addr) & mask) == val;
}

void itlmt7925::m1log(const char *fmt, ...)
{
    char tmp[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    IOLog("itlmt7925: M1 %s\n", tmp);
    size_t n = strlen(tmp);
    if (m1len + n + 2 < sizeof(m1buf)) {
        memcpy(m1buf + m1len, tmp, n);
        m1len += n;
        m1buf[m1len++] = ';';
        m1buf[m1len] = 0;
    }
    setProperty("m1-log", m1buf);
}

// ---------------------------------------------------------------------------------------------
// DMA memory + rings
// ---------------------------------------------------------------------------------------------
// Descriptors and MCU buffers stay uncached. Frame buffers (rx data, tx staging) are cached, as Linux's page pool / streaming
// mappings are on x86, where PCIe DMA snoops the CPU caches: copying a frame out of uncached memory costs one bus read per
// word, and every frame is read several times (parse, reorder, copy into an mbuf).
bool itlmt7925::dmaAlloc(itl_dma_buf &b, size_t size, bool cached)
{
    b.md = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
              kIODirectionInOut | kIOMemoryPhysicallyContiguous | (cached ? 0 : kIOMapInhibitCache), size, 0x00000000FFFFF000ULL);
    if (!b.md) return false;
    b.va = (uint8_t *)b.md->getBytesNoCopy();
    b.size = size;
    b.pa = b.md->getPhysicalSegment(0, nullptr, kIOMemoryMapperNone);
    if (!b.va || !b.pa || b.pa + size > 0x100000000ULL) {
        m1log("dmaAlloc: bad mem va=%p pa=%llx size=%lu", b.va, (unsigned long long)b.pa, (unsigned long)size);
        dmaFree(b);
        return false;
    }
    bzero(b.va, size);
    return true;
}

void itlmt7925::dmaFree(itl_dma_buf &b)
{
    if (b.md) { b.md->release(); b.md = nullptr; }
    b.va = nullptr; b.pa = 0; b.size = 0;
}

void itlmt7925::ringFree(itl_ring &r)
{
    dmaFree(r.desc);
    dmaFree(r.buf);
    r.n = 0;
}

bool itlmt7925::ringInit(itl_ring &r, int qid, uint32_t base, int n, bool rx, bool cached)
{
    if (rx && n > (int)(sizeof(r.slotBuf) / sizeof(r.slotBuf[0]))) return false;
    r.n = n;
    r.regs = base + (uint32_t)qid * 0x10u;
    r.head = r.tail = 0;
    if (!dmaAlloc(r.desc, (size_t)n * 16)) return false;
    // txData stages TXD + txp + the whole 802.11 frame in 2 KiB slots (kTxSlots of them); the other tx rings need one 4 KiB buffer
    if (!dmaAlloc(r.buf, rx ? (size_t)n * MT_RX_BUF_SIZE : (&r == &txData ? (size_t)kTxSlots * 2048 : 4096), cached)) return false;

    // mt76_dma_queue_reset(): every descriptor starts out DMA_DONE, indices zero, then ring base/size
    for (int i = 0; i < n; i++) put32(r.desc.va + i * 16 + 4, MT_DMA_CTL_DMA_DONE);
    wr(r.regs + Q_CPU_IDX, 0);
    wr(r.regs + Q_DMA_IDX, 0);
    wr(r.regs + Q_RING_SIZE, (uint32_t)n);
    wr(r.regs + Q_DESC_BASE, (uint32_t)r.desc.pa);

    if (rx) {
        // mt76_dma_rx_fill(): ndesc - 1 buffers, then kick
        for (int i = 0; i < n - 1; i++) {
            uint8_t *d = r.desc.va + i * 16;
            put32(d + 0, (uint32_t)(r.buf.pa + (uint64_t)i * MT_RX_BUF_SIZE));
            put32(d + 4, MT_DMA_CTL_SD_LEN0(MT_RX_BUF_SIZE));
            put32(d + 8, 0);
            put32(d + 12, 0);
            r.slotBuf[i] = (uint16_t)i;
        }
        r.head = n - 1;
        membar();
        wr(r.regs + Q_CPU_IDX, (uint32_t)r.head);
    }
    return true;
}

// mt792x_dma_disable(dev, force = true)
void itlmt7925::dmaDisable()
{
    rmwA(MT_WFDMA0_GLO_CFG, GLO_TX_DMA_EN | GLO_RX_DMA_EN | GLO_CSR_DISP_BASE_PTR_CHAIN_EN | GLO_OMIT_TX_INFO |
                            GLO_OMIT_RX_INFO | GLO_OMIT_RX_INFO_PFET2, 0);
    if (!pollA(MT_WFDMA0_GLO_CFG, GLO_TX_DMA_BUSY | GLO_RX_DMA_BUSY, 0, 100))
        m1log("dma_disable: still busy GLO=%08x", rdA(MT_WFDMA0_GLO_CFG));

    rmwA(MT_WFDMA0_GLO_CFG_EXT0, GLO_EXT0_CSR_TX_DMASHDL_EN, 0);
    rmwA(MT_DMASHDL_SW_CONTROL, 0, MT_DMASHDL_DMASHDL_BYPASS);

    rmwA(MT_WFDMA0_RST, MT_WFDMA0_RST_DMASHDL_ALL_RST | MT_WFDMA0_RST_LOGIC_RST, 0);
    rmwA(MT_WFDMA0_RST, 0, MT_WFDMA0_RST_DMASHDL_ALL_RST | MT_WFDMA0_RST_LOGIC_RST);
}

#define PREFETCH(base, depth) (((uint32_t)(base) << 16) | (depth))

// mt792x_dma_enable() for mt7925 (host IRQs are left off: everything is polled)
void itlmt7925::dmaEnable()
{
    // mt7925_dma_prefetch_setup()
    for (uint32_t i = 0; i < 4; i++) wrA(MT_WFDMA0_RX_RING_EXT_CTRL(i), PREFETCH(0x0000 + 0x40 * i, 0x4));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(0), PREFETCH(0x0100, 0x10));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(1), PREFETCH(0x0200, 0x10));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(2), PREFETCH(0x0300, 0x10));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(3), PREFETCH(0x0400, 0x10));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(15), PREFETCH(0x0500, 0x4));
    wrA(MT_WFDMA0_TX_RING_EXT_CTRL(16), PREFETCH(0x0540, 0x4));

    wrA(MT_WFDMA0_RST_DTX_PTR, 0xffffffffu);
    wrA(MT_WFDMA0_RST_DRX_PTR, 0xffffffffu);
    wrA(MT_WFDMA0_PRI_DLY_INT_CFG0, 0);

    rmwA(MT_WFDMA0_GLO_CFG, 0, GLO_TX_WB_DDONE | GLO_FIFO_LITTLE_ENDIAN | GLO_CLK_GAT_DIS | GLO_OMIT_TX_INFO |
                               GLO_DMA_SIZE_3 | GLO_FIFO_DIS_CHECK | GLO_RX_WB_DDONE |
                               GLO_CSR_DISP_BASE_PTR_CHAIN_EN | GLO_OMIT_RX_INFO_PFET2);
    rmwA(MT_WFDMA0_GLO_CFG, 0, GLO_TX_DMA_EN | GLO_RX_DMA_EN);

    // mt7925_wfdma_setup()
    rmwA(MT_UWFDMA0_GLO_CFG_EXT1, 1u << 28, 1u << 28);
    rmwA(MT_WFDMA0_INT_RX_PRI, 0, 0x0F00);
    rmwA(MT_WFDMA0_INT_TX_PRI, 0, 0x7F00);

    rmwA(MT_WFDMA_DUMMY_CR, 0, MT_WFDMA_NEED_REINIT);
    rmwA(MT_MCU2HOST_SW_INT_ENA, 0, MT_MCU_CMD_WAKE_RX_PCIE);
}

// ---------------------------------------------------------------------------------------------
// MCU transport
// ---------------------------------------------------------------------------------------------
// Copy `len` bytes already placed in r.buf to the ring and wait until the DMA engine consumed them.
bool itlmt7925::txKick(itl_ring &r, size_t len)
{
    uint8_t *d = r.desc.va + r.head * 16;
    put32(d + 0, (uint32_t)r.buf.pa);
    put32(d + 8, 0);
    put32(d + 12, 0);
    put32(d + 4, MT_DMA_CTL_SD_LEN0(len) | MT_DMA_CTL_LAST_SEC0);
    r.head = (r.head + 1) % r.n;
    membar();
    wr(r.regs + Q_CPU_IDX, (uint32_t)r.head);

    for (int us = 0; us < 500000; us += 20) {
        if ((int)(rd(r.regs + Q_DMA_IDX) & 0xffff) == r.head) return true;
        IODelay(20);
    }
    m1log("tx stall: q=%x cpu=%u dma=%u glo=%08x", r.regs, r.head, rd(r.regs + Q_DMA_IDX), rdA(MT_WFDMA0_GLO_CFG));
    return false;
}

// mt7925_mcu_fill_message(): connac2 MCU txd (64 bytes) + payload, sent on the WM ring.
// With wantResp, waits for the event carrying the same sequence number and returns its status byte in *ret.
int itlmt7925::mcuSend(uint8_t cid, const void *payload, size_t plen, bool wantResp, int *ret)
{
    if (64 + plen > 4096) return ITL_EINVAL;
    uint8_t seq = ++mcuSeq & 0xf;
    if (!seq) seq = ++mcuSeq & 0xf;

    uint8_t *p = txWm.buf.va;
    bzero(p, 64);
    uint32_t total = (uint32_t)(64 + plen);
    put32(p + 0, (total & 0xffff) | (2u << 23) | (0x20u << 25));    // TX_BYTES | PKT_FMT=CMD | Q_IDX=RX_Q0
    put32(p + 4, 1u << 16);                                          // HDR_FORMAT = CMD
    put16(p + 32, (uint16_t)(total - 32));                           // len, not counting txd[8]
    put16(p + 34, 0x8000);                                           // MCU_PQ_ID(MT_TX_PORT_IDX_MCU, MT_TX_MCU_PORT_RX_Q0)
    p[36] = cid;
    p[37] = MCU_PKT_ID;
    p[38] = MCU_Q_NA;
    p[39] = seq;
    memcpy(p + 64, payload, plen);

    if (!txKick(txWm, total)) return ITL_TIMEOUT;
    if (!wantResp) return 0;
    return rxWait(seq, ret, 3000);
}

// FW_SCATTER chunks are sent raw, without txd, on the FWDL ring.
int itlmt7925::fwScatter(const uint8_t *data, size_t len)
{
    while (len) {
        size_t cur = len > 4096 ? 4096 : len;
        memcpy(txFwdl.buf.va, data, cur);
        if (!txKick(txFwdl, cur)) return ITL_TIMEOUT;
        data += cur;
        len -= cur;
    }
    return 0;
}

// Poll the event ring for the response with the given sequence number. For the patch semaphore and
// patch finish commands the interesting value is the byte right after the 40 byte rxd header.
int itlmt7925::rxWait(uint8_t seq, int *ret, uint32_t timeoutMs)
{
    itl_ring &r = rxEvt;
    for (uint32_t us = 0; us < timeoutMs * 1000; us += 50) {
        for (;;) {
            uint8_t *d = r.desc.va + r.tail * 16;
            uint32_t ctrl = le32(d + 4);
            if (!(ctrl & MT_DMA_CTL_DMA_DONE)) break;

            uint32_t len = (ctrl >> 16) & 0x3fff;
            int bi = r.slotBuf[r.tail];
            const uint8_t *ev = r.buf.va + (size_t)bi * MT_RX_BUF_SIZE;
            bool match = len >= 44 && ev[37] == seq;
            if (match && ret) *ret = ev[40];
            if (len >= 44)
                m1log("ev slot=%d len=%u eid=%02x seq=%u ext=%02x b40=%02x%s", r.tail, len, ev[36], ev[37], ev[40],
                      ev[40], match ? " <match" : "");
            else
                m1log("ev slot=%d len=%u (short)", r.tail, len);

            // refill: the buffer that was in `tail` goes to the slot at `head`
            uint8_t *nd = r.desc.va + r.head * 16;
            put32(nd + 0, (uint32_t)(r.buf.pa + (uint64_t)bi * MT_RX_BUF_SIZE));
            put32(nd + 8, 0);
            put32(nd + 12, 0);
            put32(nd + 4, MT_DMA_CTL_SD_LEN0(MT_RX_BUF_SIZE));
            r.slotBuf[r.head] = (uint16_t)bi;
            r.head = (r.head + 1) % r.n;
            r.tail = (r.tail + 1) % r.n;
            membar();
            wr(r.regs + Q_CPU_IDX, (uint32_t)r.head);

            if (match) return 0;
        }
        IODelay(50);
    }
    m1log("no response for seq=%u (rx dma=%u cpu=%u tail=%d)", seq, rd(r.regs + Q_DMA_IDX), rd(r.regs + Q_CPU_IDX), r.tail);
    return ITL_TIMEOUT;
}

int itlmt7925::initDownload(uint32_t addr, uint32_t len, uint32_t mode)
{
    uint8_t req[12];
    put32(req + 0, addr);
    put32(req + 4, len);
    put32(req + 8, mode);
    bool patchCmd = addr == 0x200000u || addr == 0x900000u || addr == 0xe0002800u;
    return mcuSend(patchCmd ? MCU_CMD_PATCH_START_REQ : MCU_CMD_TARGET_ADDRESS_LEN_REQ, req, sizeof(req), true, nullptr);
}

// mt76_connac2_load_patch()
int itlmt7925::loadPatch()
{
    const uint8_t *fw = itl_fw_patch;
    size_t fwlen = (size_t)(itl_fw_patch_end - itl_fw_patch);
    if (fwlen < PATCH_HDR_SIZE) return ITL_EINVAL;
    m1log("patch: %.16s size=%lu", (const char *)fw, (unsigned long)fwlen);

    uint8_t op[4];
    int sem = -1;
    put32(op, PATCH_SEM_GET);
    int rc = mcuSend(MCU_CMD_PATCH_SEM_CONTROL, op, 4, true, &sem);
    if (rc) { m1log("patch sem get failed rc=%d", rc); return rc; }
    m1log("patch sem=%d", sem);
    if (sem == PATCH_IS_DL) { m1log("patch already downloaded"); return 0; }
    if (sem != PATCH_NOT_DL_SEM_SUCCESS) return ITL_EIO;

    int ret = 0;
    uint32_t nreg = be32(fw + 32 + 12);
    for (uint32_t i = 0; i < nreg && !ret; i++) {
        const uint8_t *sec = fw + PATCH_HDR_SIZE + i * PATCH_SEC_SIZE;
        if ((be32(sec) & PATCH_SEC_TYPE_MASK) != PATCH_SEC_TYPE_INFO) { ret = ITL_EINVAL; break; }
        uint32_t offs = be32(sec + 4), addr = be32(sec + 12), len = be32(sec + 16), info = be32(sec + 20);
        if ((size_t)offs + len > fwlen) { ret = ITL_EINVAL; break; }

        // mt76_connac2_get_data_mode()
        uint32_t mode = DL_MODE_NEED_RSP;
        if (info != PATCH_SEC_NOT_SUPPORT) {
            switch (info >> 24) {
            case 0: break;
            case 1: mode |= DL_MODE_ENCRYPT | ((info & 0xff) << 1 & 0x6) | DL_MODE_RESET_SEC_IV; break;
            case 2: mode |= DL_MODE_ENCRYPT | DL_CONFIG_ENCRY_MODE_SEL | DL_MODE_RESET_SEC_IV; break;
            default: m1log("patch: unknown enc type");
            }
        }
        m1log("patch sec %u addr=%x len=%u mode=%08x", i, addr, len, mode);
        ret = initDownload(addr, len, mode);
        if (ret) { m1log("patch init_download failed rc=%d", ret); break; }
        ret = fwScatter(fw + offs, len);
        if (ret) { m1log("patch scatter failed rc=%d", ret); break; }
    }

    if (!ret) {
        uint8_t fin[4] = {0, 0, 0, 0};                          // check_crc = 0
        int fr = -1;
        ret = mcuSend(MCU_CMD_PATCH_FINISH_REQ, fin, 4, true, &fr);
        m1log("patch finish rc=%d status=%d", ret, fr);
    }

    put32(op, PATCH_SEM_RELEASE);
    int rel = -1;
    int rr = mcuSend(MCU_CMD_PATCH_SEM_CONTROL, op, 4, true, &rel);
    m1log("patch sem release rc=%d status=%d", rr, rel);
    if (!ret && (rr || rel != PATCH_REL_SEM_SUCCESS)) ret = ITL_EIO;
    return ret;
}

// mt76_connac_mcu_send_ram_firmware(is_wa = false)
int itlmt7925::loadRam()
{
    const uint8_t *fw = itl_fw_ram;
    size_t fwlen = (size_t)(itl_fw_ram_end - itl_fw_ram);
    if (fwlen < FW_TRAILER_SIZE) return ITL_EINVAL;
    const uint8_t *tr = fw + fwlen - FW_TRAILER_SIZE;
    uint32_t nreg = tr[2];
    m1log("ram: ver=%.10s built=%.15s regions=%u size=%lu", (const char *)tr + 7, (const char *)tr + 17, nreg,
          (unsigned long)fwlen);
    if (nreg * FW_REGION_SIZE + FW_TRAILER_SIZE > fwlen) return ITL_EINVAL;

    size_t offset = 0;
    uint32_t override = 0;
    for (uint32_t i = 0; i < nreg; i++) {
        const uint8_t *rg = tr - (nreg - i) * FW_REGION_SIZE;
        uint32_t addr = le32(rg + 16), len = le32(rg + 20);
        uint8_t feat = rg[24];
        uint32_t mode = DL_MODE_NEED_RSP;
        if (feat & FW_FEATURE_SET_ENCRYPT) mode |= DL_MODE_ENCRYPT | DL_MODE_RESET_SEC_IV;
        if (feat & FW_FEATURE_ENCRY_MODE) mode |= DL_CONFIG_ENCRY_MODE_SEL;
        mode |= ((uint32_t)(feat >> 1) & 0x3) << 1;                      // key idx

        if (!(feat & FW_FEATURE_NON_DL)) {
            if (offset + len > fwlen) return ITL_EINVAL;
            if (feat & FW_FEATURE_OVERRIDE_ADDR) override = addr;
            m1log("ram region %u addr=%x len=%u feat=%02x mode=%08x", i, addr, len, feat, mode);
            int rc = initDownload(addr, len, mode);
            if (rc) { m1log("ram init_download failed rc=%d", rc); return rc; }
            rc = fwScatter(fw + offset, len);
            if (rc) { m1log("ram scatter failed rc=%d", rc); return rc; }
        }
        offset += len;
    }

    uint8_t req[8];
    put32(req + 0, override ? FW_START_OVERRIDE : 0);
    put32(req + 4, override);
    int rc = mcuSend(MCU_CMD_FW_START_REQ, req, sizeof(req), true, nullptr);
    m1log("fw start rc=%d override=%x", rc, override);
    return rc;
}

// ---------------------------------------------------------------------------------------------
// Bring-up sequence
// ---------------------------------------------------------------------------------------------
int itlmt7925::m1Run()
{
    int rc;
    uint32_t chip = rdA(MT_HW_CHIPID), rev = rdA(MT_HW_REV);
    m1log("chip=%08x rev=%08x lp=%08x misc=%08x", chip, rev, rdA(MT_CONN_ON_LPCTL), rdA(MT_CONN_ON_MISC));
    if ((chip & 0xffff) != 0x7925) { m1log("not an MT7925, abort"); return ITL_EIO; }

    pci->setBusMasterEnable(true);
    m1log("stage 1: bus master on, cmd=%04x", pci->configRead16(kIOPCIConfigCommand));

    rmwA(MT_HW_EMI_CTL, MT_HW_EMI_CTL_SLPPROT_EN, MT_HW_EMI_CTL_SLPPROT_EN);

    // mt792x_wfsys_reset_default()
    rmwA(MT_WFSYS_SW_RST_B, WFSYS_SW_RST_B, 0);
    IOSleep(50);
    rmwA(MT_WFSYS_SW_RST_B, 0, WFSYS_SW_RST_B);
    if (!pollA(MT_WFSYS_SW_RST_B, WFSYS_SW_INIT_DONE, WFSYS_SW_INIT_DONE, 500)) {
        m1log("wfsys reset timeout, rst=%08x", rdA(MT_WFSYS_SW_RST_B));
        return ITL_TIMEOUT;
    }
    m1log("stage 2: wfsys reset ok");

    wrA(MT_WFDMA0_HOST_INT_ENA, 0);
    wrA(MT7925_PCIE_MAC_INT_ENABLE, 0xff);

    dmaDisable();
    m1log("stage 3: dma disabled glo=%08x", rdA(MT_WFDMA0_GLO_CFG));

    // ring sizes as Linux (MT7925_RX_MCU_RING_SIZE 512, MT7925_RX_RING_SIZE 1536): an HE A-MPDU of 64 MPDUs carrying A-MSDUs
    // is 200+ ring entries (the hardware de-aggregates), so 256 entries overflowed on every burst the thread was late for and
    // the AP had to send the lost MPDUs again (6.5 % of the received frames were such retransmissions at 3.5 MB/s)
    if (!ringInit(txWm, MT7925_TXQ_MCU_WM, MT_TX_RING_BASE, 256, false) ||
        !ringInit(txFwdl, MT7925_TXQ_FWDL, MT_TX_RING_BASE, 128, false) ||
        !ringInit(rxEvt, MT7925_RXQ_MCU_WM, MT_RX_EVENT_RING_BASE, 512, true) ||
        (m3On && !ringInit(txData, MT7925_TXQ_BAND0, MT_TX_RING_BASE, 256, false, true))) {
        m1log("ring alloc failed");
        return ITL_EIO;
    }
    if (m2On) {
        static const int sizes[] = {1536, 512, 256};
        bool ok = false;
        for (int i = fastLevel >= 2 ? 0 : 2; i < 3 && !ok; i++) {
            ok = ringInit(rxData, MT7925_RXQ_BAND0, MT_RX_DATA_RING_BASE, sizes[i], true, true);
            if (!ok) ringFree(rxData);
        }
        if (!ok) { m1log("rx data ring alloc failed"); return ITL_EIO; }
        m1log("rx data ring %d entries", rxData.n);
    }
    m1log("stage 4: rings txwm=%llx txfwdl=%llx rx=%llx", (unsigned long long)txWm.desc.pa,
          (unsigned long long)txFwdl.desc.pa, (unsigned long long)rxEvt.desc.pa);

    dmaEnable();
    m1log("stage 5: dma enabled glo=%08x", rdA(MT_WFDMA0_GLO_CFG));

    // mt7925e_mcu_init(): fw_pmctrl, drv_pmctrl, disable L0s, run firmware
    for (int i = 0; i < 10; i++) {
        wrA(MT_CONN_ON_LPCTL, PCIE_LPCR_HOST_SET_OWN);
        if (pollA(MT_CONN_ON_LPCTL, PCIE_LPCR_HOST_OWN_SYNC, 4, 50)) break;
    }
    if (!driverOwn()) { m1log("drv_pmctrl failed lp=%08x", rdA(MT_CONN_ON_LPCTL)); return ITL_TIMEOUT; }
    rmwA(MT7925_PCIE_MAC_PM, 0, MT_PCIE_MAC_PM_L0S_DIS);
    m1log("stage 6: own ok lp=%08x misc=%08x", rdA(MT_CONN_ON_LPCTL), rdA(MT_CONN_ON_MISC));

    // mt792x_load_firmware()
    uint8_t pwr[4] = {1, 0, 0, 0};                                // mt76_connac_mcu_restart(): power_mode = 1
    rc = mcuSend(MCU_CMD_NIC_POWER_CTRL, pwr, 4, false, nullptr);
    m1log("nic power ctrl rc=%d", rc);
    if (!pollA(MT_CONN_ON_MISC, MT_TOP_MISC_FW_STATE_MASK, MT_TOP_MISC2_FW_PWR_ON, 1000))
        m1log("MCU is not ready for firmware download, misc=%08x", rdA(MT_CONN_ON_MISC));

    rc = loadPatch();
    m1log("stage 7: patch rc=%d misc=%08x", rc, rdA(MT_CONN_ON_MISC));
    if (rc) return rc;

    rc = loadRam();
    m1log("stage 8: ram rc=%d misc=%08x", rc, rdA(MT_CONN_ON_MISC));
    if (rc) return rc;

    if (!pollA(MT_CONN_ON_MISC, MT_TOP_MISC2_FW_N9_RDY, MT_TOP_MISC2_FW_N9_RDY, 1500)) {
        m1log("firmware init timeout, misc=%08x", rdA(MT_CONN_ON_MISC));
        return ITL_TIMEOUT;
    }
    m1log("stage 9: FIRMWARE READY misc=%08x", rdA(MT_CONN_ON_MISC));
    return 0;
}

void itlmt7925::m1Main()
{
    uint32_t delay = 0, m2 = 0, m3 = 0;
    PE_parse_boot_argn("itlmt_m1", &delay, sizeof(delay));
    if (PE_parse_boot_argn("itlmt_m2", &m2, sizeof(m2)) && m2) m2On = true;
    if (PE_parse_boot_argn("itlmt_m3", &m3, sizeof(m3)) && m3) m3On = m2On = true;
    if (nativeMode) {
        m3On = m2On = true;
        m1log("native datapath radio engine enabled; legacy Ethernet disabled");
    }
    uint32_t reo = 0;
    if (PE_parse_boot_argn("itlmt_reo", &reo, sizeof(reo)) && reo >= 5 && reo <= 500) reoMs = reo;
    uint32_t no160 = 0;
    if (PE_parse_boot_argn("itlmt_no160", &no160, sizeof(no160)) && no160) this->no160 = true;
    uint32_t nopwr = 0, statS = 0;
    if (PE_parse_boot_argn("itlmt_nopwr", &nopwr, sizeof(nopwr)) && nopwr) noPwr = true;
    uint32_t amsduOn = 0;
    if (PE_parse_boot_argn("itlmt_amsdu", &amsduOn, sizeof(amsduOn)) && amsduOn) noAmsdu = false;
    if (PE_parse_boot_argn("itlmt_stat", &statS, sizeof(statS)) && statS >= 1 && statS <= 60) statSecs = statS;
    uint32_t fast = 0;
    if (PE_parse_boot_argn("itlmt_fast", &fast, sizeof(fast)) && fast) {
        m3fast = true;
        fastLevel = fast > 6 ? 6 : (uint8_t)fast;
    }
    // Start when the kernel is ready instead of after a fixed sleep: the IOBSD resource is published once the root
    // filesystem is mounted, i.e. early boot (PCI enumeration, the GPU bring-up) is behind us. The firmware is embedded,
    // so nothing else has to exist. itlmt_m1=<s> is an extra delay after that point (0 = none; the old default was 75 s
    // from kext start).
    uint32_t t0 = nowMs();
    OSDictionary *match = IOService::resourceMatching("IOBSD");
    IOService *bsd = match ? IOService::waitForMatchingService(match, 120ull * 1000 * 1000 * 1000) : nullptr;
    if (match) match->release();
    if (bsd) bsd->release();
    m1log("armed: system ready after %ums (%s), extra delay %us", nowMs() - t0, bsd ? "IOBSD" : "IOBSD wait timed out", delay);
    if (delay) IOSleep(delay * 1000);
    int rc = m1Run();
    m1log("RESULT rc=%d", rc);
    char s[48];
    snprintf(s, sizeof(s), "M1 rc=%d", rc);
    nvramLog(s);
    if (rc != 0) publishService();                           // no firmware: the (radio-less) interface still has to exist
    if (rc == 0 && m2On) {
        int r2 = m2Run();
        m2log("RESULT rc=%d", r2);
        snprintf(s, sizeof(s), "M1 rc=0 M2 rc=%d", r2);
        nvramLog(s);
        publishService();                                    // normally done by m2Run() right after the address is read
        if (m3On) m3Supervise();                             // connects, reconnects and takes user-client commands; never returns
    }
    publishService();
}

void itlmt7925::m1Thread(void *arg)
{
    ((itlmt7925 *)arg)->m1Main();
}
