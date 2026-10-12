/*
 * Protocol model of the IOSurface <-> family VRAM <-> private VkImage synchronisation in NullMoth 1.14.2, checked against a
 * plain "what was last written" oracle. It runs on any host; it needs no GPU and says NOTHING about hardware timing.
 *
 * What is real: the pending-page-off table is the kext's own nvsv_pend.h, and the share eligibility predicate is the
 * plugin's own nvss_share_precheck(). What is modelled (and is therefore an ASSUMPTION about code that is closed or only
 * reached on the machine) is marked "ASSUMPTION" below; the matching hardware checks are in macos/surfsync.m.
 *
 * Mirrors (v1.14.2): NVMTLObjects.m nvmtlSurfaceIn / nvmtlSurfaceOut, NVMTLDevice.m nvmtl_surface_image_create,
 * nvrm-accel.cpp nvAccelSurfDirty / nvAccelSurfVram / NVResource::pageoff / nvAccelIopFlip / nvAccelSurfScanoutSync.
 *
 * Scenarios exercised by random operation sequences: CPU edit then GPU read; GPU write then CPU lock read; several processes
 * on one surface; different pitches and widths (padding must never change); resource freed and recreated while textures are
 * alive; injected import refusals, dirty refusals and readback (fence) failures; flips refused so the copy path runs.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define NVSV_PEND_SLOTS 64            /* small, so saturation is reached in a short run */
#include "../../patches/nullmoth-readback/files/kexts/NVRM/accel/nvsv_pend.h"
#include "../../patches/nullmoth-readback/files/plugin/nvmtl_surfstat.h"

#define MAXS 12
#define MAXT 40
#define ROWS 4
#define MAXP 12                       /* cells per row including padding */
typedef int cell;
enum { PEND_UPSTREAM = 0, PEND_FIXED, PEND_MUTANT_WIPE };
static int g_variant;

/* ---- kernel side ---- */
typedef struct vblock { int refs; cell c[ROWS * MAXP]; int cookie; } vblock;
typedef struct { int alive; vblock *vm; int ramValid, vramNewest; } res_t;           /* NVResource + NVVidMemory + valid[] bits */
typedef struct {
    int id, used, w, pitch;                                                        /* texture width w <= pitch */
    cell ram[ROWS * MAXP];
    unsigned seed;
    struct { int valid; unsigned seed, gen; } tag;                                 /* "NVMTLVramAt:p0" attachment */
    res_t res;
    cell truth[ROWS * MAXP];
    int poisoned;                                                                  /* a failed readback left the contents undefined */
} surf_t;
static surf_t S[MAXS];
static struct nvsv_pend pend;                                                      /* fixed + mutant variants */
static unsigned up_pend[NVSV_PEND_SLOTS];                                          /* upstream table: ids only */
static long long up_full;
static int cookie_seq;

static int kp_add(surf_t *s) {
    if (g_variant == PEND_UPSTREAM) {
        int freeSlot = -1;
        for (int i = 0; i < NVSV_PEND_SLOTS; i++) { if (up_pend[i] == (unsigned)s->id) return 1; if (!up_pend[i] && freeSlot < 0) freeSlot = i; }
        if (freeSlot < 0) { up_full++; return 0; }
        up_pend[freeSlot] = s->id; return 1;
    }
    return nvsv_pend_op(&pend, s->id, &s->res, NVSV_PEND_ADD);
}
static int kp_test(surf_t *s) {
    if (g_variant == PEND_UPSTREAM) { for (int i = 0; i < NVSV_PEND_SLOTS; i++) if (up_pend[i] == (unsigned)s->id) return 1; return 0; }
    return nvsv_pend_op(&pend, s->id, 0, NVSV_PEND_TEST);
}
static void kp_del(surf_t *s) {
    if (g_variant == PEND_UPSTREAM) { for (int i = 0; i < NVSV_PEND_SLOTS; i++) if (up_pend[i] == (unsigned)s->id) up_pend[i] = 0; return; }
    nvsv_pend_op(&pend, s->id, 0, NVSV_PEND_DEL);
}
static void kp_free_resource(surf_t *s) {
    if (g_variant == PEND_FIXED) nvsv_pend_release(&pend, &s->res);
    else if (g_variant == PEND_MUTANT_WIPE) memset(&pend, 0, sizeof pend);   /* wrong on purpose: also drops the entries of live surfaces */
}
static vblock *vb_new(void) { vblock *b = calloc(1, sizeof *b); b->refs = 1; b->cookie = ++cookie_seq; return b; }
static void vb_put(vblock *b) { if (b && --b->refs == 0) free(b); }

