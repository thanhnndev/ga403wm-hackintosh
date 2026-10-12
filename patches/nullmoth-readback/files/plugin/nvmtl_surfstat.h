/*
 * Per-IOSurface readback / upload statistics for the NVMTL plugin (local diagnostic, not upstream).
 *
 * Purpose: say, per IOSurface, WHY a GPU->RAM readback (nvmtlSurfaceOut) or a RAM->GPU upload (nvmtlSurfaceIn) happened,
 * how many bytes it moved, how long the CPU copy took and how long the process waited for the GPU.
 *
 * Rules this file keeps:
 *  - Off by default. One stat() of a root-owned request file every 250 ms decides; when off, a call costs one clock read.
 *  - Bounded: NVSS_SLOTS surfaces (least recently used slot is evicted into the totals), one output file of a few KB,
 *    rewritten at most every NVSS_DUMP_INTERVAL_NS. Nothing is logged per frame.
 *  - No pixels, no window titles, no surface names. Only IDs, geometry, counters and nanoseconds.
 *  - Plain C with POSIX only, so the same file is unit-tested on Linux (test/readback/surfstat_test.c) and included
 *    unchanged by the one-translation-unit plugin (NVMTLDevice.m).
 *  - Uses open()/stat(), never fopen()/access(): NVMTL_RELEASE builds redirect those for /tmp/nvmtl-* paths.
 *
 * Enable (as root, on the Mac):   echo WindowServer > /Library/NullMoth/surfstat-request     (first line = process name, * = all)
 * Disable:                        rm /Library/NullMoth/surfstat-request
 * Output:                         /private/tmp/nullmoth-surfstat.<process>.<pid>.txt
 * The request file must be a regular file owned by root (or the process owner) and not group/world writable.
 */
#ifndef NVMTL_SURFSTAT_H
#define NVMTL_SURFSTAT_H

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef NVSS_REQUEST_FILE
#define NVSS_REQUEST_FILE "/Library/NullMoth/surfstat-request"
#endif
#ifndef NVSS_OUT_DIR
#define NVSS_OUT_DIR "/private/tmp"
#endif
#ifndef NVSS_SLOTS
#define NVSS_SLOTS 256
#endif
#ifndef NVSS_TOP
#define NVSS_TOP 16
#endif
#ifndef NVSS_POLL_NS
#define NVSS_POLL_NS 250000000ull
#endif
#ifndef NVSS_DUMP_INTERVAL_NS
#define NVSS_DUMP_INTERVAL_NS 5000000000ull
#endif
#ifndef NVSS_NOW_NS
static inline uint64_t nvss_now_ns_default(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec;
}
#define NVSS_NOW_NS() nvss_now_ns_default()
#endif
#ifndef NVSS_PROGNAME
#if defined(__APPLE__)
#define NVSS_PROGNAME() getprogname()
#else
extern char *program_invocation_short_name;
#define NVSS_PROGNAME() program_invocation_short_name
#endif
#endif

/* Why an IOSurface texture is NOT backed by the surface's family VRAM (a private per-process image plus copies). */
enum nvss_private_why {
    NVSS_P_NONE = 0,        /* shared: the texture is an alias of the family VRAM */
    NVSS_P_SHARE_OFF,       /* nvmtl_vk_surface_share_on() == 0 (NVMTL_NO_SURFACE_SHARE, headless GPU, NVK import/ext-fd/DRM modifier missing) */
    NVSS_P_PLANE,           /* plane != 0 or the IOSurface has more than one plane (video, YUV) */
    NVSS_P_GEOMETRY,        /* texture row bytes exceed the surface row, or the texture is taller than the surface */
    NVSS_P_ROW_ALIGN,       /* surface bytes-per-row is not a multiple of 32 (linear pitch unit of the texture header) */
    NVSS_P_IMPORT,          /* nvmtl_vk_surface_vram failed: kernel SURF_VRAM refusal or Vulkan import failure */
    NVSS_P_ALIAS,           /* the VRAM was imported but the buffer-alias image could not be created */
    NVSS_P_N
};
/* Where nvmtl_vk_surface_vram() gave up (the plugin side of "import"; the kernel side is debug.nvaccel_ss_share_*). */
enum nvss_import_why {
    NVSS_IW_NONE = 0, NVSS_IW_SHARE_OFF, NVSS_IW_NO_MEMTYPE, NVSS_IW_NO_FD, NVSS_IW_VK_IMPORT, NVSS_IW_BUFFER, NVSS_IW_N
};
enum nvss_out_outcome {
    NVSS_O_DIRTY = 0,       /* shared VRAM marked newest; no copy (the good case) */
    NVSS_O_COPY_PRIVATE,    /* copied: the texture is a private image */
    NVSS_O_COPY_REFUSED,    /* copied: shared texture but the dirty export was refused (status recorded) */
    NVSS_O_FAIL,            /* lock or readback failed */
    NVSS_O_NOCOPYABLE,      /* geometry says the surface cannot be synced at all */
    NVSS_O_N
};
enum nvss_in_outcome {
    NVSS_I_SKIP_SEEN = 0,   /* already synced at this seed/generation (counted globally only) */
    NVSS_I_SKIP_TAG,        /* shared VRAM is current at this seed */
    NVSS_I_COPY_NEWTEX,     /* uploaded: this texture object had never synced this surface */
    NVSS_I_COPY_SEED,       /* uploaded: the IOSurface seed moved (a CPU writer, or a peer's copy-out) */
    NVSS_I_COPY_GEN,        /* uploaded: the VRAM tag generation moved (private image behind a peer's GPU write) */
    NVSS_I_FAIL,
    NVSS_I_NOCOPYABLE,
    NVSS_I_N
};

