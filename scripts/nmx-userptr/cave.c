// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step92: amdgpu userptr (DRM_AMDGPU_GEM_USERPTR) for NMXGPU, without HMM.
//
// The NMXGPU build has no CONFIG_HMM_MIRROR / CONFIG_DRM_AMDGPU_USERPTR: amdgpu_hmm_register() is the stub that warns
// "HMM_MIRROR kernel config option is not enabled" and returns -ENODEV, so the compiler dropped the rest of
// amdgpu_gem_userptr_ioctl and every import of host memory fails (RADV VK_EXT_external_memory_host: "vkAllocateMemory
// refused the imported host pointer"). NVMTL then copies every IOSurface in and out of a private image with the CPU
// (nvmtlSurfaceIn / nvmtlSurfaceOut), the largest share of WindowServer's CPU after Step91.
//
// The model here has no MMU notifier: the user pages are pinned once when the BO is made (xkpi's get_user_pages,
// an IOMemoryDescriptor wiring on the task) and held for the BO's lifetime; amdgpu_ttm_tt_unpopulate drops them.
// The submit path then never re-fetches pages (its "invalidated" checks are skipped by the NOPs in the patch).
// What the GPU sees is always the pages the process had when it imported the range, which is what NVMTL wants:
// it imports an IOSurface's allocation and keeps the surface alive while its texture lives.
//
// Built with clang for an ELF target (no libc, no globals: __TEXT is read-only) and placed by elflink2.py.
// Offsets are from NMXGPU as installed after Step91 (disassembly in docs/890M-TRACE.md Step92).
typedef unsigned long u64;
typedef unsigned int u32;
typedef unsigned char u8;

#pragma GCC visibility push(hidden)
extern int AMDGPU_BO_RESERVE(void *bo, int no_intr);                    // amdgpu_bo_reserve (outlined copy)
extern void AMDGPU_BO_UNRESERVE(void *bo);                              // amdgpu_bo_unreserve
extern void PLACEMENT_FROM_DOMAIN(void *bo, u32 domain);                // amdgpu_bo_placement_from_domain
extern int TTM_BO_VALIDATE(void *tbo, void *placement, void *ctx);      // ttm_bo_validate
extern int DRM_GEM_HANDLE_CREATE(void *filp, void *obj, u32 *handlep);  // drm_gem_handle_create
extern long LKPI_GET_USER_PAGES(u64 start, u64 nr, u32 gup, void **pages);
extern void RELEASE_PAGES(void **pages, int n);                         // linux_release_pages (put_page each)
extern int SNPRINTF(char *buf, u64 n, const char *fmt, ...);            // a "jmp _snprintf" site
extern int PRINTF(const char *fmt, ...);                                // a "jmp _printf" site
extern const char FMT_S[];                                              // NMXGPU's own "%s\n"
extern u8 LOG_BUDGET;                                                   // amdgpu_hmm_register.__print_once (unused now)
#pragma GCC visibility pop

#define TBO_TTM        0x1d8   // ttm_buffer_object.ttm
#define BO_TBO         0x48    // amdgpu_bo.tbo
#define BO_PLACEMENT   0x38    // amdgpu_bo.placement
#define TT_PAGES       0x00    // ttm_tt.pages
#define TT_NUM_PAGES   0x14    // ttm_tt.num_pages
#define DOMAIN_GTT     2
#define F_READONLY     1
#define F_VALIDATE     4
#define FOLL_WRITE     1

struct userptr_args { u64 addr, size; u32 flags, handle; };

static void say(const char *what, u64 addr, u64 size, long v)
{
    if (LOG_BUDGET >= 24)
        return;
    LOG_BUDGET++;
    char b[160];
    SNPRINTF(b, sizeof b, "NMX userptr: %s addr %llx size %llx -> %ld", what, addr, size, v);
    PRINTF(FMT_S, b);
}

