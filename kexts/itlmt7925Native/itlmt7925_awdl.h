// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// AWDL (AirDrop) front end, phase 2 of docs/ROADMAP-AWDL.md: the virtual interface (awdl0) and the ioctl that creates it.
//
// The Family creates its peer-to-peer interfaces through APPLE80211_IOC_VIRTUAL_IF_CREATE (0x5e): the ioctl carries an
// apple80211_virt_if_create_data (role 6 = AWDL/proximity, 7 = APSTA, 8-10 = NAN) and the driver answers with the BSD name it
// created. On Broadcom the core instantiates AppleBCMWLANProximityInterface (an IO80211AWDLProtocol subclass, firmware
// backed, 0xffffff800165dcbe createProxInterface); this driver instantiates its own IO80211VirtualInterface subclass and
// drives the Family's generic path (init -> attach -> register the ifnet -> setAwdlInterface), the path the Family's own
// IO80211Controller::attachVirtualInterface and IO80211VirtualInterface::createPeerManager expect.
//
// Everything is behind the boot-arg itlmt_awdl=1: with the boot-arg absent, ioctl 0x5e is not let through the gate (see
// itlmt7925Wifi::isCommandProhibited) and the handler refuses, so the verified Wi-Fi behaviour is unchanged.
#pragma once
#include <stdint.h>
#include <IOKit/IOReturn.h>

class itlmt7925WifiInterface;
struct apple80211_virt_if_create_data;

// Boot-arg itlmt_awdl (parsed once): true when set to a non-zero value.
bool itlmtAwdlEnabled();
