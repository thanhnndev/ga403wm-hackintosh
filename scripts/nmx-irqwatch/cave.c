// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step97: lost-interrupt watch for NMXGPU (H2). On some boots the GPU's interrupts stop about 1 s after NMXGPU loads
// (nmx_irq_dispatched frozen, every fence completes only through amdgpu's 0.5 s fallback timer, WindowServer's 5 s
// fence waits time out and it crash-loops). This cave:
//   - counts real interrupt-handler runs and serializes amdgpu_ih_process on the main IH ring (hook in
//     amdgpu_irq_handler), so the IH ring can also be processed from elsewhere;
//   - detects the loss in the fallback timer callback: two timer-completed fallbacks in a row with
//     nmx_irq_dispatched unchanged between them;
//   - logs the evidence once per episode (IH registers, the IH ring's software state, the wptr write-back word before
//     and after a cache flush, PCI command/status, MSI/MSI-X control, every IOInterruptEventSource's counters);
//   - degraded mode: every fence fallback timer is armed for 2 ms instead of 500 ms, and each expiry polls the IH ring
//     (through the same guard) and re-arms while the ring has unsignalled fences; the per-expiry warnings are not
//     printed while degraded. It leaves degraded mode as soon as an IH entry is dispatched from the real handler.
// On a healthy boot the fallback path costs one compare, the timer arm one compare, the handler one plain
// increment plus the guard (one lock xadd and one lock cmpxchg).
typedef unsigned long u64; typedef unsigned int u32; typedef unsigned short u16; typedef unsigned char u8;

#pragma GCC visibility push(hidden)
extern int SNPRINTF(char *buf, u64 n, const char *fmt, ...);
extern int PRINTF(const char *fmt, ...);
extern const char FMT_S[];
extern volatile u64 ST[];                // borrowed: ci_init_smc_table.__ratelimited.15 .. .43 (CI dpm only), 30 words
extern volatile u64 IRQS;                // nmx_irq_dispatched (incremented per IV in amdgpu_irq_dispatch)
extern const int HZ;                     // hz (1000)
extern char *const INTRS;                // nmx_bus.c 'intrs' TAILQ head (first entry)
extern _Bool FENCE_PROCESS(char *ring);
extern int IH_PROCESS(char *adev, char *ih);
extern int MOD_TIMER(void *timer, u64 expires);
extern u64 JIFFIES(void);
extern u32 RREG(char *adev, u32 reg, u32 acc_flags);
extern u32 PCI_READ(void *dev, int reg, int width);
extern int PCI_FIND_CAP(void *dev, int cap, int *off);
#pragma GCC visibility pop

// state words (ST[]), all zero at load
enum { DEGR, FBIRQ, HCALLS, REQ, HDISP, PDISP, EPIS, POLLS, ENTER_J, HDISP_AT, HCALLS_AT, PDISP_AT, POLLS_AT, FBDONE,
       FBDONE_AT, STATLINES, NSTATE };
_Static_assert(NSTATE <= 30, "state words");

// offsets in this build (see docs/890M-TRACE.md Step97)
#define ADEV_PDEV        0x8       // struct pci_dev *
#define ADEV_SHUTDOWN    0xa48
#define ADEV_IRQ_INST    0x15830
#define ADEV_IRQ_NUM     0x15834
#define ADEV_MSI_EN      0x15968
#define ADEV_IH          0x15970   // adev->irq.ih (ring 0)
#define PDEV_BSDDEV      0x18
#define PDEV_IRQ         0x14c
#define PDEV_MSI_EN      0x15d
#define IH_RING_SIZE     0x0
#define IH_PTR_MASK      0x4
#define IH_DOORBELL_IDX  0x8
#define IH_USE_DOORBELL  0xc
#define IH_USE_BUS_ADDR  0xd
#define IH_RING          0x18
#define IH_WPTR_CPU      0x30
#define IH_RPTR_CPU      0x40
#define IH_ENABLED       0x48
#define IH_RPTR          0x4c
#define IH_REG_CNTL      0x58
#define IH_REG_WPTR      0x5c
#define IH_REG_RPTR      0x60
#define RING_SYNC_SEQ    0x20
#define RING_LAST_SEQ    0x24
#define RING_TIMER       0x40
#define RING_NAME        0x3a8
#define INTR_RES         0x0       // struct nmx_intr
#define INTR_XCOOKIE     0x20
#define INTR_NEXT        0x28
#define RES_IRQNO        0x38      // struct resource
#define NMXIRQ_ES        0x18      // NMXIrq: OSObject, wl, es, handler, arg
#define IES_ENABLED      0x28      // IOInterruptEventSource (macOS 26 SDK layout)
#define IES_INTINDEX     0x50
#define IES_PRODUCER     0x54
#define IES_CONSUMER     0x58
#define IES_AUTODIS      0x5c
#define IES_EXPLDIS      0x5d