static void drop(void **pages, u32 n)
{
    for (u32 i = 0; i < n; i++)
        if (pages[i]) {
            RELEASE_PAGES(&pages[i], 1);
            pages[i] = 0;
        }
}

// Rest of amdgpu_gem_userptr_ioctl after amdgpu_ttm_tt_set_userptr succeeded. The caller drops its own reference to
// the object afterwards (release_object), as upstream does.
int userptr_tail(char *tbo, struct userptr_args *a, void *filp)
{
    char *bo = tbo - BO_TBO;
    char *ttm = *(char **)(tbo + TBO_TTM);
    void **pages = *(void ***)(ttm + TT_PAGES);
    u32 n = *(u32 *)(ttm + TT_NUM_PAGES);
    u32 handle = 0;
    int r;

    // pinned even without AMDGPU_GEM_USERPTR_VALIDATE: nothing else fills the page array in this model
    long got = LKPI_GET_USER_PAGES(a->addr, n, (a->flags & F_READONLY) ? 0 : FOLL_WRITE, pages);
    if (got != (long)n) {
        if (got > 0)
            drop(pages, (u32)got);
        say("pin FAILED", a->addr, a->size, got);
        return got < 0 ? (int)got : -14;   // -EFAULT
    }
    if (a->flags & F_VALIDATE) {
        r = AMDGPU_BO_RESERVE(bo, 1);
        if (r) {
            drop(pages, n);
            say("reserve FAILED", a->addr, a->size, r);
            return r;
        }
        PLACEMENT_FROM_DOMAIN(bo, DOMAIN_GTT);
        u64 ctx[3] = { 1, 0, 0 };   // ttm_operation_ctx { .interruptible = true }
        r = TTM_BO_VALIDATE(tbo, bo + BO_PLACEMENT, ctx);
        AMDGPU_BO_UNRESERVE(bo);
        if (r) {
            // not bound; unpopulate skips the NULL entries if the TT was populated
            drop(pages, n);
            say("validate FAILED", a->addr, a->size, r);
            return r;
        }
    }
    r = DRM_GEM_HANDLE_CREATE(filp, tbo, &handle);
    if (r) {
        // the pages stay with the BO; the caller's put destroys it and unpopulate drops them
        say("handle FAILED", a->addr, a->size, r);
        return r;
    }
    a->handle = handle;
    say("pinned", a->addr, a->size, (long)n);
    return 0;
}

// Replaces amdgpu_ttm_tt_set_user_pages(ttm, NULL) in amdgpu_ttm_tt_unpopulate's userptr branch.
void userptr_release(char *ttm)
{
    drop(*(void ***)(ttm + TT_PAGES), *(u32 *)(ttm + TT_NUM_PAGES));
}

// Fixed entry points (placed first): +0 the ioctl prologue detour, +8 the ioctl tail, +16 the unpopulate release.
__asm__(
    "  .section .text.entry,\"ax\",@progbits\n"
    "  .globl entry\n"
    "entry:\n"
    "  jmp pro\n"
    "  .balign 8\n"
    "  jmp tail_glue\n"
    "  .balign 8\n"
    "  jmp userptr_release\n"
    "  .balign 8\n"
    // the 7 bytes replaced at the ioctl's 0x5a7c8, plus: keep filp (rdx) in the frame's free slot at rsp
    "pro:\n"
    "  movq %rsi, %r14\n"
    "  addq $-0x10, %rdi\n"
    "  movq %rdx, -0x60(%rbp)\n"
    "  jmp IOCTL_RESUME\n"
    // from 0x5a86b (set_userptr returned 0): rbx = &bo->tbo (the GEM object), r14 = args; rsp = rbp - 0x60 (aligned)
    "tail_glue:\n"
    "  movq %rbx, %rdi\n"
    "  movq %r14, %rsi\n"
    "  movq -0x60(%rbp), %rdx\n"
    "  call userptr_tail\n"
    "  jmp IOCTL_RELEASE\n"
    "  .text\n");
