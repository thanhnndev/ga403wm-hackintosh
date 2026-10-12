/* Host test for patches/nullmoth-readback/files/plugin/nvmtl_surfstat.h (builds on Linux and macOS; no GPU involved). */
#define _GNU_SOURCE
#include <assert.h>
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char g_dir[256], g_req[300];
static uint64_t g_now;
#define NVSS_NOW_NS() (g_now)
#define NVSS_PROGNAME() "WindowServer"
#define NVSS_SLOTS 8
#define NVSS_TOP 3
#define NVSS_OUT_DIR g_dir
#define NVSS_REQUEST_FILE g_req
#define NVSS_DUMP_INTERVAL_NS 1000000000ull
#include "../../patches/nullmoth-readback/files/plugin/nvmtl_surfstat.h"

static int fails;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); fails++; } } while (0)

static void slurp(char *dst, size_t cap)
{
    char p[512]; snprintf(p, sizeof p, "%s/nullmoth-surfstat.WindowServer.%d.txt", g_dir, (int)getpid());
    FILE *f = fopen(p, "r"); dst[0] = 0; if (!f) return;
    size_t n = fread(dst, 1, cap - 1, f); dst[n] = 0; fclose(f);
}

/* The upstream predicate from nvmtl_surface_image_create(), copied verbatim, is the oracle for the classifier. */
static int upstream_eligible(int share_on, unsigned long planes, unsigned long plane, uint32_t w, uint32_t bpp, uint32_t h, size_t row, size_t sh)
{
    if (plane == 0 && planes <= 1 && share_on) { if ((size_t)w * (bpp ? bpp : 4) <= row && h <= sh && row % 32 == 0) return 1; }
    return 0;
}

static void test_precheck_matches_upstream(void)
{
    uint32_t seed = 12345;
    for (int i = 0; i < 200000; i++) {
        seed = seed * 1664525u + 1013904223u;
        int share = (seed >> 3) & 1; unsigned long planes = (seed >> 4) % 4, plane = (seed >> 7) % 3;
        uint32_t w = 1 + (seed >> 9) % 4000, h = 1 + (seed >> 11) % 3000, bpp = ((seed >> 5) & 7);
        size_t row = ((seed >> 13) % 20000), sh = ((seed >> 17) % 3200);
        if (!(seed & 0x300)) row &= ~31ul;                 /* make the aligned case common */
        int eligible = upstream_eligible(share, planes, plane, w, bpp, h, row, sh);
        int why = nvss_share_precheck(share, planes, plane, w, bpp, h, row, sh);
        CHECK((why == NVSS_P_NONE) == eligible);
        CHECK(why >= 0 && why < NVSS_P_N);
    }
    CHECK(nvss_share_precheck(0, 1, 0, 100, 4, 100, 512, 100) == NVSS_P_SHARE_OFF);
    CHECK(nvss_share_precheck(1, 2, 0, 100, 4, 100, 512, 100) == NVSS_P_PLANE);
    CHECK(nvss_share_precheck(1, 1, 1, 100, 4, 100, 512, 100) == NVSS_P_PLANE);
    CHECK(nvss_share_precheck(1, 1, 0, 200, 4, 100, 512, 100) == NVSS_P_GEOMETRY);
    CHECK(nvss_share_precheck(1, 1, 0, 100, 4, 101, 512, 100) == NVSS_P_GEOMETRY);
    CHECK(nvss_share_precheck(1, 1, 0, 100, 4, 100, 416, 100) == NVSS_P_NONE);       /* 416 = 13*32 */
    CHECK(nvss_share_precheck(1, 1, 0, 101, 4, 100, 420, 100) == NVSS_P_ROW_ALIGN);   /* 420 % 32 = 4 */
}

static void test_disabled_by_default(void)
{
    nvss_reset_for_test();
    unlink(g_req);
    atomic_store(&nvss_on_flag, 0); atomic_store(&nvss_next_poll, 0); g_now = 1000;
    CHECK(!nvss_active());
    /* a request file owned by this user but world writable is refused */
    FILE *f = fopen(g_req, "w"); fputs("WindowServer\n", f); fclose(f); chmod(g_req, 0666);
    g_now += 1000000000ull;
    CHECK(!nvss_active());
    chmod(g_req, 0644); g_now += 1000000000ull;
    CHECK(nvss_active());
    f = fopen(g_req, "w"); fputs("SomethingElse\n", f); fclose(f);
    g_now += 1000000000ull;
    CHECK(!nvss_active());
    f = fopen(g_req, "w"); fputs("*\n", f); fclose(f);
    g_now += 1000000000ull;
    CHECK(nvss_active());
    unlink(g_req);
    g_now += 1000000000ull;
    CHECK(!nvss_active());
}

