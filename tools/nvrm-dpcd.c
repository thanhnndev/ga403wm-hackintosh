// nvrm-dpcd: read-only probe of the built-in panel's eDP DPCD (backlight registers) and RM's get-brightness, from user
// space, no root: NVRM user client -> root client / device / subdevice / NV04_DISPLAY_COMMON ->
// NV0073_CTRL_CMD_DP_AUXCH_CTRL. `nvrm-dpcd [displayId]` reads; `nvrm-dpcd 0x200 test [full]` writes 0x722/3 and 0x721 = 2,
// steps 100 / 50 / 12 / 100 % and restores the original bytes. See docs/OLED-BRIGHTNESS-DPCD.md.
// O=~/ogkm610; cc -arch x86_64 -O1 -Wno-everything -I$O/src/common/sdk/nvidia/inc -I$O/src/common/sdk/nvidia/inc/class \
//   -I$O/src/common/sdk/nvidia/inc/ctrl -I$O/src/nvidia/arch/nvalloc/unix/include -I$O/src/common/inc \
//   -I$O/kernel-open/common/inc -I$O/src/nvidia/inc/kernel tools/nvrm-dpcd.c -framework IOKit -framework CoreFoundation -o nvrm-dpcd
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <IOKit/IOKitLib.h>
#include "nvtypes.h"
#include "nvos.h"
#include "nv_escape.h"
#include "nvstatus.h"
#include "class/cl0080.h"
#include "class/cl2080.h"
#include "class/cl0073.h"
#include "ctrl/ctrl0000/ctrl0000gpu.h"
#include "ctrl/ctrl0073/ctrl0073dp.h"
#include "ctrl/ctrl0073/ctrl0073specific.h"
#include "ctrl/ctrl0073/ctrl0073system.h"
#include "nvos.h"

enum { SEL_ESC = 1 };
static io_connect_t conn;
static NvHandle hClient, hDevice, hSub, hDisp;

