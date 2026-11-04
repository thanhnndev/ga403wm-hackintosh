// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step98: page-flip API on the NMXGPU display bridge, mode 2 (VRAM swap chain + vblank-latched flips), as a cave in
// the installed NMXGPU (it has no reproducible source build: ~15 binary steps sit on the 2026-10-23 build).
//
// NMXAccel (ci/nmxaccel-flip) calls NMXGPUFB::callPlatformFunction(sym, false, req, ...) with the names below.
// The hook is the "name is not nvScanoutInfo" branch at 0x6e3b23: unknown names go on to IOFramebuffer as before.
//
//   nmxFlipCaps     SUBMIT | VRAM_CHAIN | XRGB8888, the lit mode, generation
//   nmxFlipBuffers  home (handle 0) + up to 2 more XRGB8888 VRAM buffers from the bridge's DRM client, all pinned
//   nmxFlipSubmit   non-blocking atomic commit of the primary plane's fb (DC fast update, latched at vblank)
//   nmxFlipStatus   latched = the commit's flip_done; never sleeps
//   nmxFlipRelease  busy while on screen or pending, else success (chain buffers stay)
//   nmxFlipImport   unsupported (mode 1 needs DC with GPU VM, a separate boot)
//
// Pinning: amdgpu GEM objects have no .pin, so a buffer is pinned only while DC scans it. Flipping away from the home
// buffer would let TTM evict it under the kva that IOFramebuffer and the K6 copy publish. All chain buffers, home
// included, are pinned in VRAM once and never unpinned.
//
// Generation: the bridge commits its home fb itself (restore, hotplug, display power). Status notices the plane's fb is
// not the one it last latched and bumps generation; current then names whatever is really on screen.

#include "common.h"

#pragma GCC visibility push(hidden)
extern char FBS[];                                    // static fbs[MAX_FB] { dev, fb } in nmx_fb_bridge.c
extern char *DRM_CLIENT_FB_CREATE(char *client, u32 w, u32 h, u32 fmt);
extern void DRM_CLIENT_FB_DELETE(char *buffer);
extern int DRM_CLIENT_BUFFER_VMAP(char *buffer, char *map);
extern void DRM_GEM_LOCK(char *gem);
extern void DRM_GEM_UNLOCK(char *gem);
extern int AMDGPU_BO_PIN(char *bo, u32 domain);
extern u64 AMDGPU_BO_GPU_OFFSET(char *bo);
extern u64 KVA_TO_PHYS(const char *va);
extern void ACQ_INIT(char *ctx, u32 flags);
extern void ACQ_FINI(char *ctx);
extern void DROP_LOCKS(char *ctx);
extern int BACKOFF(char *ctx);
extern char *STATE_ALLOC(char *dev);
extern void STATE_CLEAR(char *state);
extern void STATE_FREE(char *ref);                    // __drm_atomic_state_free(struct kref *)
extern char *GET_PLANE_STATE(char *state, char *plane);
extern char *GET_CRTC_STATE(char *state, char *crtc);
extern void SET_FB_FOR_PLANE(char *pstate, char *fb);
extern int NONBLOCKING_COMMIT(char *state);
extern void COMMIT_FREE(char *ref);                   // __drm_crtc_commit_free(struct kref *)
extern u64 VBLANK_COUNT_AND_TIME(char *crtc, s64 *ns);
extern char *FB_CREATE_VRAM(char *client, u32 w, u32 h, u32 fmt);   // import.c: drm_client_framebuffer_create in VRAM
extern u32 FLIP_IMPORT(void *r);                                    // import.c: nmxFlipImport
extern u32 FLIP_RELEASE_IMPORT(u32 h);                              // import.c: free an import (not on screen, not pending)
#pragma GCC visibility pop





static void kref_put(char *ref, void (*release)(char *))
{
    if (__atomic_sub_fetch((int *)ref, 1, __ATOMIC_ACQ_REL) == 0) release(ref);
}

static void commit_put(char *c) { kref_put(c + COMMIT_REF, COMMIT_FREE); }

// pin a client buffer's BO in VRAM (never unpinned); its MC address goes to gpu
static int pin(char *buffer, u64 *gpu)
{
    char *gem = P(buffer, BUF_GEM), *bo = gem - BO_GEM;
    DRM_GEM_LOCK(gem);
    int e = AMDGPU_BO_PIN(bo, DOMAIN_VRAM);
    if (!e) *gpu = AMDGPU_BO_GPU_OFFSET(bo);
    DRM_GEM_UNLOCK(gem);
    return e;
}