static int g_churn;                    /* surfaces are destroyed and replaced by new ones (new IDs) while the run goes on */
static int g_evict_live, g_epoch;      /* evict resources that shared textures still hold / validate the allocation epoch before use */
static int g_inject_vram_fail, g_inject_dirty_fail, g_inject_import_fail, g_inject_readback_fail, g_inject_flip_refuse;
static unsigned rng_s = 1;
static unsigned rnd(unsigned n) { rng_s = rng_s * 1664525u + 1013904223u; return (rng_s >> 8) % n; }
static int chance(int percent) { return (int)rnd(100) < percent; }

/* the family creates the NVResource and wires VRAM on demand (deviceCacheForIOSurface + IOAccelVidMemory::wire) */
static int k_wire(surf_t *s) {
    if (!s->res.alive) { s->res.alive = 1; s->res.ramValid = 1; s->res.vramNewest = 0; s->res.vm = NULL; }
    if (!s->res.vm) {
        if (g_inject_vram_fail && chance(g_inject_vram_fail)) return -1;                        /* VRAM exhausted: NO_VRAM */
        s->res.vm = vb_new();
        memcpy(s->res.vm->c, s->ram, sizeof s->ram);                                            /* ASSUMPTION A3: page-in copies RAM up */
    }
    return 0;
}
/* VRAM -> system memory (NVResource::pageoff on the copy engine) */
static void k_pageoff(surf_t *s) {
    if (!s->res.alive || !s->res.vm) return;
    memcpy(s->ram, s->res.vm->c, sizeof s->ram);
    s->res.ramValid = 1;
    kp_del(s);                                                                                  /* nvSVPend(id, 0) on success */
}
/* IOSurfaceLock by anybody: the family pages the newest data off first. ASSUMPTION A1: the family sees valid[0] clear. */
static void k_cpu_lock(surf_t *s) { if (s->res.alive && s->res.vm && s->res.vramNewest && !s->res.ramValid) k_pageoff(s); }
/* unlock after a CPU write bumps the seed; ASSUMPTION A2: and the family then regards system memory as the newest copy. */
static void k_cpu_unlock_write(surf_t *s) { s->seed++; if (s->res.alive) { s->res.ramValid = 1; s->res.vramNewest = 0; kp_del(s); } }

typedef struct { int ok; vblock *vm; } share_t;
static share_t k_share(surf_t *s) {                                                              /* NVRM_ESC_SURF_VRAM + dup */
    share_t r = { 0, NULL };
    if (g_inject_import_fail && chance(g_inject_import_fail)) return r;                         /* NVK / kernel refused */
    if (k_wire(s)) return r;
    s->res.vm->refs++; r.ok = 1; r.vm = s->res.vm;
    return r;
}
static int k_dirty(surf_t *s) {                                                                  /* NVRM_ESC_SURF_DIRTY: nvAccelSurfDirty */
    if (g_inject_dirty_fail && chance(g_inject_dirty_fail)) return -1;
    if (!s->res.alive || !s->res.vm) return -1;                                                  /* NO_CACHE / NO_VM / NO_HANDLE */
    if (!kp_add(s)) return -1;                                                                   /* PEND_FULL */
    s->res.vramNewest = 1; s->res.ramValid = 0;
    return 0;
}
/* the family drops the resource (eviction). ASSUMPTION A4: it pages off first, as the pageoff hook exists for exactly this. */
static void k_free_resource(surf_t *s, int surface_dies) {
    if (!s->res.alive) return;
    if (!surface_dies && s->res.vramNewest && !s->res.ramValid) k_pageoff(s);
    kp_free_resource(s);
    vb_put(s->res.vm); memset(&s->res, 0, sizeof s->res);
}

