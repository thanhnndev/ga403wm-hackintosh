// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
import Foundation

/// One acknowledgement shown in About. Keep in step with NOTICE.md at the repository root.
struct Credit: Identifiable {
    let name: String
    let author: String
    let role: String
    let license: String
    let url: URL

    var id: String { name }

    static let upstream: [Credit] = [
        Credit(name: "asusctl and rog-control-center", author: "Luke Jones and the asus-linux contributors",
               role: "The feature set and organisation this app follows: profiles, power limits, charge limit, lighting. No code taken.",
               license: "MPL-2.0", url: URL(string: "https://asus-linux.org")!),
        Credit(name: "Linux asus-wmi and asus-armoury", author: "Corentin Chary, Luke Jones and contributors",
               role: "WMI method ids, profile values and the GA403WM power-limit ranges used by the AsusWmi driver. Interface facts only.",
               license: "GPL-2.0", url: URL(string: "https://github.com/torvalds/linux/tree/master/drivers/platform/x86")!),
        Credit(name: "Linux cs35l56 and cs_dsp", author: "Cirrus Logic and cirrus.com contributors",
               role: "Interface facts for the CS35L56 speaker amplifiers, and the amplifier firmware itself.",
               license: "GPL-2.0, Cirrus firmware licence", url: URL(string: "https://github.com/torvalds/linux/tree/master/sound/soc/codecs")!),
        Credit(name: "RNNoise", author: "Jean-Marc Valin and the Xiph.Org Foundation",
               role: "The noise suppression behind ROG Clear Mic.", license: "BSD-3-Clause",
               url: URL(string: "https://github.com/xiph/rnnoise")!),
        Credit(name: "AppleALC, Lilu, OpenCore", author: "Acidanthera",
               role: "Audio codec injection, the patching framework and the bootloader this hackintosh runs on.",
               license: "GPL-3.0 and BSD-3-Clause", url: URL(string: "https://github.com/acidanthera")!),
        Credit(name: "NullMoth OpenCore configuration and NVIDIA driver", author: "NullMoth",
               role: "The base EFI configuration and the GPU driver for this machine.", license: "PolyForm Noncommercial 1.0.0",
               url: URL(string: "https://github.com/nullmoth/1401")!),
        Credit(name: "mt76 and linux-firmware", author: "MediaTek Inc. and contributors",
               role: "Wi-Fi and Bluetooth hardware interface and firmware for the MT7925.", license: "BSD-3-Clause-Clear, MediaTek firmware licence",
               url: URL(string: "https://github.com/torvalds/linux/tree/master/drivers/net/wireless/mediatek/mt76")!),
        Credit(name: "itlwm", author: "OpenIntelWireless",
               role: "The idea of a Wi-Fi kext that presents itself as plain Ethernet.", license: "GPL-2.0",
               url: URL(string: "https://github.com/OpenIntelWireless/itlwm")!)
    ]
}