typedef struct {
    uint32_t id, plane, w, h, row, bpp, fmt;
    uint8_t  used, why;                     /* why = enum nvss_private_why of the newest wrapper */
    int32_t  last_vkres;                    /* VkResult of the newest failed import (0 = none) */
    uint8_t  last_import_why;               /* enum nvss_import_why of the newest failed import */
    uint32_t last_dirty_status;             /* newest refused dirty status (0 = none) */
    uint64_t last_ns;
    uint64_t wrap, wrap_shared, wrap_private, imp_ns;
    uint64_t out[NVSS_O_N];
    uint64_t out_bytes, out_gpu_ns, out_cpu_ns, out_lock_ns, dirty_ns;
    uint64_t in[NVSS_I_N];
    uint64_t in_bytes, in_gpu_ns, in_cpu_ns, in_ns;
} nvss_surf;

typedef struct {
    uint64_t wrap_shared, wrap_private, imp_ns;
    uint64_t why[NVSS_P_N];
    uint64_t imp_why[NVSS_IW_N];
    struct { int32_t res; uint64_t n; } vkres[4];
    unsigned vkres_used;
    uint64_t vkres_other;
    uint64_t out[NVSS_O_N];
    uint64_t out_bytes, out_gpu_ns, out_cpu_ns, out_lock_ns, dirty_ns;
    uint64_t in[NVSS_I_N];
    uint64_t in_bytes, in_gpu_ns, in_cpu_ns, in_ns;
    uint64_t commit_wait_n, commit_wait_ns;
    uint64_t evicted;
    /* readbacks by size class: <64K, <1M, <4M, <16M, >=16M */
    uint64_t cls_n[5], cls_bytes[5], cls_ns[5];
    struct { uint32_t status; uint64_t n; } dirty_status[8];
    unsigned dirty_status_used;
    uint64_t dirty_status_other;
} nvss_tot;

static pthread_mutex_t nvss_lock = PTHREAD_MUTEX_INITIALIZER;
static nvss_surf nvss_tab[NVSS_SLOTS];
static nvss_tot  nvss_t;
static _Atomic int      nvss_on_flag;
static _Atomic uint64_t nvss_next_poll;
static _Atomic uint64_t nvss_skip_seen;
static _Atomic uint64_t nvss_seq;               /* number of dumps written */
static uint64_t nvss_last_dump_ns, nvss_start_ns;

/* ---- pure helpers (unit-tested) ---- */

/* Mirrors the guard in nvmtl_surface_image_create(): returns NVSS_P_NONE when the texture is eligible for the family
 * VRAM and the reason otherwise. 'share_on' is nvmtl_vk_surface_share_on(). The caller still performs the import. */
