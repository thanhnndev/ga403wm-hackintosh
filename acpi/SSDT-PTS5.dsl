/*
 * SPDX-License-Identifier: BSD-3-Clause-Clear
 * Shut Down powers the GA403WM back on ~28 s later under macOS: the FCH reset register then reads bit 21 (ACPI power
 * state transition), so S5 is entered and a wake event ends it. The USB controllers (XHC0/1/3/4, GPE 0x19/0x1A) and the
 * USB4 router (NHI0/1, GPP0/GPP1.SWUS) are the wake sources left armed: macOS leaves PME_En set at power-off.
 * This table wraps _PTS (the DSDT's _PTS is renamed to ZPTS by an OpenCore ACPI patch, DSDT only): on _PTS(5) under
 * Darwin it clears PME_En and PME_Status in the PM capability of those functions, then runs the firmware's _PTS.
 * Other OSes and other sleep states only run ZPTS. Config space goes through the firmware's own CPM helpers in
 * SSDT CPMCMN (M645 = ECAM address of bus/dev/fn, M049 = 8-bit read, M04B/M04E = 32-bit read/write).
 * Undo: disable this table and the "_PTS to ZPTS" patch in config.plist (both together).
 */
DefinitionBlock ("", "SSDT", 2, "GA403", "PTS5", 0x00000000)
{
    External (ZPTS, MethodObj)
    External (M645, MethodObj)
    External (M049, MethodObj)
    External (M04B, MethodObj)
    External (M04E, MethodObj)

    // Clear PME_En (PMCSR bit 8) and PME_Status (bit 15, write 1) on bus Arg0, device Arg1, function Arg2.
    // Returns One when the PM capability was found and written.
    Method (ZPMF, 3, Serialized)
    {
        Local0 = M645 (Arg0, Arg1, Arg2)
        If ((Local0 == Zero))
        {
            Return (Zero)
        }

        If ((M04B (Local0, Zero) == 0xFFFFFFFF))
        {
            Return (Zero)
        }

        Local1 = M049 (Local0, 0x34)
        Local2 = Zero
        While (((Local1 >= 0x40) && (Local2 < 0x30)))
        {
            Local1 &= 0xFC
            If ((M049 (Local0, Local1) == One))
            {
                Local3 = (Local1 + 0x04)
                Local4 = M04B (Local0, Local3)
                M04E (Local0, Local3, ((Local4 & 0xFFFFFEFF) | 0x8000))
                Return (One)
            }

            Local1 = M049 (Local0, (Local1 + One))
            Local2++
        }

        Return (Zero)
    }

    // Secondary bus number of the root port at 00:Arg0.Arg1 (0 when absent)
    Method (ZBUS, 2, Serialized)
    {
        Local0 = M645 (Zero, Arg0, Arg1)
        If ((Local0 == Zero))
        {
            Return (Zero)
        }

        Local1 = M049 (Local0, 0x19)
        If ((Local1 == 0xFF))
        {
            Return (Zero)
        }

        Return (Local1)
    }

    Method (_PTS, 1, NotSerialized)  // _PTS: Prepare To Sleep
    {
        If (((Arg0 == 0x05) && _OSI ("Darwin")))
        {
            Local0 = ZBUS (0x08, 0x03)      // GPPC: XHC0 0, XHC3 3, XHC4 4, NHI0 5, NHI1 6
            If (Local0)
            {
                ZPMF (Local0, Zero, Zero)
                ZPMF (Local0, Zero, 0x03)
                ZPMF (Local0, Zero, 0x04)
                ZPMF (Local0, Zero, 0x05)
                ZPMF (Local0, Zero, 0x06)
            }

            Local0 = ZBUS (0x08, One)       // GPPA: XHC1 4
            If (Local0)
            {
                ZPMF (Local0, Zero, 0x04)
            }

            Local0 = ZBUS (One, One)        // GPP0: USB4 SWUS
            If (Local0)
            {
                ZPMF (Local0, Zero, Zero)
            }

            Local0 = ZBUS (One, 0x02)       // GPP1: USB4 SWUS
            If (Local0)
            {
                ZPMF (Local0, Zero, Zero)
            }
        }

        ZPTS (Arg0)
    }
}
