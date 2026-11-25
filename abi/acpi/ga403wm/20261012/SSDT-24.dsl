/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260930 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-24.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000BA4 (2980)
 *     Revision         0x02
 *     Checksum         0xFF
 *     OEM ID           "AMD"
 *     OEM Table ID     "CPMUCSI"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20230331 (539165489)
 */
DefinitionBlock ("", "SSDT", 2, "AMD", "CPMUCSI", 0x00000001)
{
    External (_SB_.PCI0.SBRG.EC0_.ECOK, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MUT0, MutexObj)
    External (M000, MethodObj)    // 1 Arguments
    External (M037, DeviceObj)
    External (M046, IntObj)
    External (M047, IntObj)
    External (M049, MethodObj)    // 2 Arguments
    External (M050, DeviceObj)
    External (M051, DeviceObj)
    External (M052, DeviceObj)
    External (M053, DeviceObj)
    External (M054, DeviceObj)
    External (M055, DeviceObj)
    External (M056, DeviceObj)
    External (M057, DeviceObj)
    External (M058, DeviceObj)
    External (M059, DeviceObj)
    External (M062, DeviceObj)
    External (M068, DeviceObj)
    External (M069, DeviceObj)
    External (M070, DeviceObj)
    External (M071, DeviceObj)
    External (M072, DeviceObj)
    External (M074, DeviceObj)
    External (M075, DeviceObj)
    External (M076, DeviceObj)
    External (M077, DeviceObj)
    External (M078, DeviceObj)
    External (M079, DeviceObj)
    External (M080, DeviceObj)
    External (M081, DeviceObj)
    External (M082, FieldUnitObj)
    External (M083, FieldUnitObj)
    External (M084, FieldUnitObj)
    External (M085, FieldUnitObj)
    External (M086, FieldUnitObj)
    External (M087, FieldUnitObj)
    External (M088, FieldUnitObj)
    External (M089, FieldUnitObj)
    External (M090, FieldUnitObj)
    External (M091, FieldUnitObj)
    External (M092, FieldUnitObj)
    External (M093, FieldUnitObj)
    External (M094, FieldUnitObj)
    External (M095, FieldUnitObj)
    External (M096, FieldUnitObj)
    External (M097, FieldUnitObj)
    External (M098, FieldUnitObj)
    External (M099, FieldUnitObj)
    External (M100, FieldUnitObj)
    External (M101, FieldUnitObj)
    External (M102, FieldUnitObj)
    External (M103, FieldUnitObj)
    External (M104, FieldUnitObj)
    External (M105, FieldUnitObj)
    External (M106, FieldUnitObj)
    External (M107, FieldUnitObj)
    External (M108, FieldUnitObj)
    External (M109, FieldUnitObj)
    External (M110, FieldUnitObj)
    External (M115, BuffObj)
    External (M116, BuffFieldObj)
    External (M117, BuffFieldObj)
    External (M118, BuffFieldObj)
    External (M119, BuffFieldObj)
    External (M120, BuffFieldObj)
    External (M122, FieldUnitObj)
    External (M127, DeviceObj)
    External (M128, FieldUnitObj)
    External (M131, FieldUnitObj)
    External (M132, FieldUnitObj)
    External (M133, FieldUnitObj)
    External (M134, FieldUnitObj)
    External (M135, FieldUnitObj)
    External (M136, FieldUnitObj)
    External (M220, FieldUnitObj)
    External (M221, FieldUnitObj)
    External (M226, FieldUnitObj)
    External (M227, DeviceObj)
    External (M229, FieldUnitObj)
    External (M231, FieldUnitObj)
    External (M233, FieldUnitObj)
    External (M235, FieldUnitObj)
    External (M23A, FieldUnitObj)
    External (M251, FieldUnitObj)
    External (M280, FieldUnitObj)
    External (M290, FieldUnitObj)
    External (M29A, FieldUnitObj)
    External (M310, FieldUnitObj)
    External (M31C, FieldUnitObj)
    External (M320, FieldUnitObj)
    External (M321, FieldUnitObj)
    External (M322, FieldUnitObj)
    External (M323, FieldUnitObj)
    External (M324, FieldUnitObj)
    External (M325, FieldUnitObj)
    External (M326, FieldUnitObj)
    External (M327, FieldUnitObj)
    External (M328, FieldUnitObj)
    External (M329, DeviceObj)
    External (M32A, DeviceObj)
    External (M32B, DeviceObj)
    External (M32C, DeviceObj)
    External (M330, DeviceObj)
    External (M331, FieldUnitObj)
    External (M378, FieldUnitObj)
    External (M379, FieldUnitObj)
    External (M380, FieldUnitObj)
    External (M381, FieldUnitObj)
    External (M382, FieldUnitObj)
    External (M383, FieldUnitObj)
    External (M384, FieldUnitObj)
    External (M385, FieldUnitObj)
    External (M386, FieldUnitObj)
    External (M387, FieldUnitObj)
    External (M388, FieldUnitObj)
    External (M389, FieldUnitObj)
    External (M390, FieldUnitObj)
    External (M391, FieldUnitObj)
    External (M392, FieldUnitObj)
    External (M404, BuffObj)
    External (M408, MutexObj)
    External (M414, FieldUnitObj)
    External (M444, FieldUnitObj)
    External (M449, FieldUnitObj)
    External (M453, FieldUnitObj)
    External (M454, FieldUnitObj)
    External (M455, FieldUnitObj)
    External (M456, FieldUnitObj)
    External (M457, FieldUnitObj)
    External (M4C0, FieldUnitObj)
    External (M4F0, FieldUnitObj)
    External (M610, FieldUnitObj)
    External (M620, FieldUnitObj)
    External (M631, FieldUnitObj)
    External (M652, FieldUnitObj)

    Scope (\_SB)
    {
        Device (UBTC)
        {
            Name (_HID, EisaId ("USBC000"))  // _HID: Hardware ID
            Name (_CID, EisaId ("PNP0CA0"))  // _CID: Compatible ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_DDN, "USB Type C")  // _DDN: DOS Device Name
            Name (_ADR, Zero)  // _ADR: Address
            Name (M311, Buffer (0x14)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0010 */  0x00, 0x00, 0x00, 0x00                           // ....
            })
            Name (CRS, ResourceTemplate ()
            {
                Memory32Fixed (ReadWrite,
                    0x00000000,         // Address Base
                    0x00001000,         // Address Length
                    _Y00)
            })
            Device (CR01)
            {
                Name (_ADR, Zero)  // _ADR: Address
                Name (PLD1, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x09, 0x00, 0x03, 0x00,  // ........
                        /* 0008 */  0x91, 0x09, 0x80, 0x00, 0x01, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD1) /* \_SB_.UBTC.CR01.PLD1 */
                }
            }

            Device (CR02)
            {
                Name (_ADR, One)  // _ADR: Address
                Name (PLD1, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x09, 0x00, 0x03, 0x00,  // ........
                        /* 0008 */  0x91, 0x09, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD1) /* \_SB_.UBTC.CR02.PLD1 */
                }
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                CreateDWordField (CRS, \_SB.UBTC._Y00._BAS, M317)  // _BAS: Base Address
                Local0 = M310 /* External reference */
                M317 = (Local0 + 0x1D)
                Return (CRS) /* \_SB_.UBTC.CRS_ */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((M049 (M128, 0x78) == One))
                {
                    VER0 = TER1 /* \_SB_.UBTC.TER1 */
                    VER1 = TER2 /* \_SB_.UBTC.TER2 */
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            OperationRegion (PM08, SystemMemory, M320, 0x30)
            Field (PM08, ByteAcc, Lock, Preserve)
            {
                VER0,   8, 
                VER1,   8, 
                RSV0,   8, 
                RSV1,   8, 
                CCI0,   8, 
                CCI1,   8, 
                CCI2,   8, 
                CCI3,   8, 
                CTL0,   8, 
                CTL1,   8, 
                CTL2,   8, 
                CTL3,   8, 
                CTL4,   8, 
                CTL5,   8, 
                CTL6,   8, 
                CTL7,   8, 
                MGI0,   8, 
                MGI1,   8, 
                MGI2,   8, 
                MGI3,   8, 
                MGI4,   8, 
                MGI5,   8, 
                MGI6,   8, 
                MGI7,   8, 
                MGI8,   8, 
                MGI9,   8, 
                MGIA,   8, 
                MGIB,   8, 
                MGIC,   8, 
                MGID,   8, 
                MGIE,   8, 
                MGIF,   8, 
                MGO0,   8, 
                MGO1,   8, 
                MGO2,   8, 
                MGO3,   8, 
                MGO4,   8, 
                MGO5,   8, 
                MGO6,   8, 
                MGO7,   8, 
                MGO8,   8, 
                MGO9,   8, 
                MGOA,   8, 
                MGOB,   8, 
                MGOC,   8, 
                MGOD,   8, 
                MGOE,   8, 
                MGOF,   8
            }

            Method (M318, 0, Serialized)
            {
                If (\_SB.PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1388)
                    VER0 = TER1 /* \_SB_.UBTC.TER1 */
                    VER1 = TER2 /* \_SB_.UBTC.TER2 */
                    MGI0 = TGI0 /* \_SB_.UBTC.TGI0 */
                    MGI1 = TGI1 /* \_SB_.UBTC.TGI1 */
                    MGI2 = TGI2 /* \_SB_.UBTC.TGI2 */
                    MGI3 = TGI3 /* \_SB_.UBTC.TGI3 */
                    MGI4 = TGI4 /* \_SB_.UBTC.TGI4 */
                    MGI5 = TGI5 /* \_SB_.UBTC.TGI5 */
                    MGI6 = TGI6 /* \_SB_.UBTC.TGI6 */
                    MGI7 = TGI7 /* \_SB_.UBTC.TGI7 */
                    MGI8 = TGI8 /* \_SB_.UBTC.TGI8 */
                    MGI9 = TGI9 /* \_SB_.UBTC.TGI9 */
                    MGIA = TGIA /* \_SB_.UBTC.TGIA */
                    MGIB = TGIB /* \_SB_.UBTC.TGIB */
                    MGIC = TGIC /* \_SB_.UBTC.TGIC */
                    MGID = TGID /* \_SB_.UBTC.TGID */
                    MGIE = TGIE /* \_SB_.UBTC.TGIE */
                    MGIF = TGIF /* \_SB_.UBTC.TGIF */
                    CCI0 = TCI0 /* \_SB_.UBTC.TCI0 */
                    CCI1 = TCI1 /* \_SB_.UBTC.TCI1 */
                    CCI2 = TCI2 /* \_SB_.UBTC.TCI2 */
                    Local0 = TCI3 /* \_SB_.UBTC.TCI3 */
                    CCI3 = Local0
                    If ((Local0 != Zero))
                    {
                        TCI3 = Zero
                    }

                    TCI0 = Zero
                    Release (\_SB.PCI0.SBRG.EC0.MUT0)
                }
            }

            OperationRegion (EURM, SystemMemory, 0xFEDD8500, 0x40)
            Field (EURM, ByteAcc, NoLock, Preserve)
            {
                TTL0,   8, 
                TTL1,   8, 
                TTL2,   8, 
                TTL3,   8, 
                TTL4,   8, 
                TTL5,   8, 
                TTL6,   8, 
                TTL7,   8, 
                TER1,   8, 
                TER2,   8, 
                TSV1,   8, 
                TSV2,   8, 
                TCI0,   8, 
                TCI1,   8, 
                TCI2,   8, 
                TCI3,   8, 
                TGI0,   8, 
                TGI1,   8, 
                TGI2,   8, 
                TGI3,   8, 
                TGI4,   8, 
                TGI5,   8, 
                TGI6,   8, 
                TGI7,   8, 
                TGI8,   8, 
                TGI9,   8, 
                TGIA,   8, 
                TGIB,   8, 
                TGIC,   8, 
                TGID,   8, 
                TGIE,   8, 
                TGIF,   8, 
                TGO0,   8, 
                TGO1,   8, 
                TGO2,   8, 
                TGO3,   8, 
                TGO4,   8, 
                TGO5,   8, 
                TGO6,   8, 
                TGO7,   8, 
                TGO8,   8, 
                TGO9,   8, 
                TGOA,   8, 
                TGOB,   8, 
                TGOC,   8, 
                TGOD,   8, 
                TGOE,   8, 
                TGOF,   8
            }

            Method (QUCM, 0, Serialized)
            {
                If (\_SB.PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1388)
                    MGI0 = TGI0 /* \_SB_.UBTC.TGI0 */
                    MGI1 = TGI1 /* \_SB_.UBTC.TGI1 */
                    MGI2 = TGI2 /* \_SB_.UBTC.TGI2 */
                    MGI3 = TGI3 /* \_SB_.UBTC.TGI3 */
                    MGI4 = TGI4 /* \_SB_.UBTC.TGI4 */
                    MGI5 = TGI5 /* \_SB_.UBTC.TGI5 */
                    MGI6 = TGI6 /* \_SB_.UBTC.TGI6 */
                    MGI7 = TGI7 /* \_SB_.UBTC.TGI7 */
                    MGI8 = TGI8 /* \_SB_.UBTC.TGI8 */
                    MGI9 = TGI9 /* \_SB_.UBTC.TGI9 */
                    MGIA = TGIA /* \_SB_.UBTC.TGIA */
                    MGIB = TGIB /* \_SB_.UBTC.TGIB */
                    MGIC = TGIC /* \_SB_.UBTC.TGIC */
                    MGID = TGID /* \_SB_.UBTC.TGID */
                    MGIE = TGIE /* \_SB_.UBTC.TGIE */
                    MGIF = TGIF /* \_SB_.UBTC.TGIF */
                    CCI0 = TCI0 /* \_SB_.UBTC.TCI0 */
                    CCI1 = TCI1 /* \_SB_.UBTC.TCI1 */
                    CCI2 = TCI2 /* \_SB_.UBTC.TCI2 */
                    CCI3 = TCI3 /* \_SB_.UBTC.TCI3 */
                    TCI0 = Zero
                    TCI3 = Zero
                    Release (\_SB.PCI0.SBRG.EC0.MUT0)
                }
            }

            Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
            {
                If ((Arg0 == ToUUID ("6f8398c2-7ca4-11e4-ad36-631042b5008f") /* Unknown UUID */))
                {
                    If ((ToInteger (Arg2) == Zero))
                    {
                        Return (Buffer (One)
                        {
                             0x0F                                             // .
                        })
                    }
                    ElseIf ((ToInteger (Arg2) == One))
                    {
                        M000 (0x0DA8)
                        If (\_SB.PCI0.SBRG.EC0.ECOK)
                        {
                            Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1388)
                            TGO0 = MGO0 /* \_SB_.UBTC.MGO0 */
                            TGO1 = MGO1 /* \_SB_.UBTC.MGO1 */
                            TGO2 = MGO2 /* \_SB_.UBTC.MGO2 */
                            TGO3 = MGO3 /* \_SB_.UBTC.MGO3 */
                            TGO4 = MGO4 /* \_SB_.UBTC.MGO4 */
                            TGO5 = MGO5 /* \_SB_.UBTC.MGO5 */
                            TGO6 = MGO6 /* \_SB_.UBTC.MGO6 */
                            TGO7 = MGO7 /* \_SB_.UBTC.MGO7 */
                            TGO8 = MGO8 /* \_SB_.UBTC.MGO8 */
                            TGO9 = MGO9 /* \_SB_.UBTC.MGO9 */
                            TGOA = MGOA /* \_SB_.UBTC.MGOA */
                            TGOB = MGOB /* \_SB_.UBTC.MGOB */
                            TGOC = MGOC /* \_SB_.UBTC.MGOC */
                            TGOD = MGOD /* \_SB_.UBTC.MGOD */
                            TGOE = MGOE /* \_SB_.UBTC.MGOE */
                            TGOF = MGOF /* \_SB_.UBTC.MGOF */
                            TTL7 = CTL7 /* \_SB_.UBTC.CTL7 */
                            TTL6 = CTL6 /* \_SB_.UBTC.CTL6 */
                            TTL5 = CTL5 /* \_SB_.UBTC.CTL5 */
                            TTL4 = CTL4 /* \_SB_.UBTC.CTL4 */
                            TTL3 = CTL3 /* \_SB_.UBTC.CTL3 */
                            TTL2 = CTL2 /* \_SB_.UBTC.CTL2 */
                            TTL1 = CTL1 /* \_SB_.UBTC.CTL1 */
                            TTL0 = CTL0 /* \_SB_.UBTC.CTL0 */
                            Release (\_SB.PCI0.SBRG.EC0.MUT0)
                        }

                        M000 (0x0DA9)
                    }
                    ElseIf ((ToInteger (Arg2) == 0x02))
                    {
                        M000 (0x0DAA)
                        M318 ()
                        M000 (0x0DAB)
                    }
                }

                Return (Zero)
            }
        }
    }
}

