// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step98/99 flip caves: what cave.c (dispatch, mode 2, submit/status) and import.c (mode 1 imports, VRAM-only
// buffer creation) share. Both are linked against the same NMXGPU addresses; the state is at 0x9270a0.
#pragma once
typedef unsigned long u64; typedef unsigned int u32; typedef long s64;
#pragma GCC visibility push(hidden)
extern int PRINTF(const char *fmt, ...);
extern int SNPRINTF(char *buf, u64 n, const char *fmt, ...);
extern const char FMT_S[];
#pragma GCC visibility pop
// layout from the real headers (scripts/nmx-flip/offsets.txt)
#define FB_BUFFER 120
#define FB_INFO 152
#define INFO_W 4
#define INFO_H 8
#define INFO_PITCH 12
#define INFO_PHYS 16
#define INFO_SIZE 24
#define INFO_KVA 32
#define CLIENT_MODESETS 104
#define BUF_GEM 16
#define BUF_PITCH 8
#define BUF_FB 40
#define MS_CRTC 8
#define MS_MODE 16
#define MS_SIZE 48
#define CRTC_PRIMARY 168
#define PLANE_STATE 1280
#define PSTATE_FB 16
#define CSTATE_COMMIT 320
#define AS_REF 0
#define AS_ACQUIRE_CTX 72
#define COMMIT_REF 8
#define COMMIT_FLIP_DONE 12
#define BO_GEM 72
#define DOMAIN_VRAM 4
#define FMT_XRGB8888 0x34325258
#define EDEADLK 11
#define EBUSY 16

#define R_OK 0
#define R_UNSUPPORTED 0xe00002c7u
#define R_BADARG 0xe00002c2u
#define R_BUSY 0xe00002d5u
#define R_NOTREADY 0xe00002d8u
#define R_ERROR 0xe00002bcu
#define NONE 0xffffffffu
#define NBUF 3

struct flipbuf { u64 phys; void *kva; u64 size; u64 gpu; u32 handle, pitch; };
struct req {
    u32 version, flags, handle, format, width, height, pitch, caps, maxImports, nbuffers;
    void *md; u64 offset, gpuAddr, seq, seqSubmitted, seqLatched;
    u32 current, pending, generation; int err;
    u64 vblankCount, vblankNs;
    struct flipbuf buf[NBUF];
};
_Static_assert(__builtin_offsetof(struct req, buf) == 120, "NMXFlipRequest layout");
_Static_assert(sizeof(struct flipbuf) == 40, "NMXFlipBuffer layout");

// imports (mode 1): handles IMP0 .. IMP0 + NIMP - 1, records in a table kmalloc'd on the first import
#define IMP0 8u
#define NIMP 4u
struct imp { char *fb, *gem, *sgt; void *md; u64 gpu; u32 fbid, gemh, fmt, used; };

struct st {
    volatile int lock;
    u32 inited, gen, current, pending, nbuf, logs, tried;
    u64 seqSub, seqLat;
    char *commit;                 // the pending flip's drm_crtc_commit (one reference held)
    char *crtc, *plane, *nfb;
    char *drmfb[NBUF];            // drm_framebuffer per handle
    char *buffer[NBUF];           // drm_client_buffer per handle (0 = home, the bridge's)
    u64 kva[NBUF], phys[NBUF], size[NBUF], gpu[NBUF];
    u32 pitch[NBUF];
    struct imp *imp;              // NIMP records
    u32 nimports, import_fail;
};
_Static_assert(sizeof(struct st) <= 352, "state fits the borrowed words");
#pragma GCC visibility push(hidden)
extern struct st ST;               // 352 bytes of dead CI dpm ratelimit state at 0x9270a0 (16-aligned)
#pragma GCC visibility pop
#define S (&ST)

static inline void lock(void) { while (__atomic_exchange_n(&S->lock, 1, __ATOMIC_ACQUIRE)) __builtin_ia32_pause(); }
static inline void unlock(void) { __atomic_store_n(&S->lock, 0, __ATOMIC_RELEASE); }

// amdgpu_device behind the bridge's DRM client: drm_to_adev (ddev at +16); mode_info.gpu_vm_support at +0x10de4
#define ADEV(nfb) (P(nfb, 0) - 16)
#define GPU_VM(nfb) (*(volatile unsigned char *)(ADEV(nfb) + 0x10de4) & 1)

// the drm_framebuffer behind a handle, 0 when the handle names nothing
static inline char *fb_of(u32 h)
{
    if (h < S->nbuf) return S->drmfb[h];
    if (h >= IMP0 && h < IMP0 + NIMP && S->imp && S->imp[h - IMP0].used) return S->imp[h - IMP0].fb;
    return 0;
}

#define LOG(...) do { if (S->logs < 40) { char b_[200]; S->logs++; SNPRINTF(b_, sizeof b_, __VA_ARGS__); PRINTF(FMT_S, b_); } } while (0)
#define P(p, off) (*(char **)((char *)(p) + (off)))
#define U32(p, off) (*(u32 *)((char *)(p) + (off)))
#define U64(p, off) (*(u64 *)((char *)(p) + (off)))
#define IS_ERR(p) ((u64)(p) >= (u64)-4095)
