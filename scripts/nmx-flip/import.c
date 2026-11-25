// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step99: zero-copy scan-out (flip mode 1) and VRAM-only buffer creation, the second flip cave (0x506580, in dead
// kv_dpm_sw_init). cave.c dispatches nmxFlipImport / nmxFlipRelease here and creates its mode-2 chain through
// fb_create_vram; the bridge's own home buffer goes through fb_create_vram too (nmx_fb_open's call at 0x6cd39d).
//
// With DC brought up with GPU VM (Step99 keeps amdgpu_sg_display at its default -1 instead of the bridge's 0),
// amdgpu offers GTT for scan-out buffers that have AMDGPU_GEM_CREATE_CPU_GTT_USWC, and an APU may then place a dumb
// buffer in GTT. fb_create_vram clears adev->mode_info.gpu_vm_support around drm_client_framebuffer_create so the
// bridge's buffers stay one contiguous VRAM range (the IOFramebuffer aperture and the K6 copy depend on that).
//
// An import makes a scan-out buffer out of the caller's memory (CoreDisplay's IOSurface, a prepared descriptor):
//   1. the descriptor's physical pages -> a flat sg_table (dma address = physical address, xkpi maps 1:1)
//   2. amdgpu_gem_object_create(CPU domain, CPU_GTT_USWC, ttm_bo_type_sg), the sg_table set on the BO and its ttm_tt
//      (TTM created the tt already, with TTM_TT_FLAG_EXTERNAL, so amdgpu binds the dma addresses from it)
//   3. pinned in GTT, a GART range bound (amdgpu_ttm_alloc_gart): gpu address = what DCN fetches
//   4. a GEM handle on the bridge's DRM file, drm_mode_addfb2 (linear, the surface's pitch), the drm_framebuffer
// The descriptor stays prepared by the caller until release. Release unpins and drops the fb and the handle; the
// sg_table is not freed (the BO may outlive the call until DRM drops its last fb reference).
#include "common.h"

#pragma GCC visibility push(hidden)
extern char *DRM_CLIENT_FB_CREATE(char *client, u32 w, u32 h, u32 fmt);
extern void DRM_GEM_LOCK(char *gem);
extern void DRM_GEM_UNLOCK(char *gem);
extern int AMDGPU_BO_PIN(char *bo, u32 domain);
extern void AMDGPU_BO_UNPIN(char *bo);
extern u64 AMDGPU_BO_GPU_OFFSET(char *bo);
extern int AMDGPU_TTM_ALLOC_GART(char *tbo);
extern int GEM_OBJECT_CREATE(char *adev, u64 size, int align, u32 domain, u64 flags, int type, char *resv, char **obj,
                             int xcp_id_plus1);
extern void GEM_OBJECT_FREE(char *ref);             // drm_gem_object_free(struct kref *)
extern int GEM_HANDLE_CREATE(char *file, char *obj, u32 *handle);
extern int GEM_HANDLE_DELETE(char *file, u32 handle);
extern int ADDFB2(char *dev, void *cmd, char *file);
extern char *FB_LOOKUP(char *dev, char *file, u32 id);
extern void MODE_OBJECT_PUT(char *obj);
extern int RMFB(char *dev, u32 id, char *file);
extern void *KMALLOC(u64 size, u32 gfp);
#pragma GCC visibility pop

#define CLIENT_FILE 40
#define BO_TBO 0x48
#define BO_TTM 544
#define BO_SG 632
#define TT_SG 24
#define TT_FLAGS 16
#define TT_EXTERNAL 4
#define SG_SIZE 40
#define SG_LENGTH 12
#define SG_DMA_ADDR 16
#define SG_DMA_LEN 24
#define SG_END 2
#define FB_BASE 24
#define GFP_KERNEL 2
#define DOMAIN_CPU 1
#define DOMAIN_GTT 2
#define GTT_USWC 4
#define TYPE_SG 2
#define FMT_XRGB2101010 0x30335258
#define MD_GETPHYS 0x138                            // IOMemoryDescriptor::getPhysicalSegment vtable slot (as nmx_xnu_user_wire calls it)
#define MAPPER_NONE 0x800