static inline int nvss_share_precheck(int share_on, unsigned long plane_count, unsigned long plane, uint32_t w, uint32_t bpp,
                                      uint32_t h, size_t row, size_t surf_h)
{
    if (!share_on) return NVSS_P_SHARE_OFF;
    if (plane != 0 || plane_count > 1) return NVSS_P_PLANE;
    if ((size_t)w * (bpp ? bpp : 4) > row || (size_t)h > surf_h) return NVSS_P_GEOMETRY;
    if (row % 32) return NVSS_P_ROW_ALIGN;
    return NVSS_P_NONE;
}
static inline int nvss_size_class(uint64_t bytes)
{
    return bytes < (64u << 10) ? 0 : bytes < (1u << 20) ? 1 : bytes < (4u << 20) ? 2 : bytes < (16u << 20) ? 3 : 4;
}
static inline const char *nvss_why_name(int w)
{
    static const char *const n[NVSS_P_N] = { "shared", "share-off", "plane", "geometry", "row-align", "import", "alias" };
    return (w >= 0 && w < NVSS_P_N) ? n[w] : "?";
}
static inline const char *nvss_iw_name(int w)
{
    static const char *const n[NVSS_IW_N] = { "none", "share-off", "no-memtype", "no-fd", "vk-import-refused", "buffer-refused" };
    return (w >= 0 && w < NVSS_IW_N) ? n[w] : "?";
}
static inline const char *nvss_out_name(int o)
{
    static const char *const n[NVSS_O_N] = { "dirty-nocopy", "copy-private", "copy-dirty-refused", "fail", "not-copyable" };
    return (o >= 0 && o < NVSS_O_N) ? n[o] : "?";
}
static inline const char *nvss_in_name(int o)
{
    static const char *const n[NVSS_I_N] = { "skip-seen", "skip-tag", "copy-newtex", "copy-seed", "copy-gen", "fail", "not-copyable" };
    return (o >= 0 && o < NVSS_I_N) ? n[o] : "?";
}

/* ---- enable / disable ---- */

