// SPDX-License-Identifier: BSD-3-Clause-Clear
// Copyright (c) 2026 thanhnndev and contributors
// MediaTek MT7925 Bluetooth firmware, embedded into the kext.
// Origin: linux-firmware mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin, redistributable under fw/LICENCE.mediatek.
// MT7922: linux-firmware mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin, same license.
// Built from the repo root, so the .incbin path is relative to it.
__asm__(".section __DATA,__const\n"
        ".globl _mtk_bt_fw\n"
        ".balign 16\n"
        "_mtk_bt_fw:\n"
        ".incbin \"fw/BT_RAM_CODE_MT7925_1_1_hdr.bin\"\n"
        ".globl _mtk_bt_fw_end\n"
        "_mtk_bt_fw_end:\n"
        ".byte 0\n"
        ".globl _mtk_bt_fw_7922\n"
        ".balign 16\n"
        "_mtk_bt_fw_7922:\n"
        ".incbin \"fw/BT_RAM_CODE_MT7922_1_1_hdr.bin\"\n"
        ".globl _mtk_bt_fw_7922_end\n"
        "_mtk_bt_fw_7922_end:\n"
        ".byte 0\n"
        ".text\n");
