// SPDX-License-Identifier: BSD-3-Clause-Clear
// Opens a DRM node through NullMoth's libdrm and prints the driver version (890M bring-up, docs/890M-TRACE.md Step30).
//   clang -o build/drm-open drm-open.c && build/drm-open [/dev/dri/renderD128]
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
typedef struct { int major, minor, patch; int name_len; char *name; int date_len; char *date; int desc_len; char *desc; } drm_version;
int main(int argc, char **argv) {
    const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
    void *h = dlopen("/Library/GPUBundles/nvmtl/libdrm.2.dylib", RTLD_NOW);
    if (!h) { printf("dlopen libdrm: %s\n", dlerror()); return 1; }
    int (*get_devices)(unsigned, void **, int) = dlsym(h, "drmGetDevices2");
    drm_version *(*get_version)(int) = dlsym(h, "drmGetVersion");
    printf("drmGetDevices2: %d\n", get_devices ? get_devices(0, NULL, 0) : -1);
    int fd = open(node, O_RDWR | O_CLOEXEC);
    if (fd < 0) { printf("open %s: %s (%d)\n", node, strerror(errno), errno); return 1; }
    drm_version *v = get_version ? get_version(fd) : NULL;
    if (v) printf("open %s: driver %s %d.%d.%d (%s)\n", node, v->name, v->major, v->minor, v->patch, v->desc);
    else printf("open %s ok, drmGetVersion failed: %s\n", node, strerror(errno));
    close(fd);
    return 0;
}
