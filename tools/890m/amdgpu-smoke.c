// SPDX-License-Identifier: BSD-3-Clause-Clear
// Smoke test of the 890M through NullMoth's libdrm_amdgpu (what RADV's winsys does first): device init, GPU info,
// a GTT buffer mapped into the CPU and the GPU, and one GFX IB (PM4 WRITE_DATA) that stores a value the CPU reads back.
//   clang -o build/amdgpu-smoke amdgpu-smoke.c /Library/GPUBundles/nvmtl/libdrm_amdgpu.1.dylib && build/amdgpu-smoke
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// libdrm amdgpu.h (public API, declared here so the test needs no libdrm headers)
typedef struct amdgpu_device *amdgpu_device_handle;
typedef struct amdgpu_bo *amdgpu_bo_handle;
typedef struct amdgpu_context *amdgpu_context_handle;
typedef struct amdgpu_bo_list *amdgpu_bo_list_handle;
typedef struct amdgpu_va *amdgpu_va_handle;
struct amdgpu_bo_alloc_request { uint64_t alloc_size, phys_alignment; uint32_t preferred_heap; uint64_t flags; };
struct amdgpu_cs_ib_info { uint64_t flags, ib_mc_address; uint32_t size; };
struct amdgpu_cs_fence_info { amdgpu_bo_handle handle; uint64_t offset; };
struct amdgpu_cs_fence { amdgpu_context_handle context; uint32_t ip_type, ip_instance, ring; uint64_t fence; };
struct amdgpu_cs_request {
    uint64_t flags; unsigned ip_type, ip_instance; uint32_t ring; amdgpu_bo_list_handle resources;
    uint32_t number_of_dependencies; struct amdgpu_cs_fence *dependencies;
    uint32_t number_of_ibs; struct amdgpu_cs_ib_info *ibs; uint64_t seq_no; struct amdgpu_cs_fence_info fence_info;
};
int amdgpu_device_initialize(int fd, uint32_t *major, uint32_t *minor, amdgpu_device_handle *dev);
int amdgpu_query_info(amdgpu_device_handle dev, unsigned info_id, unsigned size, void *value);
int amdgpu_bo_alloc(amdgpu_device_handle dev, struct amdgpu_bo_alloc_request *req, amdgpu_bo_handle *bo);
int amdgpu_bo_cpu_map(amdgpu_bo_handle bo, void **cpu);
int amdgpu_va_range_alloc(amdgpu_device_handle dev, int type, uint64_t size, uint64_t align, uint64_t required,
                          uint64_t *va, amdgpu_va_handle *h, uint64_t flags);
int amdgpu_bo_va_op(amdgpu_bo_handle bo, uint64_t offset, uint64_t size, uint64_t addr, uint64_t flags, uint32_t ops);
int amdgpu_cs_ctx_create(amdgpu_device_handle dev, amdgpu_context_handle *ctx);
int amdgpu_bo_list_create(amdgpu_device_handle dev, uint32_t n, amdgpu_bo_handle *bos, uint8_t *prios,
                          amdgpu_bo_list_handle *list);
int amdgpu_cs_submit(amdgpu_context_handle ctx, uint64_t flags, struct amdgpu_cs_request *req, uint32_t n);
int amdgpu_cs_query_fence_status(struct amdgpu_cs_fence *f, uint64_t timeout_ns, uint64_t flags, uint32_t *expired);

#define AMDGPU_INFO_DEV_INFO 0x16
#define AMDGPU_GEM_DOMAIN_GTT 0x2
#define AMDGPU_GEM_CREATE_CPU_ACCESS_REQUIRED 0x1
#define AMDGPU_VA_OP_MAP 1
#define AMDGPU_VM_PAGE_READABLE 0x2
#define AMDGPU_VM_PAGE_WRITEABLE 0x4
#define AMDGPU_VM_PAGE_EXECUTABLE 0x8
#define AMDGPU_HW_IP_GFX 0
#define PKT3(op, n) (0xc0000000u | (((n) & 0x3fff) << 16) | ((op) << 8))
#define PKT3_WRITE_DATA 0x37
#define PKT3_NOP 0x10

