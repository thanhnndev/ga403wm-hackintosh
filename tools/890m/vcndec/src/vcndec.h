// SPDX-License-Identifier: BSD-3-Clause-Clear
// vcndec: VP9 / AV1 decode on the Radeon 890M VCN through RADV Vulkan video (libavcodec hwaccel),
// output copied by the GPU into IOSurface-backed NV12 CVPixelBuffers (no CPU readback).
#pragma once
#include <CoreVideo/CoreVideo.h>
#include <stddef.h>
#include <stdint.h>

typedef struct vcn_dec vcn_dec;

// codec: 'vp09' or 'av01'. extradata: vpcC / av1C payload (may be NULL). Returns NULL and fills err on failure.
vcn_dec *vcn_open(uint32_t codec, int width, int height, const uint8_t *extradata, size_t extradata_size,
                  char *err, size_t errn);
// One compressed frame (VT sample). Returns 0 or a negative AVERROR.
int vcn_send(vcn_dec *d, const uint8_t *data, size_t size, int64_t pts);
// Signal end of stream (flush delayed frames).
int vcn_flush(vcn_dec *d);
// Next decoded frame into a new pixel buffer from `pool`. Returns 1 with *out set (caller releases),
// 0 when no frame is ready, < 0 on error. *pts gets the frame's pts.
int vcn_receive(vcn_dec *d, CVPixelBufferPoolRef pool, CVPixelBufferRef *out, int64_t *pts);
void vcn_close(vcn_dec *d);

// Stats for logging: frames out, GPU-copy frames, CPU-fallback frames, imported surfaces.
void vcn_stats(vcn_dec *d, uint64_t *frames, uint64_t *gpu_copies, uint64_t *cpu_copies, uint64_t *imports);
const char *vcn_last_error(vcn_dec *d);