struct fbcmd { u32 fb_id, width, height, pixel_format, flags, handles[4], pitches[4], offsets[4], pad; u64 modifier[4]; };
_Static_assert(sizeof(struct fbcmd) == 104, "drm_mode_fb_cmd2");

char *fb_create_vram(char *client, u32 w, u32 h, u32 fmt)
{
    volatile unsigned char *vm = (volatile unsigned char *)(P(client, 0) - 16 + 0x10de4);
    unsigned char was = *vm;
    *vm = 0;
    char *b = DRM_CLIENT_FB_CREATE(client, w, h, fmt);
    *vm = was;
    return b;
}

static u64 phys_of(void *md, u64 off, u64 *len)
{
    typedef u64 (*gp_t)(void *, u64, u64 *, u32);
    return ((gp_t)(*(char ***)md)[MD_GETPHYS / 8])(md, off, len, MAPPER_NONE);
}

static void gem_put(char *gem) { if (__atomic_sub_fetch((int *)gem, 1, __ATOMIC_ACQ_REL) == 0) GEM_OBJECT_FREE(gem); }

static u32 fail(struct req *r, const char *what, int e)
{
    S->import_fail++;
    LOG("NMX flip: import failed at %s (%d)", what, e);
    r->err = e;
    return R_ERROR;
}

