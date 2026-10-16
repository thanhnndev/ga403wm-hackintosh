// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);
extern kern_return_t BtLeDlFix_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t BtLeDlFix_kern_stop(kmod_info_t *ki, void *data);
__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(com.itlmt7925.btledlfix, "1.0.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = BtLeDlFix_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = BtLeDlFix_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
