// SPDX-License-Identifier: BSD-3-Clause-Clear
// Test shim (890M bring-up, docs/890M-TRACE.md Step33c): answers DRM_IOCTL_GET_PCIINFO in user space with the 890M's
// PCI identity, the way the fixed NMXGPU (fork dda9127) answers it, so RADV/Metal enumeration can be exercised on a
// kernel whose GET_PCIINFO still fails. Every other ioctl goes to the kernel (SHIM_TRACE=1 prints the ones that fail).
//   clang -dynamiclib -o build/pciinfo-shim.dylib pciinfo-shim.c
//   DYLD_INSERT_LIBRARIES=build/pciinfo-shim.dylib build/metal-devices
#include <errno.h>
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
    int r = ioctl(fd, req, arg);
    if (r != 0 && getenv("SHIM_TRACE"))   // SHIM_TRACE=1: print every failing ioctl on a device node
        fprintf(stderr, "shim: ioctl(%d, 0x%lx) = %d errno %d\n", fd, req, r, errno);
    return r;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *rep, *orig; } interpose_ioctl
    = { (const void *)shim_ioctl, (const void *)ioctl };