/* ---- plugin side: one texture object ---- */
typedef struct {
    int used, proc, surf, shared;
    cell priv[ROWS * MAXP];            /* private VkImage */
    vblock *alias;                     /* the imported family VRAM (shared mode) */
    int synced; unsigned surfSeed, surfGen;
} tex_t;
static tex_t T[MAXT];
static long long n_out_dirty, n_out_copy_private, n_out_copy_refused, n_in_skip_tag, n_in_copy, n_stale_display, n_checks, n_poison_skips;

static cell *img(tex_t *t) { return t->shared ? t->alias->c : t->priv; }
static unsigned tag_gen(surf_t *s) { return s->tag.valid ? s->tag.gen : 0; }
static int tag_current(surf_t *s, unsigned seed) { return s->tag.valid && s->tag.seed == seed; }

static void rows_copy(cell *dst, const cell *src, int pitch, int w) { for (int y = 0; y < ROWS; y++) memcpy(dst + y * pitch, src + y * pitch, (size_t)w * sizeof(cell)); }

/* A shared texture keeps the VRAM block it imported alive (RM dup). If the family frees and re-backs the resource, the block the
 * kernel marks "newest" is a different one. With g_epoch the texture notices (the kernel would have to return an allocation
 * epoch with the share) and imports again; without it, the texture keeps reading and writing an orphan. */
static void p_epoch_check(tex_t *t) {
    surf_t *s = &S[t->surf];
    if (!g_epoch || !t->shared || (s->res.alive && s->res.vm == t->alias)) return;
    vb_put(t->alias); t->alias = NULL; t->shared = 0; t->synced = 0;
    share_t sh = k_share(s);
    if (sh.ok) { t->shared = 1; t->alias = sh.vm; }
}
static void p_surface_in(tex_t *t) {                                       /* nvmtlSurfaceIn */
    p_epoch_check(t);
    surf_t *s = &S[t->surf];
    unsigned vgen = t->shared ? 0 : tag_gen(s);
    if (t->synced && s->seed == t->surfSeed && (t->shared || vgen == t->surfGen)) return;          /* skip: seen */
    if (t->shared && tag_current(s, s->seed)) { t->surfSeed = s->seed; t->synced = 1; n_in_skip_tag++; return; }   /* skip: tag */
    k_cpu_lock(s);                                                                                  /* IOSurfaceLock(ReadOnly) */
    rows_copy(img(t), s->ram, s->pitch, s->w);                                                      /* nvmtl_vk_image_write */
    t->surfSeed = s->seed; t->synced = 1; t->surfGen = vgen; n_in_copy++;
    if (t->shared) { s->tag.valid = 1; s->tag.seed = s->seed; /* gen unchanged */ }                 /* nvmtl_vram_tag_set */
}
static int p_surface_out(tex_t *t) {                                       /* nvmtlSurfaceOut; returns 0 on failure */
    surf_t *s = &S[t->surf];
    p_epoch_check(t);
    if (t->shared && !k_dirty(s)) {
        t->surfSeed = s->seed; t->synced = 1;
        s->tag.valid = 1; s->tag.seed = s->seed; s->tag.gen = tag_gen(s) + 1; t->surfGen = s->tag.gen;   /* nvmtl_vram_tag_bump */
        n_out_dirty++; return 1;
    }
    if (g_inject_readback_fail && chance(g_inject_readback_fail)) { s->poisoned = 1; return 0; }        /* fence / read failure */
    k_cpu_lock(s);                                                                                  /* IOSurfaceLock(0) */
    rows_copy(s->ram, img(t), s->pitch, s->w);                                                      /* nvmtl_vk_image_read */
    s->seed++;                                                                                      /* IOSurfaceUnlock bumps the seed */
    if (s->res.alive) { s->res.ramValid = 1; s->res.vramNewest = t->shared ? s->res.vramNewest : 0; }
    t->surfSeed = s->seed; t->synced = 1;
    if (t->shared) { s->tag.valid = 1; s->tag.seed = s->seed; }                                     /* nvmtl_vram_tag_set (gen kept) */
    else t->surfGen = tag_gen(s);
    if (t->shared) n_out_copy_refused++; else n_out_copy_private++;
    return 1;
}
static void p_wrap(int proc, int si) {                                     /* nvmtl_surface_image_create */
    int ti = -1; for (int i = 0; i < MAXT; i++) if (!T[i].used) { ti = i; break; }
    if (ti < 0) return;
    surf_t *s = &S[si]; tex_t *t = &T[ti]; memset(t, 0, sizeof *t);
    t->used = 1; t->proc = proc; t->surf = si;
    int why = nvss_share_precheck(1, 1, 0, (uint32_t)s->w, 4, ROWS, (size_t)s->pitch * 4 * 8, ROWS);   /* row bytes = pitch cells * 32 B: always aligned */
    if (why == NVSS_P_NONE) { share_t sh = k_share(s); if (sh.ok) { t->shared = 1; t->alias = sh.vm; } }
    if (!t->shared) { memset(t->priv, 0, sizeof t->priv); }
    if (t->shared && tag_current(s, s->seed)) { t->surfSeed = s->seed; t->synced = 1; }             /* "already current (no upload)" */
}
static void p_release(int ti) { tex_t *t = &T[ti]; if (t->used) { if (t->alias) vb_put(t->alias); memset(t, 0, sizeof *t); } }