#define U8(p, o)  (*(volatile u8 *)((char *)(p) + (o)))
#define U32(p, o) (*(volatile u32 *)((char *)(p) + (o)))
#define PTR(p, o) (*(char *volatile *)((char *)(p) + (o)))

static u64 poll_ticks(void) { int t = HZ / 500; return t > 0 ? (u64)t : 1; }

static void say(const char *s) { PRINTF(FMT_S, s); }

// ---- the guard: amdgpu_ih_process on ring 0 never runs twice at once. A caller that finds it busy leaves its work
// to the running owner, which processes again before it lets go. Nobody waits or spins.
static int ih_run(char *adev, char *ih, int credit)
{
    if (__atomic_fetch_add(&ST[REQ], 1, __ATOMIC_ACQ_REL) != 0)
        return 1;
    int r;
    for (;;) {
        u64 n = __atomic_load_n(&ST[REQ], __ATOMIC_ACQUIRE);
        u64 d0 = IRQS;
        r = IH_PROCESS(adev, ih);
        ST[credit] += IRQS - d0;
        if (__atomic_compare_exchange_n(&ST[REQ], &n, 0, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            break;
    }
    return r;
}

// amdgpu_irq_handler's call of amdgpu_ih_process (interrupt work-loop thread, one per vector)
int ih_guarded(char *adev, char *ih)
{
    ST[HCALLS]++;
    return ih_run(adev, ih, HDISP);
}

// the three call sites that arm a fence fallback timer (enable_signaling x2, fence_process)
int fb_arm(void *timer, u64 expires)
{
    if (__builtin_expect(!ST[DEGR], 1))
        return MOD_TIMER(timer, expires);
    return MOD_TIMER(timer, JIFFIES() + poll_ticks());
}

// ---- evidence
static const u16 ih_regs[] = { 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0xa5, 0xa8, 0xa9, 0xac, 0xad, 0xc1,
                               0xc2, 0xd5, 0xd9, 0xdc, 0xe4, 0xe5, 0xe6, 0xf1, 0x184, 0x18d, 0x18f };
static const char ih_names[][14] = { "RB_CNTL", "RB_RPTR", "RB_WPTR", "RB_BASE", "RB_BASE_HI", "WPTR_ADDR_HI",
                                     "WPTR_ADDR_LO", "DOORBELL_RPTR", "VERSION", "CNTL", "CLK_CTRL", "RETRY_CAM",
                                     "MEM_POWER", "CNTL2", "STATUS", "FLOOD_CNTL", "FLOOD_STATUS", "INT_FLAGS",
                                     "COOKIE_VIOL", "CREDIT_STATUS", "MMHUB_ERROR", "MSI_STORM", "CLIENT_CFG",
                                     "CHICKEN", "INT_DROP_CNTL" };
_Static_assert(sizeof ih_regs / sizeof ih_regs[0] == sizeof ih_names / sizeof ih_names[0], "names");

static void clflush(volatile void *p) { __asm__ volatile("clflush (%0)\n\tmfence" : : "r"(p) : "memory"); }

// the OSSSYS base the IH register fields were built from (all IH registers have BASE_IDX 0); 0 if they look wrong
static u32 ih_base(char *ih)
{
    u32 cntl = U32(ih, IH_REG_CNTL);
    if (cntl < 0x80 || U32(ih, IH_REG_RPTR) != cntl + 1 || U32(ih, IH_REG_WPTR) != cntl + 2)
        return 0;
    return cntl - 0x80;
}

static void dump_intrs(void)
{
    char s[200];
    int i = 0;
    for (char *in = INTRS; in && i < 4; in = PTR(in, INTR_NEXT), i++) {
        char *res = PTR(in, INTR_RES), *irq = PTR(in, INTR_XCOOKIE);
        char *es = irq ? PTR(irq, NMXIRQ_ES) : 0;
        if (!es) {
            SNPRINTF(s, sizeof s, "NMX irqwatch: intr %d irqno %d cookie %p no event source", i,
                     res ? (int)U32(res, RES_IRQNO) : -1, irq);
        } else {
            SNPRINTF(s, sizeof s, "NMX irqwatch: intr %d irqno %d index %d es enabled %d produced %u consumed %u "
                     "autodisable %d explicitdisable %d", i, res ? (int)U32(res, RES_IRQNO) : -1,
                     (int)U32(es, IES_INTINDEX), U8(es, IES_ENABLED), U32(es, IES_PRODUCER), U32(es, IES_CONSUMER),
                     U8(es, IES_AUTODIS), U8(es, IES_EXPLDIS));
        }
        say(s);
    }
}

static void dump(char *ring, char *adev, char *ih)
{
    char s[256];
    SNPRINTF(s, sizeof s, "NMX irqwatch: LOST interrupts, episode %llu, ring %s last_seq %u sync_seq %u, dispatched "
             "%llu, handler runs %llu, jiffies %llu", ST[EPIS], ring + RING_NAME, U32(ring, RING_LAST_SEQ),
             U32(ring, RING_SYNC_SEQ), IRQS, ST[HCALLS], ST[ENTER_J]);
    say(s);

    volatile u32 *wp = (volatile u32 *)PTR(ih, IH_WPTR_CPU), *rp = (volatile u32 *)PTR(ih, IH_RPTR_CPU);
    u32 w0 = wp ? *wp : 0xdeadbeef, w1 = 0xdeadbeef;
    if (wp) { clflush(wp); w1 = *wp; }
    u32 rptr = U32(ih, IH_RPTR), mask = U32(ih, IH_PTR_MASK);
    SNPRINTF(s, sizeof s, "NMX irqwatch: ih enabled %d rptr %#x mask %#x size %#x doorbell %d idx %#x bus_addr %d "
             "wptr_wb %#x flushed %#x rptr_wb %#x irq installed %d num %d msi %d", U8(ih, IH_ENABLED), rptr, mask,
             U32(ih, IH_RING_SIZE), U8(ih, IH_USE_DOORBELL), U32(ih, IH_DOORBELL_IDX), U8(ih, IH_USE_BUS_ADDR), w0,
             w1, rp ? *rp : 0xdeadbeef, U8(adev, ADEV_IRQ_INST), (int)U32(adev, ADEV_IRQ_NUM), U8(adev, ADEV_MSI_EN));
    say(s);

    char *ringp = PTR(ih, IH_RING);
    if (ringp && mask) {
        volatile u32 *iv = (volatile u32 *)(ringp + (rptr & mask & ~3u));
        clflush(iv);
        SNPRINTF(s, sizeof s, "NMX irqwatch: IV at rptr %08x %08x %08x %08x %08x %08x %08x %08x", iv[0], iv[1], iv[2],
                 iv[3], iv[4], iv[5], iv[6], iv[7]);
        say(s);
    }

    u32 base = ih_base(ih);
    if (base) {
        unsigned n = sizeof ih_regs / sizeof ih_regs[0];
        for (unsigned i = 0; i < n;) {
            int len = SNPRINTF(s, sizeof s, "NMX irqwatch: IH@%#x", base);
            for (unsigned k = 0; k < 7 && i < n; k++, i++)
                if (len > 0 && len < (int)sizeof s - 24)
                    len += SNPRINTF(s + len, sizeof s - len, " %s=%#x", ih_names[i], RREG(adev, base + ih_regs[i], 2));
            say(s);
        }
    } else {
        SNPRINTF(s, sizeof s, "NMX irqwatch: IH register fields look wrong (cntl %#x rptr %#x wptr %#x), no dump",
                 U32(ih, IH_REG_CNTL), U32(ih, IH_REG_RPTR), U32(ih, IH_REG_WPTR));
        say(s);
    }

    char *pdev = PTR(adev, ADEV_PDEV);
    void *dev = pdev ? PTR(pdev, PDEV_BSDDEV) : 0;
    if (dev) {
        int msi = 0, msix = 0;
        u32 mctl = 0, mlo = 0, mhi = 0, mdata = 0, xctl = 0;
        if (PCI_FIND_CAP(dev, 0x05, &msi) == 0 && msi) {
            mctl = PCI_READ(dev, msi + 2, 2);
            mlo = PCI_READ(dev, msi + 4, 4);
            if (mctl & 0x80) { mhi = PCI_READ(dev, msi + 8, 4); mdata = PCI_READ(dev, msi + 12, 2); }
            else mdata = PCI_READ(dev, msi + 8, 2);
        } else msi = 0;
        if (PCI_FIND_CAP(dev, 0x11, &msix) == 0 && msix) xctl = PCI_READ(dev, msix + 2, 2);
        else msix = 0;
        SNPRINTF(s, sizeof s, "NMX irqwatch: PCI cmd %#x status %#x MSI@%#x ctrl %#x addr %#x:%#x data %#x MSI-X@%#x "
                 "ctrl %#x pdev irq %d msi_enabled %d", PCI_READ(dev, 4, 2), PCI_READ(dev, 6, 2), msi, mctl, mhi, mlo,
                 mdata, msix, xctl, (int)U32(pdev, PDEV_IRQ), U8(pdev, PDEV_MSI_EN));
        say(s);
    }
    dump_intrs();
}

static void status(char *adev, char *ih, const char *what)
{
    char s[256];
    u32 base = ih_base(ih);
    volatile u32 *wp = (volatile u32 *)PTR(ih, IH_WPTR_CPU);
    SNPRINTF(s, sizeof s, "NMX irqwatch: %s: %llu ms, polls %llu, poll-dispatched %llu, irq-dispatched %llu, handler "
             "runs %llu, timer completions %llu; IH rptr %#x wptr_wb %#x RB_RPTR %#x RB_WPTR %#x STATUS %#x", what,
             (JIFFIES() - ST[ENTER_J]) * 1000 / (u64)(HZ > 0 ? HZ : 1000), ST[POLLS] - ST[POLLS_AT],
             ST[PDISP] - ST[PDISP_AT], ST[HDISP] - ST[HDISP_AT], ST[HCALLS] - ST[HCALLS_AT], ST[FBDONE] - ST[FBDONE_AT],
             U32(ih, IH_RPTR), wp ? *wp : 0xdeadbeef, base ? RREG(adev, base + 0x81, 2) : 0,
             base ? RREG(adev, base + 0x82, 2) : 0, base ? RREG(adev, base + 0xc2, 2) : 0);
    say(s);
}

static void enter(char *ring, char *adev, char *ih)
{
    ST[EPIS]++;
    ST[ENTER_J] = JIFFIES();
    ST[HDISP_AT] = ST[HDISP];
    ST[HCALLS_AT] = ST[HCALLS];
    ST[PDISP_AT] = ST[PDISP];
    ST[POLLS_AT] = ST[POLLS];
    ST[FBDONE_AT] = ST[FBDONE];
    __atomic_store_n(&ST[DEGR], 1, __ATOMIC_RELEASE);
    if (ST[EPIS] <= 4)
        dump(ring, adev, ih);
    if (ST[EPIS] <= 16) {
        char s[160];
        SNPRINTF(s, sizeof s, "NMX irqwatch: degraded mode ON (episode %llu): fence fallback every %llu ms, IH ring "
                 "polled from the timer", ST[EPIS], poll_ticks() * 1000 / (u64)(HZ > 0 ? HZ : 1000));
        say(s);
    }
}

static void leave(char *adev, char *ih)
{
    __atomic_store_n(&ST[DEGR], 0, __ATOMIC_RELEASE);
    if (ST[EPIS] <= 16)
        status(adev, ih, "interrupts back, degraded mode OFF");
    if (ST[EPIS] <= 4)
        dump_intrs();
}

static _Bool poll(char *ring, _Bool done)
{
    char *adev = PTR(ring, 0), *ih = adev + ADEV_IH;
    ST[POLLS]++;
    if (done)
        ST[FBDONE]++;
    if (ST[HDISP] != ST[HDISP_AT]) {             // the real handler dispatched an IV: interrupts work again
        leave(adev, ih);
        return 0;
    }
    if ((U8(adev, ADEV_SHUTDOWN) & 1) || !(U8(ih, IH_ENABLED) & 1))
        return 0;                                // tearing down or IH off: no poll, no re-arm
    volatile u32 *wp = (volatile u32 *)PTR(ih, IH_WPTR_CPU);
    if (wp)
        clflush(wp);                             // the write-back word may be stale in the CPU cache (H1 for the IH)
    ih_run(adev, ih, PDISP);
    if (((ST[POLLS] - ST[POLLS_AT]) & 2047) == 0 && ST[STATLINES] < 32) {
        ST[STATLINES]++;
        status(adev, ih, "still degraded");
        if (ST[STATLINES] <= 4)
            dump_intrs();
    }
    if (U32(ring, RING_LAST_SEQ) != U32(ring, RING_SYNC_SEQ))
        MOD_TIMER(ring + RING_TIMER, JIFFIES() + poll_ticks());
    return 0;                                    // no per-expiry "Fence fallback timer expired" while degraded
}

// amdgpu_fence_fallback's call of amdgpu_fence_process (nmx softclock thread; all callouts run on it, one at a time)
_Bool fb_process(char *ring)
{
    _Bool r = FENCE_PROCESS(ring);
    if (__builtin_expect(!ST[DEGR], 1)) {
        if (!r)
            return r;
        u64 irqs = IRQS;
        if (irqs != ST[FBIRQ]) {
            ST[FBIRQ] = irqs;
            return r;
        }
        char *adev = PTR(ring, 0);
        if (!(U8(adev, ADEV_IRQ_INST) & 1) || !(U8(adev + ADEV_IH, IH_ENABLED) & 1))
            return r;                            // interrupts not set up yet (early init): not a loss
        enter(ring, adev, adev + ADEV_IH);
    }
    return poll(ring, r);
}