static void test_counters_and_report(void)
{
    nvss_reset_for_test(); atomic_store(&nvss_on_flag, 0);
    FILE *f = fopen(g_req, "w"); fputs("WindowServer\n", f); fclose(f);
    atomic_store(&nvss_next_poll, 0); g_now += 1000000000ull;
    CHECK(nvss_active());
    /* surface 10: shared, 3 good no-copy writes and 1 refused write with a copy */
    nvss_ev_wrap(10, 0, 2880, 1800, 11520, 4, 80, NVSS_P_NONE, NVSS_IW_NONE, 0, 2000000);
    for (int i = 0; i < 3; i++) nvss_ev_out(10, 0, NVSS_O_DIRTY, 0, 0, 0, 0, 5000, 0);
    nvss_ev_out(10, 0, NVSS_O_COPY_REFUSED, 20736000, 3000000, 4000000, 100000, 7000, 0x80000019u);
    /* surface 11: private because of its row alignment */
    nvss_ev_wrap(11, 0, 1921, 1000, 7684, 4, 80, NVSS_P_ROW_ALIGN, NVSS_IW_NONE, 0, 0);
    nvss_ev_wrap(12, 0, 64, 64, 256, 4, 80, NVSS_P_IMPORT, NVSS_IW_VK_IMPORT, -1000072003, 700000);
    nvss_ev_wrap(12, 0, 64, 64, 256, 4, 80, NVSS_P_IMPORT, NVSS_IW_VK_IMPORT, -1000072003, 700000);
    nvss_ev_wrap(13, 0, 64, 64, 256, 4, 80, NVSS_P_IMPORT, NVSS_IW_NO_FD, 0, 0);
    nvss_ev_out(11, 0, NVSS_O_COPY_PRIVATE, 7684000, 500000, 800000, 20000, 0, 0);
    nvss_ev_out(11, 0, NVSS_O_COPY_PRIVATE, 7684000, 500000, 800000, 20000, 0, 0);
    nvss_ev_in(11, 0, NVSS_I_COPY_NEWTEX, 7684000, 400000, 700000, 1200000);
    nvss_ev_in(11, 0, NVSS_I_SKIP_SEEN, 0, 0, 0, 0);
    nvss_ev_in(10, 0, NVSS_I_SKIP_TAG, 0, 0, 0, 10);
    nvss_ev_commit_wait(1500000);
    CHECK(nvss_t.out[NVSS_O_DIRTY] == 3);
    CHECK(nvss_t.out[NVSS_O_COPY_REFUSED] == 1 && nvss_t.out[NVSS_O_COPY_PRIVATE] == 2);
    CHECK(nvss_t.out_bytes == 20736000 + 2 * 7684000);
    CHECK(nvss_t.out_gpu_ns == 3000000 + 2 * 500000 && nvss_t.out_cpu_ns == 4000000 + 2 * 800000);
    CHECK(nvss_t.why[NVSS_P_ROW_ALIGN] == 1 && nvss_t.wrap_shared == 1 && nvss_t.wrap_private == 4);
    CHECK(nvss_t.imp_why[NVSS_IW_VK_IMPORT] == 2 && nvss_t.imp_why[NVSS_IW_NO_FD] == 1 && nvss_t.vkres_used == 1 && nvss_t.vkres[0].n == 2);
    CHECK(nvss_t.cls_n[4] == 1 && nvss_t.cls_n[3] == 2);                 /* 20.7 MB >= 16M, 7.7 MB < 16M */
    CHECK(atomic_load(&nvss_skip_seen) == 1);
    CHECK(nvss_t.dirty_status_used == 1 && nvss_t.dirty_status[0].status == 0x80000019u && nvss_t.dirty_status[0].n == 1);
    g_now += 2000000000ull;
    nvss_ev_commit_wait(1);                                              /* due: writes the file */
    char rep[24 * 1024]; slurp(rep, sizeof rep);
    CHECK(strstr(rep, "# nullmoth-surfstat v1 process=WindowServer"));
    CHECK(strstr(rep, "copy-dirty-refused=1"));
    CHECK(strstr(rep, "dirty_status 0x80000019=1"));
    CHECK(strstr(rep, "row-align=1"));
    CHECK(strstr(rep, "import_failed share-off=0 no-memtype=0 no-fd=1 vk-import-refused=2 buffer-refused=0  vkresult -1000072003=2"));
    CHECK(strstr(rep, "vk-import-refused/-1000072003"));
    CHECK(strstr(rep, "surf 11 0 1921x1000 7684 4 0x50 private row-align"));
    CHECK(strstr(rep, "surf 10 0 2880x1800 11520 4 0x50 shared shared"));
    CHECK(strstr(rep, "in skip-seen=1"));
    CHECK(!strstr(rep, "\\x00"));
    /* disabling dumps the final numbers */
    unlink(g_req); g_now += 1000000000ull;
    CHECK(!nvss_active());
    unlink(g_req);
}

