/* Host test for patches/nullmoth-readback/files/kexts/NVRM/accel/nvsv_pend.h (the pending-page-off table). */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define NVSV_PEND_SLOTS 512
#include "../../patches/nullmoth-readback/files/kexts/NVRM/accel/nvsv_pend.h"

static int fails;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); fails++; } } while (0)

/* ---- upstream 1.14.2 nvSVPend(), verbatim apart from the lock, as the oracle ---- */
enum { kNVSVPend = 512 };
static unsigned gNVSVPendId[kNVSVPend];
static int up_pend(unsigned id, int op)
{
    if (!id) return 0;
    int r = 0, freeSlot = -1;
    for (int i = 0; i < kNVSVPend; i++) {
        if (gNVSVPendId[i] == id) { r = 1; if (op == 0) gNVSVPendId[i] = 0; break; }
        if (!gNVSVPendId[i] && freeSlot < 0) freeSlot = i;
    }
    if (op == 1 && !r) { if (freeSlot >= 0) { gNVSVPendId[freeSlot] = id; r = 1; } }
    else if (op == 1) r = 1;
    return r;
}

static struct nvsv_pend T;
static const void *own(unsigned id) { static char pool[1 << 16]; return &pool[id % sizeof pool]; }

/* 1. With one owner per id and no release the new table answers exactly like upstream for any sequence of ops. */
static void test_equivalent_to_upstream(void)
{
    memset(&T, 0, sizeof T); memset(gNVSVPendId, 0, sizeof gNVSVPendId);
    unsigned s = 7;
    for (int i = 0; i < 400000; i++) {
        s = s * 1664525u + 1013904223u;
        unsigned id = 1 + (s >> 8) % 700;                       /* more ids than slots: the full case is exercised */
        int op = (s >> 4) % 3;                                  /* 0 del, 1 add, 2 test */
        int a = up_pend(id, op), b = nvsv_pend_op(&T, id, own(id), op);
        CHECK(a == b);
        if (a != b) return;
    }
    long long used = 0; for (int i = 0; i < NVSV_PEND_SLOTS; i++) used += T.id[i] != 0;
    CHECK(used == T.count);
}

/* 2. The leak: surfaces that are dirtied, sampled and destroyed without a page-off. Upstream saturates; the keyed table does not. */
static void test_leak_fixed_by_release(void)
{
    memset(&T, 0, sizeof T); memset(gNVSVPendId, 0, sizeof gNVSVPendId);
    int up_refused = 0, new_refused = 0;
    for (unsigned id = 1000; id < 1000 + 5000; id++) {        /* 5000 short-lived window surfaces */
        if (!up_pend(id, 1)) up_refused++;
        if (!nvsv_pend_op(&T, id, own(id), NVSV_PEND_ADD)) new_refused++;
        nvsv_pend_release(&T, own(id));                      /* the resource is freed */
    }
    CHECK(up_refused == 5000 - 512);                          /* upstream: refuses every surface after the 512th */
    CHECK(new_refused == 0);
    CHECK(T.count == 0 && T.high == 1 && T.released == 5000);
}

/* 3. Releasing one resource never touches another's entries, even for the same surface ID (ABA after re-registration). */
static void test_release_is_exact(void)
{
    memset(&T, 0, sizeof T);
    static char A, B, C;
    CHECK(nvsv_pend_op(&T, 42, &A, NVSV_PEND_ADD));
    CHECK(nvsv_pend_op(&T, 43, &C, NVSV_PEND_ADD));
    CHECK(nvsv_pend_op(&T, 42, &B, NVSV_PEND_ADD));           /* surface 42 re-registered by a newer resource */
    CHECK(T.count == 3);
    CHECK(nvsv_pend_release(&T, &A) == 1);                    /* the old resource dies late */
    CHECK(nvsv_pend_op(&T, 42, 0, NVSV_PEND_TEST));           /* B's entry survives: the surface is still pending */
    CHECK(nvsv_pend_op(&T, 43, 0, NVSV_PEND_TEST));
    CHECK(nvsv_pend_release(&T, &B) == 1);
    CHECK(!nvsv_pend_op(&T, 42, 0, NVSV_PEND_TEST));
    CHECK(nvsv_pend_op(&T, 43, 0, NVSV_PEND_TEST));
    CHECK(nvsv_pend_release(&T, 0) == 0);                     /* a null owner releases nothing */
    CHECK(T.count == 1);
}

/* 4. A page-off clears the surface for every owner; adding the same (id, owner) twice takes one slot. */
static void test_pageoff_and_idempotent_add(void)
{
    memset(&T, 0, sizeof T);
    static char A, B;
    CHECK(nvsv_pend_op(&T, 7, &A, NVSV_PEND_ADD) && nvsv_pend_op(&T, 7, &A, NVSV_PEND_ADD));
    CHECK(T.count == 1 && T.adds == 1);
    CHECK(nvsv_pend_op(&T, 7, &B, NVSV_PEND_ADD) && T.count == 2);
    CHECK(nvsv_pend_op(&T, 7, 0, NVSV_PEND_DEL));
    CHECK(T.count == 0 && T.dels == 2);
    CHECK(!nvsv_pend_op(&T, 7, 0, NVSV_PEND_DEL));
    CHECK(!nvsv_pend_op(&T, 0, &A, NVSV_PEND_ADD));           /* id 0 is never pending */
}

/* 5. A live pending surface is never evicted to make room: when the table is full the new surface is refused (safe fallback). */
static void test_full_refuses_instead_of_evicting(void)
{
    memset(&T, 0, sizeof T);
    for (unsigned id = 1; id <= NVSV_PEND_SLOTS; id++) CHECK(nvsv_pend_op(&T, id, own(id), NVSV_PEND_ADD));
    CHECK(!nvsv_pend_op(&T, 9999, own(9999), NVSV_PEND_ADD) && T.full == 1);
    for (unsigned id = 1; id <= NVSV_PEND_SLOTS; id++) CHECK(nvsv_pend_op(&T, id, 0, NVSV_PEND_TEST));
    CHECK(T.high == NVSV_PEND_SLOTS);
    nvsv_pend_release(&T, own(5));
    CHECK(nvsv_pend_op(&T, 9999, own(9999), NVSV_PEND_ADD));
}

int main(void)
{
    test_equivalent_to_upstream();
    test_leak_fixed_by_release();
    test_release_is_exact();
    test_pageoff_and_idempotent_add();
    test_full_refuses_instead_of_evicting();
    if (fails) { fprintf(stderr, "%d check(s) failed\n", fails); return 1; }
    puts("pend_test: all checks passed");
    return 0;
}