/* ---- oracle ---- */
static void truth_set(surf_t *s, int x0, int y0, int cw, int ch, cell v) { for (int y = y0; y < y0 + ch; y++) for (int x = x0; x < x0 + cw; x++) s->truth[y * s->pitch + x] = v; }
static int expect(const cell *got, surf_t *s, const char *who) {
    if (s->poisoned) { n_poison_skips++; return 1; }
    n_checks++;
    for (int y = 0; y < ROWS; y++) for (int x = 0; x < s->w; x++)
        if (got[y * s->pitch + x] != s->truth[y * s->pitch + x]) { if (!strcmp(who, "display")) n_stale_display++; return 0; }
    return 1;
}
static int padding_intact(surf_t *s) { for (int y = 0; y < ROWS; y++) for (int x = s->w; x < s->pitch; x++) if (s->ram[y * s->pitch + x] != 0xBAD) return 0; return 1; }

static cell g_val; static const char *g_lastop = "";
static int run(unsigned seed, int steps, int nproc, int fix_variant, long long *refused_out, long long *stale_out)
{
    memset(S, 0, sizeof S); memset(T, 0, sizeof T); memset(&pend, 0, sizeof pend); memset(up_pend, 0, sizeof up_pend);
    up_full = 0; rng_s = seed; g_variant = fix_variant; g_val = 1; cookie_seq = 0;
    n_out_dirty = n_out_copy_private = n_out_copy_refused = n_in_skip_tag = n_in_copy = n_stale_display = n_checks = n_poison_skips = 0;
    int bad = 0, next_id = 100;
    for (int i = 0; i < MAXS; i++) {
        surf_t *s = &S[i]; s->used = 1; s->id = next_id++; s->w = 3 + (int)rnd(MAXP - 3 - 2); s->pitch = s->w + (int)rnd(MAXP - s->w + 1);
        for (int k = 0; k < ROWS * MAXP; k++) s->ram[k] = (k % s->pitch) >= s->w ? 0xBAD : 0;           /* padding sentinel */
        memcpy(s->truth, s->ram, sizeof s->ram);
    }
    for (int step = 0; step < steps && !bad; step++) {
        int proc = (int)rnd(nproc), si = (int)rnd(MAXS), ti = -1; surf_t *s = &S[si];
        int cand[MAXT], nc = 0; for (int i = 0; i < MAXT; i++) if (T[i].used && T[i].surf == si && T[i].proc == proc) cand[nc++] = i;
        if (nc) ti = cand[rnd(nc)];
        unsigned op = rnd(g_churn ? 14 : 12); if (op >= 12) op = 12;
        g_lastop = (const char *[]){"wrap","wrap","release","cpu-edit","cpu-edit","gpu-write","gpu-write","gpu-write","gpu-read","cpu-read","display","evict","recreate"}[op];
        switch (op) {
        case 0: case 1: p_wrap(proc, si); break;
        case 2: if (ti >= 0 && chance(40)) p_release(ti); break;
        case 3: case 4: {                                                               /* CPU edit (lock, write, unlock) */
            int full = chance(30), x0 = full ? 0 : (int)rnd(s->w), y0 = full ? 0 : (int)rnd(ROWS);
            int cw = full ? s->w : 1 + (int)rnd(s->w - x0), ch = full ? ROWS : 1 + (int)rnd(ROWS - y0);
            k_cpu_lock(s);
            for (int y = y0; y < y0 + ch; y++) for (int x = x0; x < x0 + cw; x++) s->ram[y * s->pitch + x] = g_val;
            k_cpu_unlock_write(s); truth_set(s, x0, y0, cw, ch, g_val++);
            if (full) s->poisoned = 0;
            break; }
        case 5: case 6: case 7: {                                                       /* GPU write by a texture of this process, then commit */
            if (ti < 0) { p_wrap(proc, si); break; }
            tex_t *t = &T[ti]; p_surface_in(t);                                          /* load action = load */
            int full = chance(40), x0 = full ? 0 : (int)rnd(s->w), y0 = full ? 0 : (int)rnd(ROWS);
            int cw = full ? s->w : 1 + (int)rnd(s->w - x0), ch = full ? ROWS : 1 + (int)rnd(ROWS - y0);
            cell *im = img(t); for (int y = y0; y < y0 + ch; y++) for (int x = x0; x < x0 + cw; x++) im[y * s->pitch + x] = g_val;
            truth_set(s, x0, y0, cw, ch, g_val++);
            if (!p_surface_out(t)) s->poisoned = 1;
            break; }
        case 8: if (ti >= 0) { p_surface_in(&T[ti]); bad |= !expect(img(&T[ti]), s, "gpu-read"); } break;       /* GPU read in some process */
        case 9: { k_cpu_lock(s); bad |= !expect(s->ram, s, "cpu-read"); break; }                                 /* CPU lock read */
        case 10: {                                                                      /* display: zero-copy flip or the CPU copy path */
            if (!s->res.alive || !s->res.vm) { bad |= !expect(s->ram, s, "display"); break; }
            int flip = s->res.vramNewest && !(g_inject_flip_refuse && chance(g_inject_flip_refuse));
            if (flip) bad |= !expect(s->res.vm->c, s, "display");
            else { if (kp_test(s)) k_pageoff(s); bad |= !expect(s->ram, s, "display"); }
            break; }
        case 12: {                                                                      /* the IOSurface is destroyed; a new one takes its place */
            for (int i = 0; i < MAXT; i++) if (T[i].used && T[i].surf == si) p_release(i);
            k_free_resource(s, 1);                                                      /* no page-off: nobody can read it any more */
            int id = next_id++; memset(s, 0, sizeof *s); s->used = 1; s->id = id;
            s->w = 3 + (int)rnd(MAXP - 3 - 2); s->pitch = s->w + (int)rnd(MAXP - s->w + 1);
            for (int k = 0; k < ROWS * MAXP; k++) s->ram[k] = (k % s->pitch) >= s->w ? 0xBAD : 0;
            memcpy(s->truth, s->ram, sizeof s->ram);
            break; }
        case 11: if (chance(25)) {                                                       /* eviction */
            int live = 0; for (int i = 0; i < MAXT; i++) if (T[i].used && T[i].surf == si && T[i].shared) live = 1;
            if (!live || g_evict_live) k_free_resource(s, 0);
            break; }
        }
        if (!padding_intact(s)) { bad = 1; fprintf(stderr, "padding changed on surface %d at step %d\n", s->id, step); }
        if (bad) fprintf(stderr, "variant %d seed %u: stale read at step %d (op %s, surface %d shared-tex %d)\n", fix_variant, seed, step, g_lastop, s->id, ti >= 0 ? T[ti].shared : -1);
    }
    for (int i = 0; i < MAXT; i++) p_release(i);
    for (int i = 0; i < MAXS; i++) k_free_resource(&S[i], 1);
    if (refused_out) *refused_out = g_variant == PEND_UPSTREAM ? up_full : pend.full;
    if (stale_out) *stale_out = n_stale_display;
    return bad;
}

