/*
 * Pending-page-off table of the NVAccel IOSurface VRAM sharing (local fix, not upstream).
 *
 * An entry means: "the VRAM copy of this IOSurface is newer than its system-memory copy, and the display path must
 * page it off before it reads the surface through the CPU". It is set by the dirty export (NVRM_ESC_SURF_DIRTY) that
 * lets the Metal plugin skip a GPU->RAM readback, and cleared by the page-off.
 *
 * Upstream 1.14.2 keys an entry by surface ID only and clears it only in the page-off. A surface that is written by the
 * GPU, sampled by the compositor and then destroyed without any CPU read is never paged off, so its entry stays for the
 * whole uptime; after NVSV_PEND_SLOTS of those every dirty export of a NEW surface is refused and each GPU write to it
 * falls back to the full readback. This table also remembers WHICH resource set the entry, so freeing the resource
 * can drop exactly its entries and nothing else (a surface ID that was meanwhile re-registered by another resource keeps
 * its own entry).
 *
 * Plain C, no includes: the kext and test/readback/pend_test.c use the same code. The caller holds the lock.
 */
#ifndef NVSV_PEND_H
#define NVSV_PEND_H

#ifndef NVSV_PEND_SLOTS
#define NVSV_PEND_SLOTS 512
#endif

enum { NVSV_PEND_DEL = 0, NVSV_PEND_ADD = 1, NVSV_PEND_TEST = 2 };

struct nvsv_pend {
    unsigned    id[NVSV_PEND_SLOTS];        /* 0 = free slot */
    const void *owner[NVSV_PEND_SLOTS];     /* the NVResource that marked it */
    long long   count, high, full, adds, dels, released;
};

/* NVSV_PEND_ADD: mark (id, owner) pending; true if it is pending afterwards, false if the table is full.
 * NVSV_PEND_TEST: true if any owner has the id pending.
 * NVSV_PEND_DEL: clear the id for every owner (the page-off copied the newest data to system memory); true if it was pending. */
static inline int nvsv_pend_op(struct nvsv_pend *t, unsigned id, const void *owner, int op)
{
    int found = 0, freeSlot = -1;
    if (!id) return 0;
    for (int i = 0; i < NVSV_PEND_SLOTS; i++) {
        if (t->id[i] == id) {
            if (op == NVSV_PEND_DEL) { t->id[i] = 0; t->owner[i] = 0; t->count--; t->dels++; found = 1; continue; }
            if (op == NVSV_PEND_TEST) return 1;
            if (t->owner[i] == owner) { found = 1; break; }    /* ADD: already pending for this resource */
        } else if (!t->id[i] && freeSlot < 0) freeSlot = i;
    }
    if (op == NVSV_PEND_ADD && !found) {
        if (freeSlot < 0) { t->full++; return 0; }
        t->id[freeSlot] = id; t->owner[freeSlot] = owner;
        t->count++; t->adds++;
        if (t->count > t->high) t->high = t->count;
        return 1;
    }
    return found;
}

/* The resource is being freed: drop every entry it set. Returns how many. */
static inline long long nvsv_pend_release(struct nvsv_pend *t, const void *owner)
{
    long long n = 0;
    if (!owner) return 0;
    for (int i = 0; i < NVSV_PEND_SLOTS; i++)
        if (t->id[i] && t->owner[i] == owner) { t->id[i] = 0; t->owner[i] = 0; t->count--; n++; }
    t->released += n;
    return n;
}
#endif
