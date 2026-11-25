// ioccount: DYLD interposer counting ioctl() by request and IOConnectCall* by selector in THIS process (own test only).
// IOC_MARK=1 counting starts at the first call of ioc_mark_start() from the test (resolved by dlsym); prints at exit.
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <sys/ioctl.h>
#include <stdatomic.h>
#include <IOKit/IOKitLib.h>
#include <execinfo.h>
#include <dlfcn.h>
#include <pthread.h>
// IOC_BT=<request hex or "sel61">: aggregate call stacks (symbol names, frames 2..9) of that request
static pthread_mutex_t btl = PTHREAD_MUTEX_INITIALIZER;
#define NB 64
static char bts[NB][900]; static unsigned long btn[NB]; static int nbt;
static void bt_note(void) {
    void *f[12]; int n = backtrace(f, 12); char buf[900]; buf[0] = 0;
    for (int i = 2; i < n; i++) { Dl_info d; const char *nm = dladdr(f[i], &d) && d.dli_sname ? d.dli_sname : "?";
        if (strlen(buf) + strlen(nm) + 4 < sizeof buf) { strcat(buf, nm); strcat(buf, " < "); } }
    pthread_mutex_lock(&btl);
    int k; for (k = 0; k < nbt; k++) if (!strcmp(bts[k], buf)) break;
    if (k == nbt && nbt < NB) { strcpy(bts[nbt++], buf); }
    if (k < NB) btn[k]++;
    pthread_mutex_unlock(&btl);
}
static int want(unsigned long r) { const char *e = getenv("IOC_BT"); return e && strtoul(e, NULL, 16) == r; }
static int wantsel(uint32_t s) { const char *e = getenv("IOC_BT"); return e && !strncmp(e, "sel", 3) && (uint32_t)atoi(e + 3) == s; }
static char clsname[64][64]; static mach_port_t clsport[64];
static void selnote(mach_port_t c, uint32_t s) {
    if (!clsname[s & 63][0]) { io_name_t n = {0}; IOObjectGetClass(c, n); strlcpy(clsname[s & 63], n, 64); clsport[s&63] = c; }
    if (wantsel(s)) bt_note();
}
#define DYLD_INTERPOSE(_r,_e) __attribute__((used)) static struct { const void *r; const void *e; } _interpose_##_e __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&_r, (const void *)(unsigned long)&_e };
#define N 512
static _Atomic unsigned long sv1, svn; static _Atomic unsigned long long svns;
static _Atomic unsigned long long cs_bos, cs_n, cs_maxbo;
static _Atomic unsigned long req[N], cnt[N], sel[64], selc[64]; static _Atomic int on = 1;
static _Atomic unsigned long long ns[N], cns[N];
void ioc_set(int v) { atomic_store(&on, v); }
void ioc_reset(void) { sv1 = svn = 0; svns = 0; cs_bos = cs_n = cs_maxbo = 0; nbt = 0; memset(btn, 0, sizeof btn); for (int i = 0; i < N; i++) { cnt[i] = 0; ns[i] = 0; cns[i] = 0; } for (int i = 0; i < 64; i++) selc[i] = 0; }
static void note(unsigned long r, unsigned long long t, unsigned long long ct) {
    if (!atomic_load(&on)) return;
    unsigned h = (unsigned)((r * 2654435761u) >> 7) % N;
    for (int k = 0; k < N; k++, h = (h + 1) % N) {
        unsigned long z = 0;
        if (req[h] == r || atomic_compare_exchange_strong(&req[h], &z, r) || req[h] == r) { cnt[h]++; ns[h] += t; cns[h] += ct; return; }
    }
}
static void cs_parse(void *p) {
    struct { uint32_t ctx, bo_list; uint32_t nchunks, flags; uint64_t chunks; } *in = p;
    if (!in || !in->chunks) return;
    uint64_t *cp = (uint64_t *)(uintptr_t)in->chunks;
    for (uint32_t i = 0; i < in->nchunks; i++) {
        struct { uint32_t id, len; uint64_t data; } *ch = (void *)(uintptr_t)cp[i];
        if (ch && ch->id == 6 && ch->data) { uint32_t *bl = (uint32_t *)(uintptr_t)ch->data; unsigned long long n = bl[2];
            cs_bos += n; cs_n++; if (n > cs_maxbo) cs_maxbo = n; }
    }
}
static int my_ioctl(int fd, unsigned long r, ...) {
    va_list a; va_start(a, r); void *p = va_arg(a, void *); va_end(a);
    if (r == 0xc0186444 && atomic_load(&on)) cs_parse(p);
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW), c0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
    int x = ioctl(fd, r, p);
    note(r, clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - t0, clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - c0);
    if (atomic_load(&on) && want(r)) bt_note();
    return x;
}
DYLD_INTERPOSE(my_ioctl, ioctl)
static kern_return_t my_icm(mach_port_t c, uint32_t s, const uint64_t *i, uint32_t ic, const void *is, size_t isc, uint64_t *o, uint32_t *oc, void *os, size_t *osc) {
    if (atomic_load(&on)) { selc[s & 63]++; selnote(c, s); }
    return IOConnectCallMethod(c, s, i, ic, is, isc, o, oc, os, osc);
}
DYLD_INTERPOSE(my_icm, IOConnectCallMethod)
static kern_return_t my_icsm(mach_port_t c, uint32_t s, const uint64_t *i, uint32_t ic, uint64_t *o, uint32_t *oc) {
    if (atomic_load(&on)) { selc[s & 63]++; selnote(c, s); }
    return IOConnectCallScalarMethod(c, s, i, ic, o, oc);
}
DYLD_INTERPOSE(my_icsm, IOConnectCallScalarMethod)
static kern_return_t my_icstm(mach_port_t c, uint32_t s, const void *is, size_t isc, void *os, size_t *osc) {
    if (atomic_load(&on)) { selc[s & 63]++; selnote(c, s); }
    return IOConnectCallStructMethod(c, s, is, isc, os, osc);
}
DYLD_INTERPOSE(my_icstm, IOConnectCallStructMethod)
#include <IOSurface/IOSurfaceRef.h>
static void my_sv(IOSurfaceRef b, CFStringRef k, CFTypeRef v) { uint64_t t0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID); IOSurfaceSetValue(b, k, v); if (atomic_load(&on)) { sv1++; svns += clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - t0; } }
DYLD_INTERPOSE(my_sv, IOSurfaceSetValue)
static void my_svs(IOSurfaceRef b, CFDictionaryRef d) { uint64_t t0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID); IOSurfaceSetValues(b, d); if (atomic_load(&on)) { svn++; svns += clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - t0; } }
DYLD_INTERPOSE(my_svs, IOSurfaceSetValues)
void ioc_dump(double per) {
    fprintf(stderr, "  IOSurfaceSetValue %.2f + SetValues %.2f per present, %.1f us CPU per present\n", sv1 / per, svn / per, svns / 1e3 / per);
    fprintf(stderr, "ioccount (per %.0f): CS bo list %.1f BOs average, max %llu\n", per, cs_n ? (double)cs_bos / cs_n : 0, cs_maxbo);
    for (int i = 0; i < N; i++) if (cnt[i]) fprintf(stderr, "  ioctl %#010lx (grp '%c' nr %#lx len %lu): %lu = %.2f each, %.1f us wall, %.1f us CPU per present (%.1f us CPU per call)\n", req[i],
        (int)((req[i] >> 8) & 0xff), req[i] & 0xff, (req[i] >> 16) & 0x1fff, cnt[i], cnt[i] / per, ns[i] / 1e3 / per, cns[i] / 1e3 / per, cnt[i] ? cns[i] / 1e3 / cnt[i] : 0);
    for (int i = 0; i < 64; i++) if (selc[i]) fprintf(stderr, "  IOConnect sel %d (%s): %lu = %.2f each\n", i, clsname[i], selc[i], selc[i] / per);
    for (int k = 0; k < nbt; k++) fprintf(stderr, "  BT %.2f each: %s\n", btn[k] / per, bts[k]);
}
