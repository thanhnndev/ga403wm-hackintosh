// SPDX-License-Identifier: BSD-3-Clause-Clear
// Minimal Vulkan compute pipeline (empty main) straight on RADV, without NVMTL: is vkCreateComputePipelines itself failing on the 890M?
//   clang -o build/vk-compute-min vk-compute-min.c -Wl,-rpath,/Library/GPUBundles/nvmtl /Library/GPUBundles/nvmtl/libvulkan.1.dylib
//   VK_DRIVER_FILES=/Library/GPUBundles/nvmtl/radeon_icd.json RADV_DEBUG=startup,shaders build/vk-compute-min
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef struct { uint32_t sType; const void *pNext; } Base;
typedef void *H; typedef uint64_t NH;
extern int vkCreateInstance(const void *, const void *, H *);
extern int vkEnumeratePhysicalDevices(H, uint32_t *, H *);
extern int vkCreateDevice(H, const void *, const void *, H *);
extern int vkCreateShaderModule(H, const void *, const void *, NH *);
extern int vkCreatePipelineLayout(H, const void *, const void *, NH *);
extern int vkCreateComputePipelines(H, NH, uint32_t, const void *, const void *, NH *);
extern void vkGetPhysicalDeviceQueueFamilyProperties(H, uint32_t *, void *);
int main(void)
{ setvbuf(stdout, 0, _IONBF, 0);
    struct { uint32_t s; const void *n; const char *an; uint32_t av; const char *en; uint32_t ev, api; } app = { 0, 0, "t", 1, "t", 1, (1u << 22) | (1 << 12) };
    struct { uint32_t s; const void *n; uint32_t f; const void *app; uint32_t lc; const char *const *l; uint32_t ec; const char *const *e; }
        ici = { 1, 0, 0, &app, 0, 0, 0, 0 };
    ici.s = 1; app.s = 0;
    H inst; int r = vkCreateInstance(&ici, 0, &inst); printf("vkCreateInstance %d\n", r); if (r) return 1;
    uint32_t n = 1; H pd; r = vkEnumeratePhysicalDevices(inst, &n, &pd); printf("enumerate %d n=%u\n", r, n); if (n < 1) return 1;
    float prio = 1;
    struct { uint32_t s; const void *n; uint32_t f, qf, qc; const float *p; } dq = { 2, 0, 0, 0, 1, &prio };
    struct { uint32_t s; const void *n; uint32_t f, qc; const void *q; uint32_t lc; const void *l; uint32_t ec; const void *e; const void *feat; }
        dci = { 3, 0, 0, 1, &dq, 0, 0, 0, 0, 0 };
    H dev; r = vkCreateDevice(pd, &dci, 0, &dev); printf("vkCreateDevice %d\n", r); if (r) return 1;
    static const uint32_t spv[] = { 0x07230203, 0x00010000, 0, 5, 0, 0x00020011, 1, 0x0003000E, 0, 1, 0x0005000F, 5, 1, 0x6e69616d, 0,
        0x00060010, 1, 17, 1, 1, 1, 0x00020013, 2, 0x00030021, 3, 2, 0x00050036, 2, 1, 0, 3, 0x000200F8, 4, 0x000100FD, 0x00010038 };
    struct { uint32_t s; const void *n; uint32_t f; size_t sz; const uint32_t *c; } smi = { 16, 0, 0, sizeof spv, spv };
    NH sm; r = vkCreateShaderModule(dev, &smi, 0, &sm); printf("vkCreateShaderModule %d\n", r); if (r) return 1;
    struct { uint32_t s; const void *n; uint32_t f, sl; const void *l; uint32_t pc; const void *p; } pli = { 30, 0, 0, 0, 0, 0, 0 };
    NH pl; r = vkCreatePipelineLayout(dev, &pli, 0, &pl); printf("vkCreatePipelineLayout %d\n", r); if (r) return 1;
    struct { uint32_t s; const void *n; uint32_t f, stage; NH mod; const char *name; const void *spec; } st = { 18, 0, 0, 0x20, sm, "main", 0 };
    struct { uint32_t s; const void *n; uint32_t f; struct { uint32_t s; const void *n; uint32_t f, stage; NH mod; const char *name; const void *spec; } st; NH layout, base; int32_t bi; }
        cpi = { 29, 0, 0, { 18, 0, 0, 0x20, sm, "main", 0 }, pl, 0, -1 };
    NH pipe; r = vkCreateComputePipelines(dev, 0, 1, &cpi, 0, &pipe); printf("vkCreateComputePipelines %d\n", r);
    return r != 0;
}
