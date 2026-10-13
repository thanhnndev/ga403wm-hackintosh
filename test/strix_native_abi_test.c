// SPDX-License-Identifier: BSD-3-Clause-Clear
#include "../include/StrixNativeABI.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    s89n_info info;
    unsigned char *bytes = (unsigned char *)&info;
    for (unsigned i = 0; i < sizeof(info); ++i) bytes[i] = 0;
    assert(!s89n_metal_ready(NULL)); assert(!s89n_metal_ready(&info));
    info.magic = S89N_MAGIC; info.major = S89N_ABI_MAJOR; info.size = sizeof(info);
    info.vendor_device = 0x150e1002; info.readiness = S89N_READY_DISPLAY_ONLY;
    info.expected_gc_ip = 0x000b0500; info.capabilities = S89N_CAP_DISPLAY_PIPE;
    assert(!s89n_metal_ready(&info)); // A working display is not sufficient.
    info.backend = S89N_BACKEND_GFX115; info.readiness = S89N_READY_COMPUTE;
    info.discovered_gc_ip = 0x000b0500; info.capabilities = S89N_METAL_REQUIRED_CAPS;
    assert(s89n_metal_ready(&info));
    for (uint64_t bit = 1; bit <= S89N_CAP_RADV_DEVICE_INFO; bit <<= 1) {
        if (!(S89N_METAL_REQUIRED_CAPS & bit)) continue;
        info.capabilities &= ~bit; assert(!s89n_metal_ready(&info)); info.capabilities |= bit;
    }
    info.vendor_device = 0x75501002; assert(!s89n_metal_ready(&info)); info.vendor_device = 0x150e1002;
    info.discovered_gc_ip = 0x000c0001; assert(!s89n_metal_ready(&info)); info.discovered_gc_ip = 0x000b0500;
    info.major++; assert(!s89n_metal_ready(&info)); info.major--;
    info.size--; assert(!s89n_metal_ready(&info));
    puts("Strix native ABI sizes/readiness/identity gates PASS"); return 0;
}
