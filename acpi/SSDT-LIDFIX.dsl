/*
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 * SSDT-LIDFIX (GA403WM): LID0._LID reads the lid state from EC RAM whether or not EC0 is in D0.
 *
 * Firmware _LID: If (EC0.ECOK) { LIDS ? 0 : 1 } Else { 1 }. EC0._PS3 sets ECOK = 0 and _PS0 sets it back, so between the
 * wake and EC0._PS0 the lid reads "open" even when it is closed: at the 2026-11-05 14:13 RTC wake the root domain saw
 * clamshell closed 0 with the lid shut, i.e. every dark wake in a closed laptop could turn into a full wake.
 * LIDS is bit 5 of ERAM byte 0x52, and ERAM is SystemMemory 0xFEDD8300 (the EC RAM window, see SSDT-ECRAM): it is
 * readable at any time, ECOK only gates the EmbeddedControl region. So under Darwin _LID reads LIDS directly.
 * Other OSes run the firmware method (renamed XLID by the OpenCore patch "_LID to XLID", DSDT only).
 * Undo: disable this table and the "_LID to XLID" patch together.
 */
DefinitionBlock ("", "SSDT", 2, "GA403", "LIDFIX", 0x00000000)
{
    External (_SB_.LID0, DeviceObj)
    External (_SB_.LID0.XLID, MethodObj)
    External (_SB_.PCI0.SBRG.EC0_.LIDS, FieldUnitObj)
    External (_SB_.PCI0.SBRG.EC0_.MUT0, MutexObj)

    Scope (\_SB.LID0)
    {
        Method (_LID, 0, NotSerialized)  // _LID: Lid Status
        {
            If (_OSI ("Darwin"))
            {
                Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x0200)
                Local1 = \_SB.PCI0.SBRG.EC0.LIDS
                Release (\_SB.PCI0.SBRG.EC0.MUT0)
                If (Local1)
                {
                    Return (Zero)
                }

                Return (One)
            }

            Return (\_SB.LID0.XLID ())
        }
    }
}
