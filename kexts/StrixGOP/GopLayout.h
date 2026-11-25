// SPDX-License-Identifier: BSD-3-Clause-Clear
#pragma once
#include <stdint.h>

struct GopLayout {
    uint64_t barBase, barLength, offset;
    uint32_t width, height, stride, depth, rotation;
};

// No hardware dependency. Validate before exposing any writable aperture.
inline const char *validateGopLayout(const GopLayout &g, uint64_t &raster) {
    raster = 0;
    if (!g.barBase || !g.barLength || g.barBase > UINT64_MAX - g.barLength)
        return "invalid-bar-range";
    if (!g.width || !g.height || g.width > 16384 || g.height > 16384)
        return "invalid-geometry";
    if (g.depth != 32 || g.rotation != 0) return "unsupported-pixel-layout";
    if (g.stride < uint64_t(g.width) * 4 || (g.stride & 3)) return "invalid-stride";
    raster = uint64_t(g.stride) * g.height;
    if (g.offset > g.barLength || raster > g.barLength - g.offset)
        return "raster-outside-bar";
    if ((g.barBase + g.offset) & 4095) return "unaligned-aperture";
    // IOGraphics maps complete pages. Never expose a tail beyond BAR0.
    if (raster > UINT64_MAX - 4095 || ((raster + 4095) & ~uint64_t(4095)) > g.barLength - g.offset)
        return "rounded-raster-outside-bar";
    return nullptr;
}
