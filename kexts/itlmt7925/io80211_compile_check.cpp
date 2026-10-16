// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// Compile-only check: the generated IO80211 headers (macOS 25G241 Tahoe ABI, see docs/IO80211-ABI.md) must compile with the
// kext's real flags (-mkernel -fapple-kext, MacKernelSDK) and keep Apple's instance sizes. Not linked into any kext:
//   scripts/build.sh io80211check
#include "io80211/IO80211Controller.h"
#include "io80211/IO80211WorkQueue.h"
#include "io80211/IO80211CommandGate.h"
#include "io80211/IOSkywalkInterface.h"
#include "io80211/IOSkywalkNetworkInterface.h"
#include "io80211/IOSkywalkEthernetInterface.h"
#include "io80211/IO80211SkywalkInterface.h"
#include "io80211/IO80211InfraInterface.h"
#include "io80211/IO80211InfraProtocol.h"

static_assert(sizeof(IO80211Controller) == 0x128, "IO80211Controller");
static_assert(sizeof(IO80211WorkQueue) == 0x50, "IO80211WorkQueue");
static_assert(sizeof(IO80211CommandGate) == 0x18, "IO80211CommandGate");
static_assert(sizeof(IOSkywalkInterface) == 0xb0, "IOSkywalkInterface (SDK value)");
static_assert(sizeof(IOSkywalkNetworkInterface) == 0xe0, "IOSkywalkNetworkInterface");
static_assert(sizeof(IOSkywalkEthernetInterface) == 0x120, "IOSkywalkEthernetInterface");
static_assert(sizeof(IO80211SkywalkInterface) == 0x128, "IO80211SkywalkInterface");
static_assert(sizeof(IO80211InfraInterface) == 0x130, "IO80211InfraInterface");
static_assert(sizeof(IO80211InfraProtocol) == 0x130, "IO80211InfraProtocol");