static int init(void)
{
    if (S->inited) return 1;
    char *nfb = P(FBS, 8);                            // fbs[0].fb
    // fb->info.ok stays 0: nmx_fb_open sets ok on its caller's copy after storing fb->info. kva and size are set.
    if (!nfb || !U64(nfb, FB_INFO + INFO_KVA) || !U64(nfb, FB_INFO + INFO_SIZE) || !P(nfb, FB_BUFFER)) return 0;
    char *ms = P(nfb, CLIENT_MODESETS), *crtc = 0;
    for (int i = 0; ms && P(ms, MS_CRTC) && i < 8; i++, ms += MS_SIZE)
        if (P(ms, MS_MODE)) { crtc = P(ms, MS_CRTC); break; }
    if (!crtc || !P(crtc, CRTC_PRIMARY)) return 0;
    S->nfb = nfb; S->crtc = crtc; S->plane = P(crtc, CRTC_PRIMARY);
    S->buffer[0] = P(nfb, FB_BUFFER);
    S->drmfb[0] = P(S->buffer[0], BUF_FB);
    S->kva[0] = U64(nfb, FB_INFO + INFO_KVA); S->phys[0] = U64(nfb, FB_INFO + INFO_PHYS);
    S->size[0] = U64(nfb, FB_INFO + INFO_SIZE); S->pitch[0] = U32(nfb, FB_INFO + INFO_PITCH);
    S->current = 0; S->pending = NONE; S->nbuf = 1;
    // the home buffer must stay in VRAM whatever is on screen: DC unpins it when a flip moves away from it
    int e = pin(S->buffer[0], &S->gpu[0]);
    if (e) { LOG("NMX flip: home buffer would not pin (%d), no flips", e); return 0; }
    __atomic_store_n(&S->inited, 1, __ATOMIC_RELEASE);
    LOG("NMX flip: API up, crtc %llx plane %llx home fb %llx %ux%u pitch %u", (u64)crtc, (u64)S->plane,
        (u64)S->drmfb[0], U32(nfb, FB_INFO + INFO_W), U32(nfb, FB_INFO + INFO_H), S->pitch[0]);
    return 1;
}

static u32 do_buffers(struct req *r)
{
    if (!S->tried) {
        S->tried = 1;
        u32 w = U32(S->nfb, FB_INFO + INFO_W), h = U32(S->nfb, FB_INFO + INFO_H);
        int e;
        for (u32 i = 1; i < NBUF; i++) {
            char *b = FB_CREATE_VRAM(S->nfb, w, h, FMT_XRGB8888);
            if (IS_ERR(b) || !b) { LOG("NMX flip: buffer %u not created (%ld)", i, (s64)b); break; }
            if ((e = pin(b, &S->gpu[i]))) { LOG("NMX flip: buffer %u would not pin (%d)", i, e); DRM_CLIENT_FB_DELETE(b); break; }
            char map[16];
            if ((e = DRM_CLIENT_BUFFER_VMAP(b, map))) { LOG("NMX flip: buffer %u would not map (%d)", i, e); break; }   // stays pinned: leak, never freed
            const char *va = *(char **)map;
            u32 pitch = U32(b, BUF_PITCH);
            u64 size = (u64)pitch * h, base = KVA_TO_PHYS(va), off;
            for (off = 4096; off < size; off += 4096)
                if (KVA_TO_PHYS(va + off) != base + off) break;
            if (!base || off < size) { LOG("NMX flip: buffer %u not contiguous (page %llu)", i, off / 4096); break; }
            S->buffer[i] = b; S->drmfb[i] = P(b, BUF_FB);
            S->kva[i] = (u64)va; S->phys[i] = base; S->size[i] = (size + 4095) & ~4095ul; S->pitch[i] = pitch;
            S->nbuf = i + 1;
            LOG("NMX flip: buffer %u fb %llx phys %llx gpu %llx pitch %u", i, (u64)S->drmfb[i], base, S->gpu[i], pitch);
        }
        LOG("NMX flip: chain of %u (home gpu %llx)", S->nbuf, S->gpu[0]);
    }
    r->nbuffers = S->nbuf;
    for (u32 i = 0; i < S->nbuf; i++) {
        r->buf[i].phys = S->phys[i]; r->buf[i].kva = (void *)S->kva[i]; r->buf[i].size = S->size[i];
        r->buf[i].gpu = S->gpu[i]; r->buf[i].handle = i; r->buf[i].pitch = S->pitch[i];
    }
    return S->nbuf > 1 ? R_OK : R_ERROR;
}

// lock held. Retire a pending flip whose commit has signalled flip_done; notice a bridge commit.
static void refresh(void)
{
    if (S->commit && __atomic_load_n((u32 *)(S->commit + COMMIT_FLIP_DONE), __ATOMIC_ACQUIRE)) {
        commit_put(S->commit); S->commit = 0;
        S->current = S->pending; S->pending = NONE; S->seqLat = S->seqSub;
    }
    if (S->pending == NONE) {
        char *ps = P(S->plane, PLANE_STATE), *fb = ps ? P(ps, PSTATE_FB) : 0;
        if (fb && fb != fb_of(S->current)) {
            u32 h = NONE;
            for (u32 i = 0; i < IMP0 + NIMP; i++) if (fb_of(i) == fb) h = i;
            S->gen++;
            LOG("NMX flip: on screen is fb %llx (handle %d), not handle %u: generation %u", (u64)fb, (int)h, S->current, S->gen);
            S->current = h == NONE ? 0 : h;
        }
    }
}

