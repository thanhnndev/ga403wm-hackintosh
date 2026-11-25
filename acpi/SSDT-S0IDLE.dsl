/*
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 * S0 (Modern Standby) system sleep for macOS on the GA403WM. The firmware has no _S3 (DSDT renames it XS3), so
 * AppleACPIPlatform reports "sleep states S4 S5" and refuses system sleep (kPMPCIUnsupported). AppleACPIPlatform
 * reads \_SB.LPS0 in initPlatformPowerManagement: an Integer 1 keeps the S0 sleep state, publishes
 * IOPMDeepIdleSupported and makes sleepPlatform use acpi_idle_kernel (S0 idle) instead of acpi_sleep_kernel.
 * StrixS0ix.kext supplies the CPU halt for that path (no pmDispatch on AMD: the stock halt is cli;hlt forever).
 * Built by tools/mk_ssdt_s0idle.py (no iasl here); this file is the source of truth for review.
 */
DefinitionBlock ("", "SSDT", 2, "GA403", "S0IDLE", 0x00000000)
{
    Scope (\_SB)
    {
        Method (LPS0, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (One)
            }
            Return (Zero)
        }
    }
}
