// SPDX-License-Identifier: BSD-3-Clause-Clear
#include "../kexts/StrixGOP/GopLayout.h"
#include <cassert>
#include <cstdio>

int main() {
    GopLayout g {0x880000000ull, 0x10000000, 0, 2880, 1800, 11520, 32, 0};
    uint64_t raster;
    assert(!validateGopLayout(g, raster) && raster == 20736000);
    auto invalid = g; invalid.barLength = raster - 1; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.stride = 11519; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.offset = UINT64_MAX; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.barBase = UINT64_MAX - 4095; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.offset = 4; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.rotation = 1; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.depth = 30; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.width = 0; assert(validateGopLayout(invalid, raster));
    invalid = g; invalid.height = 16385; assert(validateGopLayout(invalid, raster));
    // Raster fits, but the final mapped page would escape the resource.
    invalid = g; invalid.width = 1; invalid.height = 1; invalid.stride = 4;
    invalid.barLength = 4; assert(validateGopLayout(invalid, raster));
    invalid.barLength = 4096; assert(!validateGopLayout(invalid, raster));
    // Padded stride and nonzero page-aligned offsets must remain supported.
    invalid = g; invalid.stride = 12288; invalid.offset = 4096;
    assert(!validateGopLayout(invalid, raster) && raster == 22118400);
    puts("StrixGOP layout: 13 boundary cases PASS");
}
