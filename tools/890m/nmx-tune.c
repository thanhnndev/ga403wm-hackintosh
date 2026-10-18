// SPDX-License-Identifier: BSD-3-Clause-Clear
// nmx-tune get|set0|set1: read or switch NMXGPU's GTT cache mode (nmx_wc) at runtime; needs root for set.
//   cc -o build/nmx-tune nmx-tune.c
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct nmx_drm_sysfs_get { char name[64]; uint32_t len, pad; char value[4096]; };
#define GET _IOWR('N', 0x42, struct nmx_drm_sysfs_get)
#define PUT _IOW('N', 0x43, struct nmx_drm_sysfs_get)

int main(int argc, char **argv)
{
    static struct nmx_drm_sysfs_get sg;
    int fd = open("/dev/dri/renderD128", O_RDWR);
    if (fd < 0 || argc < 2) { perror("open /dev/dri/renderD128 / usage: nmx-tune get|set0|set1"); return 1; }
    strcpy(sg.name, "nmx_wc");
    if (!strcmp(argv[1], "get")) {
        if (ioctl(fd, GET, &sg)) { perror("get"); return 1; }
        printf("nmx_wc = %c\n", sg.value[0]);
    } else {
        sg.value[0] = argv[1][3]; sg.len = 1;
        if (ioctl(fd, PUT, &sg)) { perror("set"); return 1; }
        printf("nmx_wc set to %c\n", sg.value[0]);
    }
    return 0;
}