static int fails;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); fails++; } } while (0)

int main(void)
{
    long long refused, stale; int nproc = 3;
    /* Clean run: no injected errors. Every variant that keeps the invariant "VRAM newest => pending" must never read stale data. */
    for (unsigned seed = 1; seed <= 40; seed++) {
        CHECK(run(seed, 4000, nproc, PEND_UPSTREAM, &refused, &stale) == 0);
        CHECK(run(seed, 4000, nproc, PEND_FIXED, &refused, &stale) == 0);
    }
    /* Everything that can go wrong at once: import refusals, VRAM exhaustion, dirty refusals, flips refused, fence failures. */
    g_inject_vram_fail = 15; g_inject_dirty_fail = 20; g_inject_import_fail = 20; g_inject_readback_fail = 3; g_inject_flip_refuse = 30;
    for (unsigned seed = 100; seed <= 160; seed++) {
        CHECK(run(seed, 4000, nproc, PEND_UPSTREAM, &refused, &stale) == 0);
        CHECK(run(seed, 4000, nproc, PEND_FIXED, &refused, &stale) == 0);
    }
    g_inject_vram_fail = g_inject_dirty_fail = g_inject_import_fail = g_inject_readback_fail = g_inject_flip_refuse = 0;
    /* Surface churn (destroyed surfaces never get a page-off): upstream's id-only table fills and refuses, the fixed one does not,
     * and neither ever shows stale data. */
    long long up_ref = 0, fix_ref = 0;
    g_churn = 1;
    for (unsigned seed = 300; seed < 320; seed++) {
        CHECK(run(seed, 6000, 2, PEND_UPSTREAM, &refused, &stale) == 0); up_ref += refused;
        CHECK(run(seed, 6000, 2, PEND_FIXED, &refused, &stale) == 0);    fix_ref += refused;
    }
    printf("pending-table refusals over 20 churn runs (table of %d): upstream %lld, fixed %lld\n", NVSV_PEND_SLOTS, up_ref, fix_ref);
    CHECK(up_ref > 0 && fix_ref == 0);
    g_churn = 0;
    /* Eviction while shared textures are alive. Without an allocation epoch the model reads stale data (documented hazard H6);
     * with the epoch check it must not. This is NOT claimed to happen on the machine: it needs the family to free and re-back
     * a resource that a plugin texture still holds, which only the counters nvaccel_vm_alloc vs nvaccel_res_new can show. */
    g_evict_live = 1;
    int stale_without_epoch = 0;
    for (unsigned seed = 500; seed < 540; seed++) { g_epoch = 0; stale_without_epoch += run(seed, 4000, nproc, PEND_FIXED, &refused, &stale) != 0; }
    for (unsigned seed = 500; seed < 540; seed++) { g_epoch = 1; CHECK(run(seed, 4000, nproc, PEND_FIXED, &refused, &stale) == 0); }
    printf("eviction with live shared textures: %d/40 runs read stale data without an allocation epoch, 0/40 with it\n", stale_without_epoch);
    CHECK(stale_without_epoch > 0);                      /* the model must be able to see the hazard, or the epoch result means nothing */
    g_evict_live = 0; g_epoch = 0;
    /* Mutation check: a release that also drops the entries of live surfaces must be CAUGHT (the refused-flip copy path then reads
     * stale system memory). If this passes silently the model has no teeth. */
    int caught = 0; g_inject_flip_refuse = 30;
    for (unsigned seed = 400; seed < 460 && !caught; seed++) caught = run(seed, 4000, nproc, PEND_MUTANT_WIPE, &refused, &stale) != 0;
    CHECK(caught);
    if (fails) { fprintf(stderr, "%d check(s) failed\n", fails); return 1; }
    puts("sync_model_test: all checks passed");
    return 0;
}