#define CHECK(what, call) do { int r_ = (call); printf("%-28s %d%s%s\n", what, r_, r_ ? " " : "", r_ ? strerror(r_ < 0 ? -r_ : r_) : ""); if (r_) return 1; } while (0)

int main(int argc, char **argv)
{
    const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
    int fd = open(node, O_RDWR | O_CLOEXEC);
    if (fd < 0) { printf("open %s: %s\n", node, strerror(errno)); return 1; }
    uint32_t maj, min;
    amdgpu_device_handle dev;
    CHECK("amdgpu_device_initialize", amdgpu_device_initialize(fd, &maj, &min, &dev));
    printf("  drm %u.%u\n", maj, min);
    uint32_t info[64] = {0};   // struct drm_amdgpu_info_device: device_id, chip_rev, external_rev, pci_rev, family, ...
    CHECK("query DEV_INFO", amdgpu_query_info(dev, AMDGPU_INFO_DEV_INFO, sizeof(info), info));
    printf("  device_id 0x%x chip_rev %u external_rev 0x%x family %u num_shader_engines %u\n",
           info[0], info[1], info[2], info[4], info[5]);

    struct amdgpu_bo_alloc_request req = { 4096, 4096, AMDGPU_GEM_DOMAIN_GTT, AMDGPU_GEM_CREATE_CPU_ACCESS_REQUIRED };
    amdgpu_bo_handle bo;
    CHECK("bo_alloc (GTT 4K)", amdgpu_bo_alloc(dev, &req, &bo));
    uint32_t *cpu;
    CHECK("bo_cpu_map", amdgpu_bo_cpu_map(bo, (void **)&cpu));
    uint64_t va; amdgpu_va_handle vah;
    CHECK("va_range_alloc", amdgpu_va_range_alloc(dev, 0, 4096, 4096, 0, &va, &vah, 0));
    CHECK("bo_va_op MAP", amdgpu_bo_va_op(bo, 0, 4096, va, AMDGPU_VM_PAGE_READABLE | AMDGPU_VM_PAGE_WRITEABLE |
                                          AMDGPU_VM_PAGE_EXECUTABLE, AMDGPU_VA_OP_MAP));
    printf("  cpu %p gpu va 0x%llx\n", (void *)cpu, (unsigned long long)va);

    // IB at offset 0, the value lands at offset 1024 (dword 256)
    memset(cpu, 0, 4096);
    const uint64_t dst = va + 1024;
    uint32_t n = 0;
    cpu[n++] = PKT3(PKT3_WRITE_DATA, 3);
    cpu[n++] = (5u << 8) | (1u << 20);      // DST_SEL memory, WR_CONFIRM, ENGINE_SEL ME
    cpu[n++] = (uint32_t)dst;
    cpu[n++] = (uint32_t)(dst >> 32);
    cpu[n++] = 0x890d890d;
    while (n & 7) cpu[n++] = PKT3(PKT3_NOP, 0x3fff);   // single-dword NOP padding
    cpu[256] = 0xdeadbeef;

    amdgpu_context_handle ctx;
    CHECK("cs_ctx_create", amdgpu_cs_ctx_create(dev, &ctx));
    amdgpu_bo_list_handle list;
    CHECK("bo_list_create", amdgpu_bo_list_create(dev, 1, &bo, NULL, &list));
    struct amdgpu_cs_ib_info ib = { 0, va, n };
    struct amdgpu_cs_request cs = { 0 };
    cs.ip_type = AMDGPU_HW_IP_GFX; cs.resources = list; cs.number_of_ibs = 1; cs.ibs = &ib;
    CHECK("cs_submit (GFX)", amdgpu_cs_submit(ctx, 0, &cs, 1));
    struct amdgpu_cs_fence f = { ctx, AMDGPU_HW_IP_GFX, 0, 0, cs.seq_no };
    uint32_t expired = 0;
    CHECK("query_fence_status (1 s)", amdgpu_cs_query_fence_status(&f, 1000000000ull, 0, &expired));
    printf("  seq %llu expired %u, value 0x%08x (%s)\n", (unsigned long long)cs.seq_no, expired, cpu[256],
           cpu[256] == 0x890d890d ? "GPU wrote it" : "NOT written");
    return cpu[256] == 0x890d890d ? 0 : 2;
}
