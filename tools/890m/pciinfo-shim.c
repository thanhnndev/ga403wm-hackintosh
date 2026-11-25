// SPDX-License-Identifier: BSD-3-Clause-Clear
// Test shim (890M bring-up, docs/890M-TRACE.md Step33c): answers DRM_IOCTL_GET_PCIINFO in user space with the 890M's
// PCI identity, the way the fixed NMXGPU (fork dda9127) answers it, so RADV/Metal enumeration can be exercised on a
// kernel whose GET_PCIINFO still fails. Every other ioctl goes to the kernel (SHIM_TRACE=1 prints the ones that fail).
//   clang -dynamiclib -o build/pciinfo-shim.dylib pciinfo-shim.c
//   DYLD_INSERT_LIBRARIES=build/pciinfo-shim.dylib build/metal-devices
#include <errno.h>
#include <sys/stat.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

struct drm_pciinfo { uint16_t domain; uint8_t bus, dev, func; uint16_t vendor_id, device_id, subvendor_id, subdevice_id;
                     uint8_t revision_id; };
#define DRM_IOCTL_GET_PCIINFO _IOR('d', 0x15, struct drm_pciinfo)

static int shim_ioctl(int fd, unsigned long req, void *arg)
{
    struct stat st;
    if (req == DRM_IOCTL_GET_PCIINFO && fstat(fd, &st) == 0 && S_ISCHR(st.st_mode)) {
        struct drm_pciinfo pi = { 0, 101, 0, 0, 0x1002, 0x150e, 0x1043, 0x3998, 0xc1 };   // 0000:65:00.0, ASUS GA403WM
        memcpy(arg, &pi, sizeof(pi));
        return 0;
    }
    uint32_t pre[8] = {0};
    if (((req >> 8) & 0xff) == 'd' && (req & 0xff) >= 0x40 && (req & 0x80000000)) memcpy(pre, arg, ((req >> 16) & 0x1fff) < 32 ? ((req >> 16) & 0x1fff) : 32);
    int r = ioctl(fd, req, arg), e = errno;
    const char *tr = getenv("SHIM_TRACE");   // 1: failing ioctls; 2: every amdgpu ioctl
    if (tr && (r != 0 || tr[0] == '2') && ((req >> 8) & 0xff) == 'd' && (req & 0xff) >= 0x40) {
        uint32_t *w = arg;   // drm_amdgpu_info: u64 return_pointer, u32 return_size, u32 query
        fprintf(stderr, "shim: amdgpu ioctl nr 0x%02lx size %lu = %d errno %d  out %08x %08x %08x %08x in %08x %08x %08x %08x %08x %08x\n", req & 0xff,
                (req >> 16) & 0x1fff, r, r ? e : 0, w[0], w[1], w[2], w[3], pre[0], pre[1], pre[2], pre[3], pre[4], pre[5]);
    } else
    if (r != 0 && tr)   // SHIM_TRACE=1: print every failing ioctl on a device node
        fprintf(stderr, "shim: ioctl(%d, 0x%lx) = %d errno %d\n", fd, req, r, errno);
    errno = e;
    return r;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *rep, *orig; } interpose_ioctl
    = { (const void *)shim_ioctl, (const void *)ioctl };

#include <sys/mman.h>
static void *shim_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
    void *p = mmap(addr, len, prot, flags, fd, off); int e = errno;
    struct stat st;
    if (getenv("SHIM_TRACE") && fd >= 0 && fstat(fd, &st) == 0 && S_ISCHR(st.st_mode))
        fprintf(stderr, "shim: mmap(addr %p len 0x%zx prot %d flags 0x%x fd %d off 0x%llx) = %p errno %d\n", addr, len, prot, flags, fd,
                (unsigned long long)off, p, p == MAP_FAILED ? e : 0);
    errno = e;
    return p;
}
__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *rep, *orig; } interpose_mmap
    = { (const void *)shim_mmap, (const void *)mmap };
