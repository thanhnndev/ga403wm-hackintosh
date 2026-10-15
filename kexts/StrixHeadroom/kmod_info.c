// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
#include <mach/mach_types.h>
extern kern_return_t StrixHeadroom_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t StrixHeadroom_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(com.itlmt7925.strixheadroom, "0.1.0", StrixHeadroom_kern_start, StrixHeadroom_kern_stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
