// SPDX-License-Identifier: BSD-3-Clause-Clear
// Stable public transport between Strix backend, future RADV/Metal, and tools.
// Little-endian, natural alignment; no kernel pointers or variable-sized input.
#ifndef STRIX_NATIVE_ABI_H
#define STRIX_NATIVE_ABI_H
#include <stdint.h>
#define S89N_UC_TYPE 0x5338394eu /* S89N: distinct from Cobalt's N48N */
#define S89N_MAGIC 0x5338394eu
#define S89N_ABI_MAJOR 1u
#define S89N_ABI_MINOR 1u
enum { S89N_HELLO = 0, S89N_QUERY_INFO = 1, S89N_FOUNDATION_READ = 2, S89N_SELECTOR_COUNT = 3 };
enum { S89N_BACKEND_NONE = 0, S89N_BACKEND_GFX115 = 1 };
enum { S89N_READY_DISPLAY_ONLY = 1, S89N_READY_COMPUTE = 2 };
enum {
    S89N_CAP_DISPLAY_PIPE = 1ull << 0,
    S89N_CAP_GPU_VM = 1ull << 1,
    S89N_CAP_SDMA = 1ull << 2,
    S89N_CAP_GFX_SUBMIT = 1ull << 3,
    S89N_CAP_FENCE_READBACK = 1ull << 4,
    S89N_CAP_RADV_DEVICE_INFO = 1ull << 5,
    S89N_CAP_FOUNDATION_READ = 1ull << 6
};
#define S89N_METAL_REQUIRED_CAPS (S89N_CAP_GPU_VM | S89N_CAP_GFX_SUBMIT | S89N_CAP_FENCE_READBACK | S89N_CAP_RADV_DEVICE_INFO)
typedef struct {
    uint32_t major, minor;
    uint64_t reserved[2];
} s89n_hello_request;
typedef struct {
    uint32_t magic, major, minor, size;
    uint64_t capabilities;
    uint64_t reserved;
} s89n_hello_reply;
typedef struct {
    uint32_t magic, major, minor, size;
    uint64_t capabilities;
    uint64_t accelerator_registry_id;
    uint64_t pci_registry_id;
    uint32_t vendor_device, revision_class, subsystem;
    uint32_t readiness, backend, expected_gc_ip, discovered_gc_ip, reserved0;
    char os_build[32];
    uint64_t reserved[7];
} s89n_info;
typedef struct {
    uint32_t magic, size;
    uint32_t rcc_memsize_mib, ip_discovery_version, psp_discovery_status, reserved0;
    uint64_t reserved;
} s89n_foundation;
#ifdef __cplusplus
static_assert(sizeof(s89n_hello_request) == 24, "Hello request ABI");
static_assert(sizeof(s89n_hello_reply) == 32, "Hello reply ABI");
static_assert(sizeof(s89n_info) == 160, "Info ABI");
static_assert(sizeof(s89n_foundation) == 32, "Foundation ABI");
#else
_Static_assert(sizeof(s89n_hello_request) == 24, "Hello request ABI");
_Static_assert(sizeof(s89n_hello_reply) == 32, "Hello reply ABI");
_Static_assert(sizeof(s89n_info) == 160, "Info ABI");
_Static_assert(sizeof(s89n_foundation) == 32, "Foundation ABI");
#endif
static inline int s89n_metal_ready(const s89n_info *info) {
    return info && info->magic == S89N_MAGIC && info->major == S89N_ABI_MAJOR &&
        info->size == sizeof(*info) && info->vendor_device == 0x150e1002 &&
        info->backend == S89N_BACKEND_GFX115 && info->readiness == S89N_READY_COMPUTE &&
        info->discovered_gc_ip == 0x000b0500 &&
        (info->capabilities & S89N_METAL_REQUIRED_CAPS) == S89N_METAL_REQUIRED_CAPS;
}
#endif