static void test_bounded_eviction_and_top(void)
{
    nvss_reset_for_test(); atomic_store(&nvss_on_flag, 1); atomic_store(&nvss_next_poll, ~0ull);
    for (uint32_t id = 100; id < 100 + 40; id++) {
        g_now += 10;
        nvss_ev_wrap(id, 0, 64, 64, 256, 4, 80, NVSS_P_NONE, NVSS_IW_NONE, 0, 0);
        nvss_ev_out(id, 0, NVSS_O_COPY_PRIVATE, 16384, id, id, 0, 0, 0);
    }
    int used = 0; for (int i = 0; i < NVSS_SLOTS; i++) used += nvss_tab[i].used;
    CHECK(used == NVSS_SLOTS);
    CHECK(nvss_t.evicted == 40 - NVSS_SLOTS);
    CHECK(nvss_t.out[NVSS_O_COPY_PRIVATE] == 40);                         /* totals survive eviction */
    /* the NVSS_TOP most expensive surfaces appear, most expensive first */
    nvss_buf b = { malloc(8192), 0, 8192 };
    nvss_format_locked(&b, g_now);
    const char *p = b.p; int order[NVSS_TOP], n = 0;
    while ((p = strstr(p, "\nsurf ")) && n < NVSS_TOP + 1) { order[n < NVSS_TOP ? n : 0] = atoi(p + 6); n++; p += 6; }
    CHECK(n == NVSS_TOP);
    CHECK(order[0] == 139 && order[1] == 138 && order[2] == 137);
    free(b.p);
}

static void test_report_is_bounded(void)
{
    nvss_reset_for_test(); atomic_store(&nvss_on_flag, 1); atomic_store(&nvss_next_poll, ~0ull);
    for (int i = 0; i < 100000; i++) { g_now += 1; nvss_ev_out(1 + i % 5, 0, NVSS_O_COPY_REFUSED, 1000, 1, 1, 1, 1, 0x80000000u + (i % 50)); }
    CHECK(nvss_t.dirty_status_used == 8 && nvss_t.dirty_status_other > 0);
    nvss_buf b = { malloc(4096), 0, 4096 };                                /* even a tiny buffer is not overrun */
    nvss_format_locked(&b, g_now);
    CHECK(b.n < 4096);
    free(b.p);
}

int main(void)
{
    snprintf(g_dir, sizeof g_dir, "/tmp/nvss-test-%d", (int)getpid());
    mkdir(g_dir, 0700);
    snprintf(g_req, sizeof g_req, "%s/request", g_dir);
    g_now = 5000000000ull;
    test_precheck_matches_upstream();
    test_disabled_by_default();
    test_counters_and_report();
    test_bounded_eviction_and_top();
    test_report_is_bounded();
    DIR *d = opendir(g_dir); struct dirent *e; char p[600];
    while (d && (e = readdir(d))) if (e->d_name[0] != '.') { snprintf(p, sizeof p, "%s/%s", g_dir, e->d_name); unlink(p); }
    if (d) closedir(d);
    rmdir(g_dir);
    if (fails) { fprintf(stderr, "%d check(s) failed\n", fails); return 1; }
    puts("surfstat_test: all checks passed");
    return 0;
}