static int esc(uint32_t cmd, void *data, size_t size)
{
    uint64_t in = cmd; size_t out = size;
    kern_return_t kr = IOConnectCallMethod(conn, SEL_ESC, &in, 1, data, size, NULL, NULL, data, &out);
    if (kr) { fprintf(stderr, "esc 0x%x -> kr 0x%x\n", cmd, kr); return -1; }
    return 0;
}
static NvU32 rmAlloc(NvHandle parent, NvHandle *h, NvU32 cls, void *params)
{
    NVOS21_PARAMETERS p; memset(&p, 0, sizeof p);
    p.hRoot = hClient; p.hObjectParent = parent; p.hObjectNew = *h; p.hClass = cls; p.pAllocParms = (NvP64)(uintptr_t)params;
    if (esc(NV_ESC_RM_ALLOC, &p, sizeof p)) return 0xFFFF;
    *h = p.hObjectNew; return p.status;
}
static NvU32 rmCtl(NvHandle obj, NvU32 cmd, void *params, NvU32 size)
{
    NVOS54_PARAMETERS p; memset(&p, 0, sizeof p);
    p.hClient = hClient; p.hObject = obj; p.cmd = cmd; p.params = (NvP64)(uintptr_t)params; p.paramsSize = size;
    if (esc(NV_ESC_RM_CONTROL, &p, sizeof p)) return 0xFFFF;
    return p.status;
}
static int auxRead(NvU32 id, NvU32 addr, uint8_t *buf, int n)
{
    NV0073_CTRL_DP_AUXCH_CTRL_PARAMS p; memset(&p, 0, sizeof p);
    p.subDeviceInstance = 0; p.displayId = id;
    p.cmd = DRF_DEF(0073_CTRL, _DP, _AUXCH_CMD_TYPE, _AUX) | DRF_DEF(0073_CTRL, _DP, _AUXCH_CMD_REQ_TYPE, _READ);
    p.addr = addr; p.size = n - 1;
    NvU32 st = rmCtl(hDisp, NV0073_CTRL_CMD_DP_AUXCH_CTRL, &p, sizeof p);
    if (st) { fprintf(stderr, "AUX read 0x%x status 0x%x\n", addr, st); return -1; }
    if (p.replyType != 0 && p.replyType != NV0073_CTRL_DP_AUXCH_REPLYTYPE_ACK) fprintf(stderr, "  (reply type %u)\n", p.replyType);
    int got = p.size; if (got > n) got = n;
    memcpy(buf, p.data, got);
    return got;
}
static int auxWrite(NvU32 id, NvU32 addr, const uint8_t *buf, int n)
{
    NV0073_CTRL_DP_AUXCH_CTRL_PARAMS p; memset(&p, 0, sizeof p);
    p.subDeviceInstance = 0; p.displayId = id;
    p.cmd = DRF_DEF(0073_CTRL, _DP, _AUXCH_CMD_TYPE, _AUX) | DRF_DEF(0073_CTRL, _DP, _AUXCH_CMD_REQ_TYPE, _WRITE);
    p.addr = addr; p.size = n - 1; memcpy(p.data, buf, n);
    NvU32 st = rmCtl(hDisp, NV0073_CTRL_CMD_DP_AUXCH_CTRL, &p, sizeof p);
    if (st) { fprintf(stderr, "AUX write 0x%x status 0x%x\n", addr, st); return -1; }
    return p.size;
}
static void setLevel(NvU32 id, unsigned lvl)
{
    uint8_t b[2] = { (uint8_t)(lvl >> 8), (uint8_t)lvl };
    int w = auxWrite(id, 0x722, b, 2);
    uint8_t r[4]; int g = auxRead(id, 0x720, r, 8 > 4 ? 4 : 4);
    printf("  level 0x%04x written (%d) -> DPCD 0x720..723 = %02x %02x %02x %02x\n", lvl, w, r[0], r[1], r[2], r[3]);
    fflush(stdout);
}
static void dump(NvU32 id, NvU32 addr, int n)
{
    uint8_t b[16]; int g = auxRead(id, addr, b, n);
    printf("DPCD 0x%03x:", addr);
    if (g < 0) { printf(" read failed\n"); return; }
    for (int i = 0; i < g; i++) printf(" %02x", b[i]);
    printf("\n");
}
int main(int argc, char **argv)
{
    NvU32 id = argc > 1 ? (NvU32)strtoul(argv[1], 0, 0) : 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("NVRM"));
    if (!svc) { fprintf(stderr, "no NVRM service\n"); return 1; }
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    if (kr) { fprintf(stderr, "IOServiceOpen 0x%x\n", kr); return 1; }
    NvU32 st = rmAlloc(0, &hClient, NV01_ROOT_CLIENT, NULL);
    printf("root client: status 0x%x handle 0x%x\n", st, hClient);
    if (st) return 1;
    NV0000_CTRL_GPU_GET_ATTACHED_IDS_PARAMS ids; memset(&ids, 0, sizeof ids);
    for (int i = 0; i < NV0000_CTRL_GPU_MAX_ATTACHED_GPUS; i++) ids.gpuIds[i] = NV0000_CTRL_GPU_INVALID_ID;
    st = rmCtl(hClient, NV0000_CTRL_CMD_GPU_GET_ATTACHED_IDS, &ids, sizeof ids);
    printf("attached ids: status 0x%x first 0x%x\n", st, ids.gpuIds[0]);
    NV0000_CTRL_GPU_GET_ID_INFO_V2_PARAMS info; memset(&info, 0, sizeof info); info.gpuId = ids.gpuIds[0];
    st = rmCtl(hClient, NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2, &info, sizeof info);
    printf("id info: status 0x%x dev %u subdev %u\n", st, info.deviceInstance, info.subDeviceInstance);
    NV0080_ALLOC_PARAMETERS a80; memset(&a80, 0, sizeof a80); a80.deviceId = info.deviceInstance; a80.hClientShare = hClient;
    NV2080_ALLOC_PARAMETERS a20; memset(&a20, 0, sizeof a20); a20.subDeviceId = info.subDeviceInstance;
    st = rmAlloc(hClient, &hDevice, NV01_DEVICE_0, &a80);      printf("device: 0x%x\n", st);
    if (!st) { hSub = 0; st = rmAlloc(hDevice, &hSub, NV20_SUBDEVICE_0, &a20); printf("subdevice: 0x%x\n", st); }
    if (!st) { hDisp = 0; st = rmAlloc(hDevice, &hDisp, NV04_DISPLAY_COMMON, NULL); printf("display common: 0x%x\n", st); }
    if (st) return 1;
    NV0073_CTRL_SYSTEM_GET_SUPPORTED_PARAMS sup; memset(&sup, 0, sizeof sup);
    st = rmCtl(hDisp, NV0073_CTRL_CMD_SYSTEM_GET_SUPPORTED, &sup, sizeof sup);
    printf("supported: status 0x%x mask 0x%x\n", st, sup.displayMask);
    if (!id) id = 0x200;
    printf("probing display 0x%x\n", id);
    dump(id, 0x000, 16);   // DPCD rev, link rate, lanes, ...
    dump(id, 0x700, 8);    // eDP rev, general caps 1..3
    dump(id, 0x720, 8);    // backlight adjustment + brightness (0x720 cap/ctl, 0x721 mode, 0x722/3 brightness)
    dump(id, 0x728, 8);    // PWM gen
    dump(id, 0x730, 8);
    for (int type = 1; type <= 3; type++) {
        NV0073_CTRL_SPECIFIC_BACKLIGHT_BRIGHTNESS_PARAMS g; memset(&g, 0, sizeof g);
        g.subDeviceInstance = 0; g.displayId = id; g.brightnessType = type;
        st = rmCtl(hDisp, NV0073_CTRL_CMD_SPECIFIC_GET_BACKLIGHT_BRIGHTNESS, &g, sizeof g);
        printf("RM get brightness type %d: status 0x%x value %u\n", type, st, g.brightness);
    }
    if (argc > 2 && !strcmp(argv[2], "test")) {
        uint8_t o[4]; auxRead(id, 0x720, o, 4);           // 720 display control, 721 mode, 722/723 brightness
        printf("original 0x720..723 = %02x %02x %02x %02x\n", o[0], o[1], o[2], o[3]);
        unsigned full = argc > 3 ? strtoul(argv[3], 0, 0) : 0x07FF;
        printf("TEST: DPCD brightness mode, full=0x%x -- watch the OLED\n", full);
        setLevel(id, full);
        uint8_t m = 0x02; auxWrite(id, 0x721, &m, 1);     // DPCD brightness control mode
        sleep(3);
        printf("-> 50%%\n"); setLevel(id, full / 2); sleep(3);
        printf("-> 12%%\n"); setLevel(id, full / 8); sleep(3);
        printf("-> 100%%\n"); setLevel(id, full); sleep(2);
        auxWrite(id, 0x721, &o[1], 1);                    // back to the original mode
        auxWrite(id, 0x722, &o[2], 2);
        uint8_t r[4]; auxRead(id, 0x720, r, 4);
        printf("restored 0x720..723 = %02x %02x %02x %02x\n", r[0], r[1], r[2], r[3]);
    }
    return 0;
}