static int nvss_request_read(char *want, size_t cap)
{
    struct stat st;
    snprintf(want, cap, "WindowServer");
    if (stat(NVSS_REQUEST_FILE, &st) != 0 || !S_ISREG(st.st_mode)) return 0;
    if (st.st_uid != 0 && st.st_uid != geteuid()) return 0;
    if (st.st_mode & (S_IWGRP | S_IWOTH)) return 0;
    int fd = open(NVSS_REQUEST_FILE, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return 0;
    char b[64]; ssize_t n = read(fd, b, sizeof b - 1); close(fd);
    if (n > 0) {
        b[n] = 0;
        size_t i = 0;
        while (b[i] == ' ' || b[i] == '\t') i++;
        size_t j = 0;
        while (b[i] && b[i] != '\n' && b[i] != '\r' && b[i] != ' ' && b[i] != '\t' && j < cap - 1) want[j++] = b[i++];
        if (j) want[j] = 0;
    }
    return 1;
}
static int nvss_dump_now(void);
static void nvss_reset_locked(void)
{
    memset(nvss_tab, 0, sizeof nvss_tab); memset(&nvss_t, 0, sizeof nvss_t);
    atomic_store(&nvss_skip_seen, 0); atomic_store(&nvss_seq, 0);
    nvss_last_dump_ns = 0; nvss_start_ns = 0;
}
static void nvss_poll(uint64_t now)
{
    atomic_store_explicit(&nvss_next_poll, now + NVSS_POLL_NS, memory_order_relaxed);
    char want[64]; int on = 0;
    const char *forced = getenv("NVMTL_SURFSTAT");
    if (forced && forced[0] == '1') on = 1;
    else if (nvss_request_read(want, sizeof want)) {
        const char *prog = NVSS_PROGNAME();
        on = want[0] == '*' || (prog && !strcmp(want, prog));
    }
    const int was = atomic_load_explicit(&nvss_on_flag, memory_order_relaxed);
    if (on && !was) {                               /* a fresh measurement window starts with empty counters */
        pthread_mutex_lock(&nvss_lock);
        nvss_reset_locked();
        nvss_start_ns = now; nvss_last_dump_ns = now;
        pthread_mutex_unlock(&nvss_lock);
    }
    atomic_store_explicit(&nvss_on_flag, on, memory_order_relaxed);
    if (!on && was) nvss_dump_now();                /* leave the final numbers behind */
}
static inline int nvss_active(void)
{
    const uint64_t now = NVSS_NOW_NS();
    if (now >= atomic_load_explicit(&nvss_next_poll, memory_order_relaxed)) nvss_poll(now);
    return atomic_load_explicit(&nvss_on_flag, memory_order_relaxed);
}

/* ---- table (caller holds nvss_lock) ---- */

static nvss_surf *nvss_slot_locked(uint32_t id, uint32_t plane, uint64_t now)
{
    unsigned h = (unsigned)((id * 2654435761u) ^ (plane * 40503u)) % NVSS_SLOTS;
    nvss_surf *free_s = NULL, *old = &nvss_tab[0];
    for (unsigned k = 0; k < NVSS_SLOTS; k++) {
        nvss_surf *s = &nvss_tab[(h + k) % NVSS_SLOTS];
        if (s->used && s->id == id && s->plane == plane) { s->last_ns = now; return s; }
        if (!s->used) { if (!free_s) free_s = s; }
        else if (s->last_ns < old->last_ns || !old->used) old = s;
    }
    nvss_surf *s = free_s;
    if (!s) { s = old; nvss_t.evicted++; }     /* its counters are already folded into nvss_t */
    memset(s, 0, sizeof *s);
    s->used = 1; s->id = id; s->plane = plane; s->last_ns = now;
    return s;
}
static void nvss_note_dirty_status_locked(nvss_surf *s, uint32_t status)
{
    s->last_dirty_status = status;
    for (unsigned i = 0; i < nvss_t.dirty_status_used; i++)
        if (nvss_t.dirty_status[i].status == status) { nvss_t.dirty_status[i].n++; return; }
    if (nvss_t.dirty_status_used < 8) {
        nvss_t.dirty_status[nvss_t.dirty_status_used].status = status;
        nvss_t.dirty_status[nvss_t.dirty_status_used++].n = 1;
    } else nvss_t.dirty_status_other++;
}

/* ---- dump ---- */

typedef struct { char *p; size_t n, cap; } nvss_buf;
static void nvss_cat(nvss_buf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void nvss_cat(nvss_buf *b, const char *fmt, ...)
{
    if (b->n + 1 >= b->cap) return;
    va_list ap; va_start(ap, fmt);
    int w = vsnprintf(b->p + b->n, b->cap - b->n, fmt, ap);
    va_end(ap);
    if (w < 0) return;
    b->n += (size_t)w < b->cap - b->n ? (size_t)w : b->cap - b->n - 1;
}
static inline double nvss_ms(uint64_t ns) { return (double)ns / 1e6; }
static inline uint64_t nvss_cost(const nvss_surf *s) { return s->out_gpu_ns + s->out_cpu_ns + s->out_lock_ns + s->in_ns + s->dirty_ns + s->imp_ns; }

/* Formats the report into b (caller holds nvss_lock). Returns the number of bytes. */
static size_t nvss_format_locked(nvss_buf *b, uint64_t now)
{
    const double secs = nvss_start_ns ? (double)(now - nvss_start_ns) / 1e9 : 0;
    nvss_cat(b, "# nullmoth-surfstat v1 process=%s pid=%d seq=%llu window_s=%.1f slots=%d evicted=%llu\n",
             NVSS_PROGNAME() ? NVSS_PROGNAME() : "?", (int)getpid(), (unsigned long long)atomic_load(&nvss_seq), secs, NVSS_SLOTS,
             (unsigned long long)nvss_t.evicted);
    nvss_cat(b, "# counts are since the request file appeared; times are summed nanoseconds shown as ms; no pixel data is recorded\n");
    nvss_cat(b, "wrap shared=%llu private=%llu import_ms=%.2f\n", (unsigned long long)nvss_t.wrap_shared,
             (unsigned long long)nvss_t.wrap_private, nvss_ms(nvss_t.imp_ns));
    nvss_cat(b, "private_why");
    for (int i = 1; i < NVSS_P_N; i++) nvss_cat(b, " %s=%llu", nvss_why_name(i), (unsigned long long)nvss_t.why[i]);
    nvss_cat(b, "\nimport_failed");
    for (int i = 1; i < NVSS_IW_N; i++) nvss_cat(b, " %s=%llu", nvss_iw_name(i), (unsigned long long)nvss_t.imp_why[i]);
    nvss_cat(b, "  vkresult");
    if (!nvss_t.vkres_used) nvss_cat(b, " none");
    for (unsigned i = 0; i < nvss_t.vkres_used; i++) nvss_cat(b, " %d=%llu", (int)nvss_t.vkres[i].res, (unsigned long long)nvss_t.vkres[i].n);
    if (nvss_t.vkres_other) nvss_cat(b, " other=%llu", (unsigned long long)nvss_t.vkres_other);
    nvss_cat(b, "\nout");
    for (int i = 0; i < NVSS_O_N; i++) nvss_cat(b, " %s=%llu", nvss_out_name(i), (unsigned long long)nvss_t.out[i]);
    nvss_cat(b, "\nout_copy bytes=%llu gpu_wait_ms=%.2f cpu_copy_ms=%.2f lock_ms=%.2f dirty_path_ms=%.2f\n",
             (unsigned long long)nvss_t.out_bytes, nvss_ms(nvss_t.out_gpu_ns), nvss_ms(nvss_t.out_cpu_ns),
             nvss_ms(nvss_t.out_lock_ns), nvss_ms(nvss_t.dirty_ns));
    nvss_cat(b, "in skip-seen=%llu", (unsigned long long)atomic_load(&nvss_skip_seen));
    for (int i = 1; i < NVSS_I_N; i++) nvss_cat(b, " %s=%llu", nvss_in_name(i), (unsigned long long)nvss_t.in[i]);
    nvss_cat(b, "\nin_copy bytes=%llu gpu_wait_ms=%.2f cpu_copy_ms=%.2f total_ms=%.2f\n", (unsigned long long)nvss_t.in_bytes,
             nvss_ms(nvss_t.in_gpu_ns), nvss_ms(nvss_t.in_cpu_ns), nvss_ms(nvss_t.in_ns));
    nvss_cat(b, "dirty_status");
    if (!nvss_t.dirty_status_used) nvss_cat(b, " none");
    for (unsigned i = 0; i < nvss_t.dirty_status_used; i++)
        nvss_cat(b, " %#x=%llu", nvss_t.dirty_status[i].status, (unsigned long long)nvss_t.dirty_status[i].n);
    if (nvss_t.dirty_status_other) nvss_cat(b, " other=%llu", (unsigned long long)nvss_t.dirty_status_other);
    nvss_cat(b, "\ncommit_wait n=%llu ms=%.2f   # waitUntilCompleted inside commitAndWaitUntilSubmitted (elapsed, not CPU)\n",
             (unsigned long long)nvss_t.commit_wait_n, nvss_ms(nvss_t.commit_wait_ns));
    static const char *const cn[5] = { "<64K", "<1M", "<4M", "<16M", ">=16M" };
    nvss_cat(b, "readback_by_size");
    for (int i = 0; i < 5; i++)
        if (nvss_t.cls_n[i]) nvss_cat(b, " %s:n=%llu,MB=%.1f,ms=%.2f", cn[i], (unsigned long long)nvss_t.cls_n[i],
                                      (double)nvss_t.cls_bytes[i] / 1048576.0, nvss_ms(nvss_t.cls_ns[i]));
    nvss_cat(b, "\n# top surfaces by (readback + upload + import + dirty-path) time\n");
    nvss_cat(b, "# id plane WxH row bpp fmt mode why wraps(sh/pv) out(dirty/priv/refused/fail) out_MB gpu_ms cpu_ms | in(tag/new/seed/gen/fail) in_MB in_ms | last_dirty_status import_why/vkres\n");
    const nvss_surf *top[NVSS_TOP]; unsigned nt = 0;
    for (unsigned i = 0; i < NVSS_SLOTS; i++) {
        const nvss_surf *s = &nvss_tab[i];
        if (!s->used || !nvss_cost(s)) continue;
        unsigned at = nt < NVSS_TOP ? nt++ : NVSS_TOP;
        if (at == NVSS_TOP) { if (nvss_cost(s) <= nvss_cost(top[NVSS_TOP - 1])) continue; at = NVSS_TOP - 1; }
        top[at] = s;
        while (at > 0 && nvss_cost(top[at]) > nvss_cost(top[at - 1])) { const nvss_surf *t = top[at]; top[at] = top[at - 1]; top[at - 1] = t; at--; }
    }
    for (unsigned i = 0; i < nt; i++) {
        const nvss_surf *s = top[i];
        nvss_cat(b, "surf %u %u %ux%u %u %u %#x %s %s %llu/%llu out(%llu/%llu/%llu/%llu) %.1f %.2f %.2f | in(%llu/%llu/%llu/%llu/%llu) %.1f %.2f | %#x %s/%d\n",
                 s->id, s->plane, s->w, s->h, s->row, s->bpp, s->fmt, s->why ? "private" : "shared", nvss_why_name(s->why),
                 (unsigned long long)s->wrap_shared, (unsigned long long)s->wrap_private,
                 (unsigned long long)s->out[NVSS_O_DIRTY], (unsigned long long)s->out[NVSS_O_COPY_PRIVATE],
                 (unsigned long long)s->out[NVSS_O_COPY_REFUSED], (unsigned long long)s->out[NVSS_O_FAIL],
                 (double)s->out_bytes / 1048576.0, nvss_ms(s->out_gpu_ns), nvss_ms(s->out_cpu_ns),
                 (unsigned long long)s->in[NVSS_I_SKIP_TAG], (unsigned long long)s->in[NVSS_I_COPY_NEWTEX],
                 (unsigned long long)s->in[NVSS_I_COPY_SEED], (unsigned long long)s->in[NVSS_I_COPY_GEN],
                 (unsigned long long)s->in[NVSS_I_FAIL], (double)s->in_bytes / 1048576.0, nvss_ms(s->in_ns),
                 s->last_dirty_status, nvss_iw_name(s->last_import_why), (int)s->last_vkres);
    }
    return b->n;
}

static int nvss_write_report(const char *data, size_t n)
{
    char tmp[1100], fin[1024];
    int k = snprintf(fin, sizeof fin, "%s/nullmoth-surfstat.%s.%d.txt", NVSS_OUT_DIR, NVSS_PROGNAME() ? NVSS_PROGNAME() : "proc", (int)getpid());
    if (k < 0 || (size_t)k >= sizeof fin) return -1;
    snprintf(tmp, sizeof tmp, "%s.tmp", fin);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (fd < 0 && errno == EEXIST) { unlink(tmp); fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644); }
    if (fd < 0) return -1;
    size_t off = 0;
    while (off < n) { ssize_t w = write(fd, data + off, n - off); if (w <= 0) { close(fd); unlink(tmp); return -1; } off += (size_t)w; }
    close(fd);
    if (rename(tmp, fin) != 0) { unlink(tmp); return -1; }
    return 0;
}

/* Writes the report now (used by the due-check, by the test, and by nvss_dump_now()). Returns 0 on success. */
static int nvss_dump_now(void)
{
    static char out[24 * 1024];
    nvss_buf b = { out, 0, sizeof out };
    const uint64_t now = NVSS_NOW_NS();
    pthread_mutex_lock(&nvss_lock);
    nvss_last_dump_ns = now;
    atomic_fetch_add(&nvss_seq, 1);
    nvss_format_locked(&b, now);
    size_t n = b.n;
    int rc = nvss_write_report(out, n);        /* single static buffer: keep the lock until it is written */
    pthread_mutex_unlock(&nvss_lock);
    return rc;
}
static inline void nvss_dump_if_due(void)
{
    const uint64_t now = NVSS_NOW_NS();
    int due = 0;
    pthread_mutex_lock(&nvss_lock);
    due = nvss_last_dump_ns && now - nvss_last_dump_ns >= NVSS_DUMP_INTERVAL_NS;
    if (due) nvss_last_dump_ns = now;
    pthread_mutex_unlock(&nvss_lock);
    if (due) nvss_dump_now();
}

/* ---- events (call only when nvss_active()) ---- */

/* A texture was wrapped around an IOSurface plane. why == NVSS_P_NONE means it shares the family VRAM. */
static void nvss_ev_wrap(uint32_t id, uint32_t plane, uint32_t w, uint32_t h, uint32_t row, uint32_t bpp, uint32_t fmt,
                         int why, int import_why, int32_t vkres, uint64_t import_ns)
{
    const uint64_t now = NVSS_NOW_NS();
    pthread_mutex_lock(&nvss_lock);
    nvss_surf *s = nvss_slot_locked(id, plane, now);
    s->w = w; s->h = h; s->row = row; s->bpp = bpp; s->fmt = fmt; s->why = (uint8_t)why; s->wrap++;
    if (import_why > 0 && import_why < NVSS_IW_N) {
        s->last_import_why = (uint8_t)import_why; nvss_t.imp_why[import_why]++;
        if (vkres) {
            s->last_vkres = vkres;
            unsigned i = 0;
            while (i < nvss_t.vkres_used && nvss_t.vkres[i].res != vkres) i++;
            if (i < nvss_t.vkres_used) nvss_t.vkres[i].n++;
            else if (nvss_t.vkres_used < 4) { nvss_t.vkres[nvss_t.vkres_used].res = vkres; nvss_t.vkres[nvss_t.vkres_used++].n = 1; }
            else nvss_t.vkres_other++;
        }
    }
    s->imp_ns += import_ns; nvss_t.imp_ns += import_ns;
    if (why == NVSS_P_NONE) { s->wrap_shared++; nvss_t.wrap_shared++; }
    else { s->wrap_private++; nvss_t.wrap_private++; if (why > 0 && why < NVSS_P_N) nvss_t.why[why]++; }
    pthread_mutex_unlock(&nvss_lock);
    nvss_dump_if_due();
}
/* A GPU write was published (nvmtlSurfaceOut). bytes/gpu/cpu/lock are zero for the no-copy outcome. dirty_path_ns is the time
 * spent in the dirty export + tag bump (or the refused export). status is the refusal status (0 if none). */
static void nvss_ev_out(uint32_t id, uint32_t plane, int outcome, uint64_t bytes, uint64_t gpu_ns, uint64_t cpu_ns,
                        uint64_t lock_ns, uint64_t dirty_path_ns, uint32_t status)
{
    if (outcome < 0 || outcome >= NVSS_O_N) return;
    const uint64_t now = NVSS_NOW_NS();
    pthread_mutex_lock(&nvss_lock);
    nvss_surf *s = nvss_slot_locked(id, plane, now);
    s->out[outcome]++; nvss_t.out[outcome]++;
    s->dirty_ns += dirty_path_ns; nvss_t.dirty_ns += dirty_path_ns;
    if (status) nvss_note_dirty_status_locked(s, status);
    if (outcome == NVSS_O_COPY_PRIVATE || outcome == NVSS_O_COPY_REFUSED) {
        s->out_bytes += bytes; s->out_gpu_ns += gpu_ns; s->out_cpu_ns += cpu_ns; s->out_lock_ns += lock_ns;
        nvss_t.out_bytes += bytes; nvss_t.out_gpu_ns += gpu_ns; nvss_t.out_cpu_ns += cpu_ns; nvss_t.out_lock_ns += lock_ns;
        const int c = nvss_size_class(bytes);
        nvss_t.cls_n[c]++; nvss_t.cls_bytes[c] += bytes; nvss_t.cls_ns[c] += gpu_ns + cpu_ns + lock_ns;
    }
    pthread_mutex_unlock(&nvss_lock);
    nvss_dump_if_due();
}
/* nvmtlSurfaceIn. NVSS_I_SKIP_SEEN is counted without taking the lock (hot path). */
static void nvss_ev_in(uint32_t id, uint32_t plane, int outcome, uint64_t bytes, uint64_t gpu_ns, uint64_t cpu_ns, uint64_t total_ns)
{
    if (outcome < 0 || outcome >= NVSS_I_N) return;
    if (outcome == NVSS_I_SKIP_SEEN) { atomic_fetch_add_explicit(&nvss_skip_seen, 1, memory_order_relaxed); return; }
    const uint64_t now = NVSS_NOW_NS();
    pthread_mutex_lock(&nvss_lock);
    nvss_surf *s = nvss_slot_locked(id, plane, now);
    s->in[outcome]++; nvss_t.in[outcome]++;
    if (outcome == NVSS_I_COPY_NEWTEX || outcome == NVSS_I_COPY_SEED || outcome == NVSS_I_COPY_GEN) {
        s->in_bytes += bytes; s->in_gpu_ns += gpu_ns; s->in_cpu_ns += cpu_ns;
        nvss_t.in_bytes += bytes; nvss_t.in_gpu_ns += gpu_ns; nvss_t.in_cpu_ns += cpu_ns;
    }
    s->in_ns += total_ns; nvss_t.in_ns += total_ns;
    pthread_mutex_unlock(&nvss_lock);
    nvss_dump_if_due();
}
static void nvss_ev_commit_wait(uint64_t ns)
{
    pthread_mutex_lock(&nvss_lock);
    nvss_t.commit_wait_n++; nvss_t.commit_wait_ns += ns;
    pthread_mutex_unlock(&nvss_lock);
    nvss_dump_if_due();
}
/* Test hook: forget everything. */
static void nvss_reset_for_test(void)
{
    pthread_mutex_lock(&nvss_lock);
    nvss_reset_locked();
    pthread_mutex_unlock(&nvss_lock);
}
#endif
