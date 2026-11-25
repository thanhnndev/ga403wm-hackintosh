// SPDX-License-Identifier: BSD-3-Clause-Clear
// DYLD interpose: print the VkResult of vkCreateComputePipelines / vkCreateShaderModule (890M bring-up: NVMTL only says "FAILED").
//   clang -dynamiclib -o build/vk-trace-shim.dylib vk-trace-shim.c /Library/GPUBundles/nvmtl/libvulkan.1.dylib
//   DYLD_INSERT_LIBRARIES=build/vk-trace-shim.dylib build/nvmtltest
#include <stdint.h>
#include <stdio.h>
typedef int32_t VkResult;
extern VkResult vkCreateComputePipelines(void *, uint64_t, uint32_t, const void *, const void *, void *);
extern VkResult vkCreateShaderModule(void *, const void *, const void *, void *);
extern VkResult vkCreatePipelineLayout(void *, const void *, const void *, void *);
static VkResult my_cp(void *d, uint64_t c, uint32_t n, const void *ci, const void *a, void *p)
{ VkResult r = vkCreateComputePipelines(d, c, n, ci, a, p); fprintf(stderr, "[vk] vkCreateComputePipelines(n=%u) = %d\n", n, r); return r; }
static VkResult my_sm(void *d, const void *ci, const void *a, void *m)
{ VkResult r = vkCreateShaderModule(d, ci, a, m); fprintf(stderr, "[vk] vkCreateShaderModule = %d\n", r); return r; }
static VkResult my_pl(void *d, const void *ci, const void *a, void *m)
{ VkResult r = vkCreatePipelineLayout(d, ci, a, m); fprintf(stderr, "[vk] vkCreatePipelineLayout = %d\n", r); return r; }
#define IP(n, f) __attribute__((used)) static struct { const void *r, *o; } ip_##n __attribute__((section("__DATA,__interpose"))) = { (const void *)f, (const void *)n }
IP(vkCreateComputePipelines, my_cp); IP(vkCreateShaderModule, my_sm); IP(vkCreatePipelineLayout, my_pl);
