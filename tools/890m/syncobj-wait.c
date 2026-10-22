// SPDX-License-Identifier: BSD-3-Clause-Clear
// Does DRM_IOCTL_SYNCOBJ_WAIT honour an absolute CLOCK_MONOTONIC deadline on the own-build NMXGPU? (890M bring-up,
// NVMTL got ETIME after 2 ms.) Waits 500 ms on a never-signalled syncobj, deadline built from each clock, and prints
// how long the ioctl really took.
//   clang -o build/syncobj-wait syncobj-wait.c /Library/GPUBundles/nvmtl/libdrm.2.dylib
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
int drmSyncobjCreate(int fd, uint32_t flags, uint32_t *handle);
int drmSyncobjWait(int fd, uint32_t *handles, unsigned n, int64_t timeout_nsec, unsigned flags, uint32_t *first);
static uint64_t now(clockid_t c) { return clock_gettime_nsec_np(c); }
int main(void)
{
    int fd = open("/dev/dri/renderD128", O_RDWR);
    uint32_t h; printf("create %d\n", drmSyncobjCreate(fd, 0, &h));
    struct { const char *n; clockid_t c; } cl[] = { { "MONOTONIC", CLOCK_MONOTONIC }, { "UPTIME_RAW", CLOCK_UPTIME_RAW }, { "MONOTONIC_RAW", CLOCK_MONOTONIC_RAW } };
    for (int i = 0; i < 3; i++) {
        uint32_t first = 0; uint64_t t0 = now(CLOCK_UPTIME_RAW);
        int r = drmSyncobjWait(fd, &h, 1, (int64_t)(now(cl[i].c) + 500000000ull), 1 /*WAIT_ALL*/ | 2 /*FOR_SUBMIT*/, &first);
        printf("%-14s ret %d errno %d after %.1f ms (expected ~500)\n", cl[i].n, r, r ? errno : 0, (now(CLOCK_UPTIME_RAW) - t0) / 1e6);
    }
    return 0;
}