static u32 do_submit(struct req *r)
{
    u32 h = r->handle;
    char *nfbp = fb_of(h);
    if (!nfbp) return R_BADARG;
    lock();
    refresh();
    if (S->pending != NONE) { unlock(); return R_BUSY; }
    S->pending = h;                                   // reserved; status reports it pending from here
    unlock();

    char ctx[40];
    ACQ_INIT(ctx, 0);
    char *state = STATE_ALLOC(P(S->nfb, 0));          // client->dev
    int e = -12;
    char *commit = 0;
    if (state) {
        P(state, AS_ACQUIRE_CTX) = ctx;
        for (;;) {
            char *ps = GET_PLANE_STATE(state, S->plane), *cs;
            if (IS_ERR(ps)) { e = (int)(s64)ps; goto deadlk; }
            SET_FB_FOR_PLANE(ps, nfbp);
            cs = GET_CRTC_STATE(state, S->crtc);
            if (IS_ERR(cs)) { e = (int)(s64)cs; goto deadlk; }
            e = NONBLOCKING_COMMIT(state);
            if (!e) {
                commit = P(cs, CSTATE_COMMIT);        // locks still held: nothing can swap the CRTC state yet
                if (commit) __atomic_add_fetch((int *)(commit + COMMIT_REF), 1, __ATOMIC_ACQ_REL);
                break;
            }
        deadlk:
            if (e != -EDEADLK) break;
            STATE_CLEAR(state);
            BACKOFF(ctx);
        }
        kref_put(state + AS_REF, STATE_FREE);
    }
    DROP_LOCKS(ctx);
    ACQ_FINI(ctx);

    lock();
    if (e || !commit) {
        S->pending = NONE;
        if (commit) commit_put(commit);
        unlock();
        LOG("NMX flip: submit of handle %u failed (%d%s)", h, e, e ? "" : ", no commit");
        r->err = e ? e : -22;
        return e == -EBUSY ? R_BUSY : R_ERROR;
    }
    S->commit = commit;
    r->seq = ++S->seqSub;
    unlock();
    return R_OK;
}

static u32 do_status(struct req *r)
{
    s64 ns = 0;
    lock();
    refresh();
    r->seqSubmitted = S->seqSub; r->seqLatched = S->seqLat;
    r->current = S->current; r->pending = S->pending; r->generation = S->gen;
    unlock();
    r->vblankCount = VBLANK_COUNT_AND_TIME(S->crtc, &ns);
    r->vblankNs = (u64)ns;
    return R_OK;
}

static int is(char *sym, const char *name)
{
    typedef int (*eq_t)(char *, const char *);
    return ((eq_t)(*(char ***)sym)[0x158 / 8])(sym, name) & 0xff;
}

// -1: not a flip call (IOFramebuffer handles it); otherwise the IOReturn
s64 flip_dispatch(char *sym, struct req *r)
{
    int fn = is(sym, "nmxFlipStatus") ? 5 : is(sym, "nmxFlipSubmit") ? 4 : is(sym, "nmxFlipCaps") ? 0 :
             is(sym, "nmxFlipBuffers") ? 2 : is(sym, "nmxFlipRelease") ? 3 : is(sym, "nmxFlipImport") ? 1 : -1;
    if (fn < 0) return -1;
    if (!r || r->version != 1) return R_BADARG;
    if (!init()) return R_NOTREADY;
    r->err = 0;
    switch (fn) {
    case 0:
        r->caps = 1u | 4u | 0x100u; r->maxImports = 0;
        if (GPU_VM(S->nfb)) { r->caps |= 2u | 0x200u; r->maxImports = NIMP; }   // DC scans GTT only with GPU VM on
        r->width = U32(S->nfb, FB_INFO + INFO_W); r->height = U32(S->nfb, FB_INFO + INFO_H); r->pitch = S->pitch[0];
        r->generation = S->gen;
        return R_OK;
    case 1: return FLIP_IMPORT(r);
    case 2: return do_buffers(r);
    case 3: {
        u32 busy;
        lock(); refresh(); busy = r->handle == S->current || r->handle == S->pending; unlock();
        if (busy) return R_BUSY;
        return r->handle >= IMP0 ? FLIP_RELEASE_IMPORT(r->handle) : R_OK;
    }
    case 4: return do_submit(r);
    default: return do_status(r);
    }
}

// Jumped to from 0x6e3b23 (je, when the name is not nvScanoutInfo), inside NMXGPUFB::callPlatformFunction after its
// prologue (push rbp, 5 pushes, sub $8: rsp is 16-byte aligned here). Registers hold the original arguments.
__asm__(".section .text.entry,\"ax\",@progbits\n"
        ".globl entry\n"
        "entry:\n"
        " pushq %rdi\n pushq %rsi\n pushq %rdx\n pushq %rcx\n pushq %r8\n pushq %r9\n"
        " movq %rsi, %rdi\n movq %rcx, %rsi\n"
        " call flip_dispatch\n"
        " popq %r9\n popq %r8\n popq %rcx\n popq %rdx\n popq %rsi\n popq %rdi\n"
        " cmpq $-1, %rax\n"
        " je SUPER_PATH\n"
        " addq $8, %rsp\n popq %rbx\n popq %r12\n popq %r13\n popq %r14\n popq %r15\n popq %rbp\n ret\n");
