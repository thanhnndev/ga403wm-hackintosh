// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Shared ring between RogAudio.driver and rogaudiod: the final ROG Speakers mix, so rogaudiod can run the sound chain
// without opening an input stream (any open input lights the macOS microphone indicator).
//
// The driver host process ("Core Audio Driver (RogAudio.driver)", user _coreaudiod, not sandboxed) creates the object at
// Initialize, mode 0644, after unlinking any old one. One writer (the driver's ROG Speakers WriteMix), any number of readers.
// The writer stores frames at wpos % kShmFrames and then publishes wpos (release). A reader keeps its own position, copies
// [rpos, wpos), and re-reads wpos afterwards: if the writer got more than kShmFrames ahead meanwhile, the copy is discarded.
#pragma once
#include <stdatomic.h>
#include <stdint.h>

#define ROG_SHM_NAME "/com.itlmt7925.rogspk"     // macOS limit: 31 characters
#define ROG_SHM_MAGIC 0x48534752u                 // 'RGSH'
#define ROG_SHM_VERSION 1u
#define kShmFrames 65536u                         // power of two, 1.37 s of stereo at 48 kHz
#define kShmDataOffset 4096u

typedef struct {
    uint32_t magic, version, rate, channels, frames;
    int32_t pid;                                  // driver host; readers treat a dead pid as no driver
    _Atomic uint64_t wpos;                        // frames written since the object was created
    _Atomic uint64_t lastHost;                    // mach_absolute_time of the last write
} RogShmHeader;

#define ROG_SHM_SIZE (kShmDataOffset + kShmFrames * 2u * sizeof(float))
static inline float *rog_shm_data(void *base) { return (float *)((char *)base + kShmDataOffset); }