u32 flip_import(struct req *r)
{
    if (!GPU_VM(S->nfb)) return R_UNSUPPORTED;
    if (!r->md || !r->width || !r->height || r->pitch < 4 * r->width || (r->pitch & 255)) return R_BADARG;
    u32 fmt = r->format == 1 ? FMT_XRGB8888 : r->format == 2 ? FMT_XRGB2101010 : 0;
    if (!fmt) return R_BADARG;
    if (!S->imp) {
        struct imp *t = KMALLOC(sizeof(struct imp) * NIMP, GFP_KERNEL);
        if (!t) return fail(r, "table", -12);
        for (u32 i = 0; i < sizeof(struct imp) * NIMP; i++) ((char *)t)[i] = 0;
        S->imp = t;
    }
    u32 slot = NONE;
    lock();
    for (u32 i = 0; i < NIMP; i++) if (!S->imp[i].used) { slot = i; S->imp[i].used = 2; break; }   // 2 = being built
    unlock();
    if (slot == NONE) return R_BUSY;
    struct imp *m = &S->imp[slot];

    u64 size = ((u64)r->pitch * r->height + 4095) & ~4095ul, n = size / 4096, nents = 0;
    char *sgt = KMALLOC(16 + n * SG_SIZE, GFP_KERNEL);
    if (!sgt) { m->used = 0; return fail(r, "sg alloc", -12); }
    char *sgl = sgt + 16, *e = 0;
    for (u64 i = 0; i < n; i++) {
        u64 len = 0, pa = phys_of(r->md, r->offset + i * 4096, &len);
        if (!pa || (pa & 4095)) { m->used = 0; return fail(r, "descriptor page", (int)i); }   // sg_table leaked
        if (e && U64(e, SG_DMA_ADDR) + U32(e, SG_DMA_LEN) == pa) { U32(e, SG_DMA_LEN) += 4096; U32(e, SG_LENGTH) += 4096; continue; }
        e = sgl + nents++ * SG_SIZE;
        for (int k = 0; k < SG_SIZE; k++) e[k] = 0;
        U64(e, SG_DMA_ADDR) = pa; U32(e, SG_DMA_LEN) = 4096; U32(e, SG_LENGTH) = 4096;
    }
    U64(e, 0) |= SG_END;
    P(sgt, 0) = sgl; U32(sgt, 8) = (u32)nents; U32(sgt, 12) = (u32)nents;

    char *adev = ADEV(S->nfb), *gem = 0, *file = P(S->nfb, CLIENT_FILE);
    int err = GEM_OBJECT_CREATE(adev, size, 4096, DOMAIN_CPU, GTT_USWC, TYPE_SG, 0, &gem, 0);
    if (err || !gem) { m->used = 0; return fail(r, "gem create", err); }
    char *bo = gem - BO_TBO, *tt = P(bo, BO_TTM);
    P(bo, BO_SG) = sgt;
    if (!tt || !(U32(tt, TT_FLAGS) & TT_EXTERNAL)) { gem_put(gem); m->used = 0; return fail(r, "no external tt", tt ? (int)U32(tt, TT_FLAGS) : -1); }
    P(tt, TT_SG) = sgt;

    u64 gpu = 0;
    DRM_GEM_LOCK(gem);
    err = AMDGPU_BO_PIN(bo, DOMAIN_GTT);
    if (!err && (err = AMDGPU_TTM_ALLOC_GART(bo + BO_TBO))) AMDGPU_BO_UNPIN(bo);
    if (!err) gpu = AMDGPU_BO_GPU_OFFSET(bo);
    DRM_GEM_UNLOCK(gem);
    if (err) { gem_put(gem); m->used = 0; return fail(r, "pin gtt", err); }

    u32 h = 0;
    if ((err = GEM_HANDLE_CREATE(file, gem, &h))) { DRM_GEM_LOCK(gem); AMDGPU_BO_UNPIN(bo); DRM_GEM_UNLOCK(gem); gem_put(gem); m->used = 0; return fail(r, "handle", err); }
    gem_put(gem);                                      // the handle holds the object now
    struct fbcmd c;
    for (u32 i = 0; i < sizeof c; i++) ((char *)&c)[i] = 0;
    c.width = r->width; c.height = r->height; c.pixel_format = fmt; c.handles[0] = h; c.pitches[0] = r->pitch;
    char *dev = P(S->nfb, 0), *fb;
    if ((err = ADDFB2(dev, &c, file)) || !(fb = FB_LOOKUP(dev, file, c.fb_id))) {
        DRM_GEM_LOCK(gem); AMDGPU_BO_UNPIN(bo); DRM_GEM_UNLOCK(gem);
        GEM_HANDLE_DELETE(file, h); m->used = 0;
        return fail(r, "addfb2", err ? err : -2);
    }
    MODE_OBJECT_PUT(fb + FB_BASE);                     // the file's fb list holds it
    m->fb = fb; m->gem = gem; m->sgt = sgt; m->md = r->md; m->gpu = gpu; m->fbid = c.fb_id; m->gemh = h; m->fmt = fmt;
    __atomic_store_n(&m->used, 1, __ATOMIC_RELEASE);
    S->nimports++;
    r->handle = IMP0 + slot; r->gpuAddr = gpu;
    LOG("NMX flip: import %u: %ux%u pitch %u fmt %x, %llu pages in %llu runs, gpu %llx, fb %llx", IMP0 + slot, r->width, r->height,
        r->pitch, fmt, n, nents, gpu, (u64)fb);
    return R_OK;
}

// cave.c has checked the handle is neither on screen nor pending
u32 flip_release_import(u32 h)
{
    if (!S->imp || h < IMP0 || h >= IMP0 + NIMP || S->imp[h - IMP0].used != 1) return R_BADARG;
    struct imp *m = &S->imp[h - IMP0];
    char *dev = P(S->nfb, 0), *file = P(S->nfb, CLIENT_FILE), *bo = m->gem - BO_TBO;
    lock(); m->used = 2; unlock();
    DRM_GEM_LOCK(m->gem); AMDGPU_BO_UNPIN(bo); DRM_GEM_UNLOCK(m->gem);
    RMFB(dev, m->fbid, file);
    GEM_HANDLE_DELETE(file, m->gemh);
    m->fb = 0; m->gem = 0;
    __atomic_store_n(&m->used, 0, __ATOMIC_RELEASE);
    LOG("NMX flip: released import %u", h);
    return R_OK;
}
