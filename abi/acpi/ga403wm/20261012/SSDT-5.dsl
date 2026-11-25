/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260930 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of SSDT-5.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000465C (18012)
 *     Revision         0x01
 *     Checksum         0x9E
 *     OEM ID           "OptRf2"
 *     OEM Table ID     "Opt2Tabl"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20230331 (539165489)
 */
DefinitionBlock ("", "SSDT", 1, "OptRf2", "Opt2Tabl", 0x00001000)
{
    External (_SB_.ALIB, MethodObj)    // 2 Arguments
    External (_SB_.PCI0.GPP9, DeviceObj)
    External (_SB_.PCI0.GPP9._ADR, IntObj)
    External (_SB_.PCI0.SBRG.EC0_.CTMP, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.DDGU, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.DMUS, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.ECOK, IntObj)
    External (_SB_.PCI0.SBRG.EC0_.EDAD, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.FTBL, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.G40C, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.GBLD, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MOLR, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MUT0, MutexObj)
    External (_SB_.PCI0.SBRG.EC0_.MUT1, MutexObj)
    External (_SB_.PCI0.SBRG.EC0_.NDF9, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.NVPS, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.PMXL, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.PROL, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.PWMD, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.S4UM, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.SBLD, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.SDNT, FieldUnitObj)
    External (_SB_.PCI0.SBRG.EC0_.VGAT, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.VIUF, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.VRTT, UnknownObj)
    External (_SB_.PLTF.C000, DeviceObj)
    External (_SB_.PLTF.C001, DeviceObj)
    External (_SB_.PLTF.C002, DeviceObj)
    External (_SB_.PLTF.C003, DeviceObj)
    External (_SB_.PLTF.C004, DeviceObj)
    External (_SB_.PLTF.C005, DeviceObj)
    External (_SB_.PLTF.C006, DeviceObj)
    External (_SB_.PLTF.C007, DeviceObj)
    External (_SB_.PLTF.C008, DeviceObj)
    External (_SB_.PLTF.C009, DeviceObj)
    External (_SB_.PLTF.C00A, DeviceObj)
    External (_SB_.PLTF.C00B, DeviceObj)
    External (_SB_.PLTF.C00C, DeviceObj)
    External (_SB_.PLTF.C00D, DeviceObj)
    External (_SB_.PLTF.C00E, DeviceObj)
    External (_SB_.PLTF.C00F, DeviceObj)
    External (_SB_.PLTF.C010, DeviceObj)
    External (_SB_.PLTF.C011, DeviceObj)
    External (_SB_.PLTF.C012, DeviceObj)
    External (_SB_.PLTF.C013, DeviceObj)
    External (_SB_.PLTF.C014, DeviceObj)
    External (_SB_.PLTF.C015, DeviceObj)
    External (_SB_.PLTF.C016, DeviceObj)
    External (_SB_.PLTF.C017, DeviceObj)
    External (_SB_.PLTF.C018, DeviceObj)
    External (_SB_.PLTF.C019, DeviceObj)
    External (_SB_.PLTF.C01A, DeviceObj)
    External (_SB_.PLTF.C01B, DeviceObj)
    External (_SB_.PLTF.C01C, DeviceObj)
    External (_SB_.PLTF.C01D, DeviceObj)
    External (_SB_.PLTF.C01E, DeviceObj)
    External (_SB_.PLTF.C01F, DeviceObj)
    External (CUMA, IntObj)
    External (DPMF, UnknownObj)
    External (EID1, UnknownObj)
    External (EID2, UnknownObj)
    External (GPCE, IntObj)
    External (GTPM, IntObj)
    External (M009, MethodObj)    // 1 Arguments
    External (M010, MethodObj)    // 2 Arguments
    External (M017, MethodObj)    // 6 Arguments
    External (M018, MethodObj)    // 7 Arguments
    External (M019, MethodObj)    // 4 Arguments
    External (M020, MethodObj)    // 5 Arguments
    External (M023, MethodObj)    // 3 Arguments
    External (M027, MethodObj)    // 3 Arguments
    External (M028, MethodObj)    // 4 Arguments
    External (M037, DeviceObj)
    External (M046, IntObj)
    External (M047, IntObj)
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
    External (M249, MethodObj)    // 4 Arguments
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
    External (M401, MethodObj)    // 3 Arguments
    External (M402, MethodObj)    // 3 Arguments
    External (M403, MethodObj)    // 4 Arguments
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
    External (M460, MethodObj)    // 7 Arguments
    External (M471, MethodObj)    // 3 Arguments
    External (M4C0, FieldUnitObj)
    External (M4F0, FieldUnitObj)
    External (M610, FieldUnitObj)
    External (M620, FieldUnitObj)
    External (M631, FieldUnitObj)
    External (M652, FieldUnitObj)
    External (NBFM, IntObj)
    External (PEBS, BuffFieldObj)
    External (PIDM, UnknownObj)
    External (PWEN, UnknownObj)
    External (PWOK, UnknownObj)
    External (REST, UnknownObj)
    External (SDMF, UnknownObj)
    External (UMFG, IntObj)
    External (WOSR, IntObj)

    Name (TOPT, 0x02)
    OperationRegion (TPNV, SystemMemory, 0x6EE12000, 0x004D)
    Field (TPNV, AnyAcc, Lock, Preserve)
    {
        Offset (0x00), 
        MXD1,   32, 
        Offset (0x04), 
        MXD2,   32, 
        Offset (0x08), 
        MXD3,   32, 
        Offset (0x0C), 
        MXD4,   32, 
        Offset (0x10), 
        MXD5,   32, 
        Offset (0x14), 
        MXD6,   32, 
        Offset (0x18), 
        MXD7,   32, 
        Offset (0x1C), 
        MXD8,   32, 
        Offset (0x20), 
        EBAS,   32, 
        Offset (0x24), 
        DGVS,   32, 
        Offset (0x28), 
        DGVB,   32, 
        Offset (0x2C), 
        HYSS,   32, 
        Offset (0x30), 
        NVAF,   8, 
        Offset (0x31), 
        DEID,   16, 
        Offset (0x33), 
        DPMF,   8, 
        Offset (0x34), 
        SDMF,   8, 
        Offset (0x35), 
        SGFL,   8, 
        Offset (0x36), 
        NVGA,   32, 
        Offset (0x3A), 
        NVHA,   32, 
        Offset (0x3E), 
        TCNT,   8, 
        Offset (0x3F), 
        CMPL,   8, 
        Offset (0x40), 
        CNPL,   8, 
        Offset (0x41), 
        CNLL,   8, 
        Offset (0x42), 
        CLPL,   8, 
        Offset (0x43), 
        KFAX,   8, 
        Offset (0x44), 
        PTOF,   8, 
        Offset (0x45), 
        TM00,   8, 
        Offset (0x46), 
        TM01,   8, 
        Offset (0x47), 
        TM02,   8, 
        Offset (0x48), 
        TM03,   8, 
        Offset (0x49), 
        TM04,   32
    }

    Method (TPV0, 0, Serialized)
    {
        M402 (Zero, 0x03, One)
    }

    Method (TPV1, 0, Serialized)
    {
        M403 (Zero, 0x03, One, One)
    }

    Method (TPV2, 0, Serialized)
    {
        M403 (Zero, 0x03, One, Zero)
    }

    Scope (\_SB.PCI0.GPP9)
    {
        Method (BPGN, 0, Serialized)
        {
        }

        Method (APGN, 0, Serialized)
        {
        }

        Method (BPGF, 0, Serialized)
        {
        }

        Method (APGF, 0, Serialized)
        {
        }
    }

    Name (OFT1, Zero)
    Scope (\_SB.PCI0.GPP9)
    {
        Device (PEGP)
        {
            Name (_ADR, Zero)  // _ADR: Address
            Method (_STA, 0, Serialized)  // _STA: Status
            {
                Local2 = M017 (Zero, 0x03, One, 0x68, 0x04, One)
                If (((Local2 == Zero) && (\CUMA == Zero)))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_EJ0, 1, NotSerialized)  // _EJx: Eject Device, x=0-9
            {
                If ((GPCE == One))
                {
                    \_SB.PCI0.GPP9.PG00._OFF ()
                    UMFG = One
                    WOSR = Zero
                }
            }

            Method (_RMV, 0, NotSerialized)  // _RMV: Removal Status
            {
                Return (Zero)
            }

            OperationRegion (QMIP, SystemIO, 0xB2, One)
            Field (QMIP, ByteAcc, NoLock, Preserve)
            {
                QSMI,   8
            }

            Name (MMID, Package (0x02)
            {
                Package (0x03)
                {
                    Zero, 
                    "PI3WVR13612", 
                    0x00030002
                }, 

                Package (0x03)
                {
                    One, 
                    "NON-MUX or Error", 
                    Zero
                }
            })
            Method (_DOD, 0, NotSerialized)  // _DOD: Display Output Devices
            {
                Return (Package (0x01)
                {
                    0x8000A450
                })
            }

            Device (LCD0)
            {
                Method (_ADR, 0, Serialized)  // _ADR: Address
                {
                    Return (0x8000A450)
                }

                Method (_DDC, 1, Serialized)  // _DDC: Display Data Current
                {
                    If (((Arg0 == One) || (Arg0 == 0x02)))
                    {
                        OperationRegion (EDMB, SystemMemory, \_SB.PCI0.SBRG.EC0.EDAD, 0x0100)
                        Field (EDMB, AnyAcc, NoLock, Preserve)
                        {
                            EDMD,   2048
                        }

                        Name (BUFF, Buffer (0x0100)
                        {
                             0x00                                             // .
                        })
                        BUFF = EDMD /* \_SB_.PCI0.GPP9.PEGP.LCD0._DDC.EDMD */
                        Return (BUFF) /* \_SB_.PCI0.GPP9.PEGP.LCD0._DDC.BUFF */
                    }

                    Return (Zero)
                }

                Method (MXDS, 1, NotSerialized)
                {
                    Local0 = Arg0
                    Local1 = (Local0 & 0x0F)
                    Local2 = (Local0 & 0x10)
                    If ((Local1 == Zero))
                    {
                        If ((\_SB.PCI0.SBRG.EC0.MOLR == Zero))
                        {
                            Return (One)
                        }
                        Else
                        {
                            Return (0x02)
                        }
                    }
                    ElseIf ((Local1 == One))
                    {
                        If ((Local2 == 0x10))
                        {
                            \_SB.PCI0.SBRG.EC0.DMUS = One
                            Sleep (0x14)
                        }
                        Else
                        {
                            \_SB.PCI0.SBRG.EC0.DMUS = Zero
                            Sleep (0x14)
                        }

                        Return (One)
                    }
                    Else
                    {
                        Return (Zero)
                    }
                }

                Method (MXDM, 1, NotSerialized)
                {
                    Local0 = Arg0
                    Local1 = (Local0 & 0x07)
                    If ((Local1 == Zero))
                    {
                        Local2 = DPMF /* \DPMF */
                        Return (Local2)
                    }
                    ElseIf ((Local1 < 0x05))
                    {
                        SDMF = Local1
                        QSMI = 0xB8
                    }
                    Else
                    {
                        Return (Zero)
                    }

                    Return (One)
                }

                Method (MXID, 1, NotSerialized)
                {
                    If ((Arg0 == Zero))
                    {
                        Local0 = DerefOf (DerefOf (MMID [Zero]) [0x02])
                        Return (Local0)
                    }
                }

                Method (LRST, 1, NotSerialized)
                {
                    Local0 = Arg0
                    Local1 = (Local0 & 0x07)
                    If ((Local1 == Zero))
                    {
                        If ((\_SB.PCI0.SBRG.EC0.PROL == Zero))
                        {
                            Return (One)
                        }
                        Else
                        {
                            Return (0x02)
                        }
                    }
                    ElseIf ((Local1 == One))
                    {
                        \_SB.PCI0.SBRG.EC0.PROL = Zero
                    }
                    ElseIf ((Local1 == 0x02))
                    {
                        \_SB.PCI0.SBRG.EC0.PROL = One
                    }
                    Else
                    {
                        Return (Zero)
                    }
                }
            }
        }

        Device (NHDA)
        {
            Name (_ADR, One)  // _ADR: Address
            Method (_RMV, 0, NotSerialized)  // _RMV: Removal Status
            {
                Return (Zero)
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((M097 != Zero))
                {
                    Return (Zero)
                }
                Else
                {
                    Return (0x0F)
                }
            }
        }

        Method (_DSD, 0, Serialized)  // _DSD: Device-Specific Data
        {
            Return (Package (0x06)
            {
                ToUUID ("6b4ad420-8fd3-4364-acf8-eb94876fd9eb") /* Unknown UUID */, 
                Package (0x00){}, 
                ToUUID ("6211e2c0-58a3-4af3-90e1-927a4e0c55a4") /* Unknown UUID */, 
                Package (0x01)
                {
                    Package (0x02)
                    {
                        "HotPlugSupportInD3", 
                        One
                    }
                }, 

                ToUUID ("fdf06fad-f744-4451-bb64-ecd792215b10") /* Unknown UUID */, 
                Package (0x01)
                {
                    Package (0x02)
                    {
                        "FundamentalDeviceResetTriggeredOnD3ToD0", 
                        One
                    }
                }
            })
        }

        Method (PON, 0, NotSerialized)
        {
            M010 (REST, Zero)
            Sleep (One)
            M010 (PWEN, One)
            Sleep (0x78)
            M010 (REST, One)
            Sleep (0xC8)
        }

        Method (L23D, 1, Serialized)
        {
            Local1 = TM02 /* \TM02 */
            If ((Local1 == Zero))
            {
                Local1 = 0x0A
            }

            Sleep (Local1)
            \_SB.ALIB (0x13, 0x19)
            Local0 = Zero
            While (((M017 (Zero, 0x03, One, 0x6A, Zero, 0x04) < 0x04) || 
                (M017 (Zero, 0x03, One, 0x6A, 0x0D, One) != One)))
            {
                If ((Local0 > 0x13BB))
                {
                    Break
                }

                Stall (0x63)
                Local0++
            }

            Name (RPNM, 0xEE)
            Name (LCRG, 0xEEEEEEEE)
            If ((RPNM == 0xEE))
            {
                RPNM = M401 (Zero, 0x03, One)
            }

            If (((RPNM != 0xFF) && (LCRG == 0xEEEEEEEE)))
            {
                LCRG = (M471 (Zero, RPNM, 0x04) + 0x0294)
            }

            If ((LCRG != 0xEEEEEEEE))
            {
                Local1 = M249 (Zero, Zero, Zero, LCRG)
                M460 ("  OEM-ASL-\\_SB.PCI0.GP12.PCIE_LC_STATE0 = 0x%X\n", Local1, Zero, Zero, Zero, Zero, Zero)
            }

            Local0 = Zero
            Local1 &= 0x3F
            While ((Local1 != 0x10))
            {
                If ((Local0 > 0x13BB))
                {
                    Break
                }

                Stall (0x63)
                Local1 = M249 (Zero, Zero, Zero, LCRG)
                Local1 &= 0x3F
                Local0++
            }

            TPV2 ()
            Local1 = TM03 /* \TM03 */
            If ((Local1 == Zero))
            {
                Local1 = 0x64
            }

            Sleep (Local1)
        }

        Method (POFF, 0, NotSerialized)
        {
            M010 (REST, Zero)
            Sleep (One)
            M010 (PWEN, Zero)
            Sleep (0x64)
        }

        Method (DL23, 1, Serialized)
        {
            If ((Arg0 == One))
            {
                If (((\UMFG == One) || (GPCE == One)))
                {
                    LNKD = One
                }
                Else
                {
                    TPV0 ()
                    OFT1 = Zero
                    OFT1 = M019 (Zero, 0x03, One, 0x70)
                    M020 (Zero, 0x03, One, 0x70, (OFT1 & 0xFFFF0000))
                    \_SB.ALIB (0x12, 0x19)
                    Sleep (0x1E)
                }
            }

            Local1 = TM04 /* \TM04 */
            If ((Local1 == Zero))
            {
                Local1 = 0x0A
            }

            Sleep (Local1)
        }

        OperationRegion (RPCX, SystemMemory, ((\PEBS + (((\_SB.PCI0.GPP9._ADR & 0x00FF0000) >> 0x10) << 
            0x0F)) + ((\_SB.PCI0.GPP9._ADR & 0xFF) << 0x0C)), 0x1000)
        Field (RPCX, DWordAcc, NoLock, Preserve)
        {
            RVID,   32, 
            CMDR,   8, 
            Offset (0x19), 
            PRBN,   8, 
            Offset (0x54), 
            D0ST,   2, 
            Offset (0x62), 
            CEDR,   1, 
            Offset (0x68), 
            ASPM,   2, 
                ,   2, 
            LNKD,   1, 
            Offset (0x80), 
            Offset (0x81), 
                ,   2, 
            LREN,   1
        }

        Method (GSTA, 0, NotSerialized)
        {
            If ((M009 (REST) == Zero))
            {
                Return (Zero)
            }
            Else
            {
                Return (One)
            }
        }

        Name (TDGC, Zero)
        Name (DGCX, Zero)
        Name (TGPC, Buffer (0x04)
        {
             0x00                                             // .
        })
        PowerResource (PG00, 0x00, 0x0000)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((RVID == Ones))
                {
                    Return (Zero)
                }

                Return (GSTA ())
            }

            Method (_ON, 0, Serialized)  // _ON_: Power On
            {
                M023 (Zero, 0x03, One)
                OFT1 = Zero
                OFT1 = M019 (Zero, 0x03, One, 0x70)
                M020 (Zero, 0x03, One, 0x70, (OFT1 & 0xFFFF0000))
                Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x2000)
                \_SB.PCI0.SBRG.EC0.VGAT = One
                Release (\_SB.PCI0.SBRG.EC0.MUT0)
                Acquire (\_SB.PCI0.SBRG.EC0.MUT1, 0x2000)
                \_SB.ALIB (0x18, Zero)
                If ((\UMFG != One))
                {
                    If ((GSTA () != Zero))
                    {
                        Return (Zero)
                    }

                    Local4 = M453 /* External reference */
                    M453 = Zero
                    If ((\_SB.PCI0.GPP9.TDGC == One))
                    {
                        If ((\_SB.PCI0.GPP9.DGCX == 0x03))
                        {
                            \_SB.PCI0.GPP9.PEGP.GC6O ()
                        }
                        ElseIf ((\_SB.PCI0.GPP9.DGCX == 0x04))
                        {
                            \_SB.PCI0.GPP9.PEGP.GC6O ()
                        }

                        \_SB.PCI0.GPP9.TDGC = Zero
                        \_SB.PCI0.GPP9.DGCX = Zero
                    }
                    Else
                    {
                        \_SB.PCI0.GPP9.BPGN ()
                        \_SB.PCI0.GPP9.PON ()
                        \_SB.PCI0.GPP9.L23D (PTOF)
                        \_SB.PCI0.GPP9.LREN = \_SB.PCI0.GPP9.PEGP.LTRE
                        \_SB.PCI0.GPP9.CEDR = One
                        \_SB.PCI0.GPP9.PEGP.SSSV = HYSS /* \HYSS */
                        \_SB.PCI0.GPP9.APGN ()
                    }

                    M453 = Local4
                    Local5 = M019 (Zero, 0x03, One, 0x70)
                    M020 (Zero, 0x03, One, 0x70, (OFT1 | Local5))
                    Local5 = M019 (Zero, 0x03, One, 0x70)
                }

                \_SB.ALIB (0x18, One)
                Release (\_SB.PCI0.SBRG.EC0.MUT1)
            }

            Method (_OFF, 0, Serialized)  // _OFF: Power Off
            {
                Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x2000)
                \_SB.PCI0.SBRG.EC0.VGAT = Zero
                Release (\_SB.PCI0.SBRG.EC0.MUT0)
                Acquire (\_SB.PCI0.SBRG.EC0.MUT1, 0x2000)
                If ((\UMFG != One))
                {
                    If ((GSTA () != One))
                    {
                        Return (Zero)
                    }

                    Local4 = M453 /* External reference */
                    M453 = Zero
                    If ((\_SB.PCI0.GPP9.TDGC == One))
                    {
                        CreateField (\_SB.PCI0.GPP9.TGPC, Zero, 0x03, GPPC)
                        If ((ToInteger (GPPC) == One))
                        {
                            \_SB.PCI0.GPP9.PEGP.GC6I ()
                        }
                        ElseIf ((ToInteger (GPPC) == 0x02))
                        {
                            \_SB.PCI0.GPP9.PEGP.GC6I ()
                        }
                    }
                    Else
                    {
                        Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x2000)
                        Local0 = \_SB.PCI0.SBRG.EC0.VIUF /* External reference */
                        Release (\_SB.PCI0.SBRG.EC0.MUT0)
                        If ((Local0 == Zero))
                        {
                            \_SB.PCI0.GPP9.BPGF ()
                            \_SB.PCI0.GPP9.PEGP.LTRE = \_SB.PCI0.GPP9.LREN
                            Sleep (0x18)
                            Local1 = M019 (Zero, 0x03, One, 0x54)
                            M020 (Zero, 0x03, One, 0x54, (Local1 & 0xFFFF7FFC))
                            Sleep (One)
                            Local2 = M017 (Zero, 0x03, One, 0x19, Zero, 0x08)
                            M028 (Local2, Zero, Zero, Zero)
                            Local3 = M027 (Local2, Zero, Zero)
                            M020 (Zero, 0x03, One, 0x54, (Local1 & 0xFFFF7FFF))
                            \_SB.PCI0.GPP9.DL23 (PTOF)
                            \_SB.PCI0.GPP9.POFF ()
                            \_SB.PCI0.GPP9.APGF ()
                            M018 (Zero, 0x03, One, 0x70, Zero, 0x10, Local2)
                            M023 (Zero, 0x03, One)
                        }
                    }

                    M453 = Local4
                    Local5 = M019 (Zero, 0x03, One, 0x70)
                    M020 (Zero, 0x03, One, 0x70, (OFT1 | Local5))
                    Local5 = M019 (Zero, 0x03, One, 0x70)
                }

                Release (\_SB.PCI0.SBRG.EC0.MUT1)
            }
        }

        Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
        {
            PG00, 
        })
        Name (_PR2, Package (0x01)  // _PR2: Power Resources for D2
        {
            PG00, 
        })
        Name (_PR3, Package (0x01)  // _PR3: Power Resources for D3hot
        {
            PG00, 
        })
        Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
        {
            Return (0x04)
        }
    }

    Scope (\_SB.PCI0.GPP9.PEGP)
    {
        OperationRegion (PCIM, SystemMemory, EBAS, 0x0500)
        Field (PCIM, DWordAcc, Lock, Preserve)
        {
            NVID,   16, 
            NDID,   16, 
            Offset (0x04), 
            CMDR,   8, 
            VGAR,   2008, 
            Offset (0x48B), 
                ,   1, 
            HDAE,   1
        }

        OperationRegion (MSID, SystemMemory, EBAS, 0x0500)
        Field (MSID, DWordAcc, NoLock, Preserve)
        {
            Offset (0x40), 
            SSSV,   32
        }

        Name (VGAB, Buffer (0xFA)
        {
             0x00                                             // .
        })
        Name (GPRF, Zero)
        Name (LTRE, Zero)
        Name (OMPR, 0x02)
        Name (DGPS, Zero)
        OperationRegion (NVHM, SystemMemory, NVHA, 0x00030400)
        Field (NVHM, DWordAcc, NoLock, Preserve)
        {
            NVSG,   128, 
            NVSZ,   32, 
            NVVR,   32, 
            NVHO,   32, 
            RVBS,   32, 
            RBF1,   262144, 
            RBF2,   262144, 
            RBF3,   262144, 
            RBF4,   262144, 
            RBF5,   262144, 
            RBF6,   262144, 
            MXML,   32, 
            MXM3,   1600
        }

        Method (SGST, 0, Serialized)
        {
            If ((NVID != 0xFFFF))
            {
                Return (0x0F)
            }

            Return (Zero)
        }

        Name (_PSC, Zero)  // _PSC: Power State Current
        Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
        {
            If ((\CUMA == Zero))
            {
                _PSC = Zero
                If ((DGPS != Zero))
                {
                    \_SB.PCI0.SBRG.EC0.NVPS = One
                    \_SB.PCI0.GPP9.PG00._ON ()
                    If ((GPRF != One))
                    {
                        VGAR = VGAB /* \_SB_.PCI0.GPP9.PEGP.VGAB */
                    }

                    DGPS = Zero
                    \_SB.PCI0.SBRG.EC0.NVPS = Zero
                }
            }
        }

        Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
        {
            If ((\CUMA == Zero))
            {
                If ((OMPR == 0x03))
                {
                    If ((GPRF != One))
                    {
                        VGAB = VGAR /* \_SB_.PCI0.GPP9.PEGP.VGAR */
                    }

                    \_SB.PCI0.GPP9.PG00._OFF ()
                    DGPS = One
                    OMPR = 0x02
                }

                _PSC = 0x03
            }
        }

        Method (NBCI, 4, Serialized)
        {
            Debug = "<<< NBCI >>>"
            If ((Arg1 != 0x0102))
            {
                Return (0x80000002)
            }

            Switch (ToInteger (Arg2))
            {
                Case (Zero)
                {
                    Return (Buffer (0x04)
                    {
                         0x01, 0x00, 0x11, 0x00                           // ....
                    })
                }
                Case (0x10)
                {
                    CreateWordField (Arg3, 0x02, USRG)
                    OperationRegion (EDM2, SystemMemory, (\_SB.PCI0.SBRG.EC0.EDAD + 0x08), 0x0100)
                    Field (EDM2, AnyAcc, NoLock, Preserve)
                    {
                        PDVD,   32
                    }

                    Name (BF22, Buffer (0x04)
                    {
                         0x00                                             // .
                    })
                    If ((USRG == 0x4452))
                    {
                        Debug = "Get DR key"
                        If ((PDVD == 0x0C19E509))
                        {
                            Debug = "Get DR key BOE"
                            Return (Buffer (0xD7)
                            {
                                /* 0000 */  0x7E, 0x78, 0x9F, 0x8B, 0x09, 0x99, 0x0D, 0x16,  // ~x......
                                /* 0008 */  0x52, 0x44, 0xD7, 0x00, 0x00, 0x00, 0x00, 0x01,  // RD......
                                /* 0010 */  0x00, 0x00, 0x00, 0x00, 0xDE, 0x10, 0x00, 0x00,  // ........
                                /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 0020 */  0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x00,  // ......4.
                                /* 0028 */  0x00, 0x00, 0x01, 0x00, 0x47, 0x00, 0x00, 0x00,  // ....G...
                                /* 0030 */  0x02, 0x00, 0x45, 0x00, 0x00, 0x00, 0x03, 0x00,  // ..E.....
                                /* 0038 */  0x87, 0x00, 0x00, 0x00, 0x04, 0x00, 0x85, 0x00,  // ........
                                /* 0040 */  0x00, 0x00, 0x05, 0x00, 0x83, 0x00, 0x00, 0x00,  // ........
                                /* 0048 */  0x06, 0x00, 0x81, 0x00, 0x00, 0x00, 0x07, 0x00,  // ........
                                /* 0050 */  0x7F, 0x00, 0x00, 0x00, 0x08, 0x00, 0x7D, 0x00,  // ......}.
                                /* 0058 */  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xD9, 0x1C,  // ........
                                /* 0060 */  0x04, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // ........
                                /* 0068 */  0x41, 0x5D, 0xC9, 0x00, 0x01, 0x24, 0x2E, 0x00,  // A]...$..
                                /* 0070 */  0x02, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x01,  // ........
                                /* 0078 */  0x00, 0x00, 0x00, 0xD9, 0x1C, 0x04, 0x00, 0x00,  // ........
                                /* 0080 */  0x00, 0x02, 0x00, 0x00, 0x00, 0xE0, 0x7C, 0x97,  // ......|.
                                /* 0088 */  0x01, 0xC4, 0xD5, 0xC4, 0x32, 0x00, 0x00, 0x00,  // ....2...
                                /* 0090 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00,  // .....&..
                                /* 0098 */  0x00, 0x32, 0x00, 0x34, 0x00, 0x30, 0x00, 0x2A,  // .2.4.0.*
                                /* 00A0 */  0x00, 0x31, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30,  // .1.0.0.0
                                /* 00A8 */  0x00, 0x30, 0x00, 0x3B, 0x00, 0x36, 0x00, 0x30,  // .0.;.6.0
                                /* 00B0 */  0x00, 0x2A, 0x00, 0x34, 0x00, 0x30, 0x00, 0x30,  // .*.4.0.0
                                /* 00B8 */  0x00, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00,  // .0.0....
                                /* 00C0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00C8 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00D0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00         // .......
                            })
                        }

                        If ((PDVD == 0x158E104D))
                        {
                            Debug = "Get DR key SHARP"
                            Return (Buffer (0xD7)
                            {
                                /* 0000 */  0x7E, 0x78, 0x9F, 0x8B, 0x09, 0x99, 0x0D, 0x16,  // ~x......
                                /* 0008 */  0x52, 0x44, 0xD7, 0x00, 0x00, 0x00, 0x00, 0x01,  // RD......
                                /* 0010 */  0x00, 0x00, 0x00, 0x00, 0xDE, 0x10, 0x00, 0x00,  // ........
                                /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 0020 */  0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x00,  // ......4.
                                /* 0028 */  0x00, 0x00, 0x01, 0x00, 0x47, 0x00, 0x00, 0x00,  // ....G...
                                /* 0030 */  0x02, 0x00, 0x45, 0x00, 0x00, 0x00, 0x03, 0x00,  // ..E.....
                                /* 0038 */  0x87, 0x00, 0x00, 0x00, 0x04, 0x00, 0x85, 0x00,  // ........
                                /* 0040 */  0x00, 0x00, 0x05, 0x00, 0x83, 0x00, 0x00, 0x00,  // ........
                                /* 0048 */  0x06, 0x00, 0x81, 0x00, 0x00, 0x00, 0x07, 0x00,  // ........
                                /* 0050 */  0x7F, 0x00, 0x00, 0x00, 0x08, 0x00, 0x7D, 0x00,  // ......}.
                                /* 0058 */  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xD9, 0x1C,  // ........
                                /* 0060 */  0x04, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // ........
                                /* 0068 */  0x41, 0x5D, 0xC9, 0x00, 0x01, 0x24, 0x2E, 0x00,  // A]...$..
                                /* 0070 */  0x02, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x01,  // ........
                                /* 0078 */  0x00, 0x00, 0x00, 0xD9, 0x1C, 0x04, 0x00, 0x00,  // ........
                                /* 0080 */  0x00, 0x02, 0x00, 0x00, 0x00, 0xE0, 0x7C, 0x97,  // ......|.
                                /* 0088 */  0x01, 0xC4, 0xD5, 0xC4, 0x32, 0x00, 0x00, 0x00,  // ....2...
                                /* 0090 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00,  // .....&..
                                /* 0098 */  0x00, 0x32, 0x00, 0x34, 0x00, 0x30, 0x00, 0x2A,  // .2.4.0.*
                                /* 00A0 */  0x00, 0x31, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30,  // .1.0.0.0
                                /* 00A8 */  0x00, 0x30, 0x00, 0x3B, 0x00, 0x36, 0x00, 0x30,  // .0.;.6.0
                                /* 00B0 */  0x00, 0x2A, 0x00, 0x34, 0x00, 0x30, 0x00, 0x30,  // .*.4.0.0
                                /* 00B8 */  0x00, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00,  // .0.0....
                                /* 00C0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00C8 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00D0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00         // .......
                            })
                        }

                        If ((PDVD == 0x41AE834C))
                        {
                            Debug = "Get DR key SDC"
                            Return (Buffer (0xD7)
                            {
                                /* 0000 */  0x7E, 0x78, 0x9F, 0x8B, 0x09, 0x99, 0x0D, 0x16,  // ~x......
                                /* 0008 */  0x52, 0x44, 0xD7, 0x00, 0x00, 0x00, 0x00, 0x01,  // RD......
                                /* 0010 */  0x00, 0x00, 0x00, 0x00, 0xDE, 0x10, 0x00, 0x00,  // ........
                                /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 0020 */  0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x00,  // ......4.
                                /* 0028 */  0x00, 0x00, 0x01, 0x00, 0x47, 0x00, 0x00, 0x00,  // ....G...
                                /* 0030 */  0x02, 0x00, 0x45, 0x00, 0x00, 0x00, 0x03, 0x00,  // ..E.....
                                /* 0038 */  0x87, 0x00, 0x00, 0x00, 0x04, 0x00, 0x85, 0x00,  // ........
                                /* 0040 */  0x00, 0x00, 0x05, 0x00, 0x83, 0x00, 0x00, 0x00,  // ........
                                /* 0048 */  0x06, 0x00, 0x81, 0x00, 0x00, 0x00, 0x07, 0x00,  // ........
                                /* 0050 */  0x7F, 0x00, 0x00, 0x00, 0x08, 0x00, 0x7D, 0x00,  // ......}.
                                /* 0058 */  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xD9, 0x1C,  // ........
                                /* 0060 */  0x04, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // ........
                                /* 0068 */  0x41, 0x5D, 0xC9, 0x00, 0x01, 0x24, 0x2E, 0x00,  // A]...$..
                                /* 0070 */  0x02, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x01,  // ........
                                /* 0078 */  0x00, 0x00, 0x00, 0xD9, 0x1C, 0x04, 0x00, 0x00,  // ........
                                /* 0080 */  0x00, 0x02, 0x00, 0x00, 0x00, 0xE0, 0x7C, 0x97,  // ......|.
                                /* 0088 */  0x01, 0xC4, 0xD5, 0xC4, 0x32, 0x00, 0x00, 0x00,  // ....2...
                                /* 0090 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00,  // .....&..
                                /* 0098 */  0x00, 0x32, 0x00, 0x34, 0x00, 0x30, 0x00, 0x2A,  // .2.4.0.*
                                /* 00A0 */  0x00, 0x31, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30,  // .1.0.0.0
                                /* 00A8 */  0x00, 0x30, 0x00, 0x3B, 0x00, 0x36, 0x00, 0x30,  // .0.;.6.0
                                /* 00B0 */  0x00, 0x2A, 0x00, 0x34, 0x00, 0x30, 0x00, 0x30,  // .*.4.0.0
                                /* 00B8 */  0x00, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00,  // .0.0....
                                /* 00C0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00C8 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00D0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00         // .......
                            })
                        }

                        If ((PDVD == 0x419C834C))
                        {
                            Debug = "Get DR key SDC"
                            Return (Buffer (0xD7)
                            {
                                /* 0000 */  0x28, 0xE2, 0x00, 0x62, 0xC1, 0xB3, 0x8C, 0x1B,  // (..b....
                                /* 0008 */  0x52, 0x44, 0xD7, 0x00, 0x00, 0x00, 0x00, 0x01,  // RD......
                                /* 0010 */  0x00, 0x00, 0x00, 0x00, 0xDE, 0x10, 0x00, 0x00,  // ........
                                /* 0018 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 0020 */  0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x34, 0x00,  // ......4.
                                /* 0028 */  0x00, 0x00, 0x01, 0x00, 0x47, 0x00, 0x00, 0x00,  // ....G...
                                /* 0030 */  0x02, 0x00, 0x45, 0x00, 0x00, 0x00, 0x03, 0x00,  // ..E.....
                                /* 0038 */  0x87, 0x00, 0x00, 0x00, 0x04, 0x00, 0x85, 0x00,  // ........
                                /* 0040 */  0x00, 0x00, 0x05, 0x00, 0x83, 0x00, 0x00, 0x00,  // ........
                                /* 0048 */  0x06, 0x00, 0x81, 0x00, 0x00, 0x00, 0x07, 0x00,  // ........
                                /* 0050 */  0x7F, 0x00, 0x00, 0x00, 0x08, 0x00, 0x7D, 0x00,  // ......}.
                                /* 0058 */  0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xD9, 0x1C,  // ........
                                /* 0060 */  0x04, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,  // ........
                                /* 0068 */  0x41, 0x5D, 0xC9, 0x00, 0x01, 0x24, 0x2E, 0x00,  // A]...$..
                                /* 0070 */  0x02, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x01,  // ........
                                /* 0078 */  0x00, 0x00, 0x00, 0xD9, 0x1C, 0x04, 0x00, 0x00,  // ........
                                /* 0080 */  0x00, 0x02, 0x00, 0x00, 0x00, 0xE0, 0x7C, 0x97,  // ......|.
                                /* 0088 */  0x01, 0xC4, 0xD5, 0xC4, 0x32, 0x00, 0x00, 0x00,  // ....2...
                                /* 0090 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00,  // .....&..
                                /* 0098 */  0x00, 0x31, 0x00, 0x32, 0x00, 0x30, 0x00, 0x2A,  // .1.2.0.*
                                /* 00A0 */  0x00, 0x32, 0x00, 0x30, 0x00, 0x30, 0x00, 0x30,  // .2.0.0.0
                                /* 00A8 */  0x00, 0x30, 0x00, 0x3B, 0x00, 0x36, 0x00, 0x30,  // .0.;.6.0
                                /* 00B0 */  0x00, 0x2A, 0x00, 0x34, 0x00, 0x30, 0x00, 0x30,  // .*.4.0.0
                                /* 00B8 */  0x00, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00,  // .0.0....
                                /* 00C0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00C8 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                                /* 00D0 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00         // .......
                            })
                        }
                    }

                    If ((USRG == 0x564B))
                    {
                        Debug = "Get VK key"
                        If ((PDVD == 0x0C19E509))
                        {
                            Debug = "Get VK key BOE"
                            Return (Buffer (0xC9)
                            {
                                /* 0000 */  0x0C, 0x79, 0x75, 0x92, 0x3C, 0x12, 0xF1, 0xEC,  // .yu.<...
                                /* 0008 */  0x4B, 0x56, 0xC9, 0x00, 0x00, 0x00, 0x01, 0x00,  // KV......
                                /* 0010 */  0x39, 0x31, 0x34, 0x35, 0x37, 0x32, 0x32, 0x32,  // 91457222
                                /* 0018 */  0x37, 0x37, 0x31, 0x36, 0x47, 0x65, 0x6E, 0x75,  // 7716Genu
                                /* 0020 */  0x69, 0x6E, 0x65, 0x20, 0x4E, 0x56, 0x49, 0x44,  // ine NVID
                                /* 0028 */  0x49, 0x41, 0x20, 0x43, 0x65, 0x72, 0x74, 0x69,  // IA Certi
                                /* 0030 */  0x66, 0x69, 0x65, 0x64, 0x20, 0x47, 0x53, 0x79,  // fied GSy
                                /* 0038 */  0x6E, 0x63, 0x20, 0x52, 0x65, 0x61, 0x64, 0x79,  // nc Ready
                                /* 0040 */  0x20, 0x50, 0x6C, 0x61, 0x74, 0x66, 0x6F, 0x72,  //  Platfor
                                /* 0048 */  0x6D, 0x20, 0x66, 0x6F, 0x72, 0x20, 0x4B, 0x59,  // m for KY
                                /* 0050 */  0x5A, 0x53, 0x4B, 0x46, 0x4A, 0x57, 0x54, 0x50,  // ZSKFJWTP
                                /* 0058 */  0x41, 0x52, 0x57, 0x45, 0x57, 0x4F, 0x54, 0x58,  // ARWEWOTX
                                /* 0060 */  0x48, 0x4C, 0x20, 0x2D, 0x20, 0x4D, 0x30, 0x5D,  // HL - M0]
                                /* 0068 */  0x4F, 0x3D, 0x55, 0x23, 0x46, 0x52, 0x5D, 0x26,  // O=U#FR]&
                                /* 0070 */  0x25, 0x49, 0x44, 0x56, 0x5D, 0x4B, 0x29, 0x3D,  // %IDV]K)=
                                /* 0078 */  0x5C, 0x56, 0x4E, 0x2F, 0x2E, 0x39, 0x3E, 0x32,  // \VN/.9>2
                                /* 0080 */  0x44, 0x20, 0x2D, 0x20, 0x43, 0x6F, 0x70, 0x79,  // D - Copy
                                /* 0088 */  0x72, 0x69, 0x67, 0x68, 0x74, 0x20, 0x32, 0x30,  // right 20
                                /* 0090 */  0x32, 0x33, 0x20, 0x4E, 0x56, 0x49, 0x44, 0x49,  // 23 NVIDI
                                /* 0098 */  0x41, 0x20, 0x43, 0x6F, 0x72, 0x70, 0x6F, 0x72,  // A Corpor
                                /* 00A0 */  0x61, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x41, 0x6C,  // ation Al
                                /* 00A8 */  0x6C, 0x20, 0x52, 0x69, 0x67, 0x68, 0x74, 0x73,  // l Rights
                                /* 00B0 */  0x20, 0x52, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65,  //  Reserve
                                /* 00B8 */  0x64, 0x2D, 0x37, 0x32, 0x35, 0x31, 0x31, 0x35,  // d-725115
                                /* 00C0 */  0x36, 0x36, 0x31, 0x33, 0x33, 0x31, 0x28, 0x52,  // 661331(R
                                /* 00C8 */  0x29                                             // )
                            })
                        }

                        If ((PDVD == 0x158E104D))
                        {
                            Debug = "Get VK key SHARP"
                            Return (Buffer (0xC9)
                            {
                                /* 0000 */  0xA3, 0xCE, 0x2A, 0x90, 0x7B, 0x7A, 0x26, 0x2F,  // ..*.{z&/
                                /* 0008 */  0x4B, 0x56, 0xC9, 0x00, 0x00, 0x00, 0x01, 0x00,  // KV......
                                /* 0010 */  0x39, 0x31, 0x34, 0x35, 0x37, 0x32, 0x32, 0x32,  // 91457222
                                /* 0018 */  0x37, 0x37, 0x31, 0x36, 0x47, 0x65, 0x6E, 0x75,  // 7716Genu
                                /* 0020 */  0x69, 0x6E, 0x65, 0x20, 0x4E, 0x56, 0x49, 0x44,  // ine NVID
                                /* 0028 */  0x49, 0x41, 0x20, 0x43, 0x65, 0x72, 0x74, 0x69,  // IA Certi
                                /* 0030 */  0x66, 0x69, 0x65, 0x64, 0x20, 0x47, 0x53, 0x79,  // fied GSy
                                /* 0038 */  0x6E, 0x63, 0x20, 0x52, 0x65, 0x61, 0x64, 0x79,  // nc Ready
                                /* 0040 */  0x20, 0x50, 0x6C, 0x61, 0x74, 0x66, 0x6F, 0x72,  //  Platfor
                                /* 0048 */  0x6D, 0x20, 0x66, 0x6F, 0x72, 0x20, 0x46, 0x46,  // m for FF
                                /* 0050 */  0x47, 0x42, 0x46, 0x4C, 0x57, 0x5A, 0x48, 0x4B,  // GBFLWZHK
                                /* 0058 */  0x50, 0x49, 0x56, 0x4F, 0x48, 0x42, 0x4F, 0x4E,  // PIVOHBON
                                /* 0060 */  0x42, 0x45, 0x20, 0x2D, 0x20, 0x2B, 0x54, 0x41,  // BE - +TA
                                /* 0068 */  0x39, 0x3B, 0x56, 0x58, 0x36, 0x48, 0x3B, 0x42,  // 9;VX6H;B
                                /* 0070 */  0x31, 0x5C, 0x33, 0x5A, 0x5E, 0x2C, 0x42, 0x5E,  // 1\3Z^,B^
                                /* 0078 */  0x4E, 0x3F, 0x4E, 0x2C, 0x51, 0x47, 0x54, 0x2C,  // N?N,QGT,
                                /* 0080 */  0x21, 0x20, 0x2D, 0x20, 0x43, 0x6F, 0x70, 0x79,  // ! - Copy
                                /* 0088 */  0x72, 0x69, 0x67, 0x68, 0x74, 0x20, 0x32, 0x30,  // right 20
                                /* 0090 */  0x32, 0x33, 0x20, 0x4E, 0x56, 0x49, 0x44, 0x49,  // 23 NVIDI
                                /* 0098 */  0x41, 0x20, 0x43, 0x6F, 0x72, 0x70, 0x6F, 0x72,  // A Corpor
                                /* 00A0 */  0x61, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x41, 0x6C,  // ation Al
                                /* 00A8 */  0x6C, 0x20, 0x52, 0x69, 0x67, 0x68, 0x74, 0x73,  // l Rights
                                /* 00B0 */  0x20, 0x52, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65,  //  Reserve
                                /* 00B8 */  0x64, 0x2D, 0x37, 0x32, 0x35, 0x31, 0x31, 0x35,  // d-725115
                                /* 00C0 */  0x36, 0x36, 0x31, 0x33, 0x33, 0x31, 0x28, 0x52,  // 661331(R
                                /* 00C8 */  0x29                                             // )
                            })
                        }

                        If ((PDVD == 0x41AE834C))
                        {
                            Debug = "Get VK key SDC"
                            Return (Buffer (0xC9)
                            {
                                /* 0000 */  0x90, 0x38, 0x90, 0x90, 0x2C, 0x9D, 0x80, 0xDC,  // .8..,...
                                /* 0008 */  0x4B, 0x56, 0xC9, 0x00, 0x00, 0x00, 0x01, 0x00,  // KV......
                                /* 0010 */  0x39, 0x31, 0x34, 0x35, 0x37, 0x32, 0x32, 0x32,  // 91457222
                                /* 0018 */  0x37, 0x37, 0x31, 0x36, 0x47, 0x65, 0x6E, 0x75,  // 7716Genu
                                /* 0020 */  0x69, 0x6E, 0x65, 0x20, 0x4E, 0x56, 0x49, 0x44,  // ine NVID
                                /* 0028 */  0x49, 0x41, 0x20, 0x43, 0x65, 0x72, 0x74, 0x69,  // IA Certi
                                /* 0030 */  0x66, 0x69, 0x65, 0x64, 0x20, 0x47, 0x53, 0x79,  // fied GSy
                                /* 0038 */  0x6E, 0x63, 0x20, 0x52, 0x65, 0x61, 0x64, 0x79,  // nc Ready
                                /* 0040 */  0x20, 0x50, 0x6C, 0x61, 0x74, 0x66, 0x6F, 0x72,  //  Platfor
                                /* 0048 */  0x6D, 0x20, 0x66, 0x6F, 0x72, 0x20, 0x4F, 0x4D,  // m for OM
                                /* 0050 */  0x4D, 0x47, 0x47, 0x46, 0x49, 0x5A, 0x59, 0x4C,  // MGGFIZYL
                                /* 0058 */  0x55, 0x54, 0x4A, 0x45, 0x46, 0x55, 0x55, 0x5A,  // UTJEFUUZ
                                /* 0060 */  0x53, 0x56, 0x20, 0x2D, 0x20, 0x41, 0x42, 0x4F,  // SV - ABO
                                /* 0068 */  0x3F, 0x4C, 0x24, 0x22, 0x53, 0x3E, 0x28, 0x4F,  // ?L$"S>(O
                                /* 0070 */  0x4D, 0x53, 0x26, 0x3F, 0x39, 0x49, 0x4D, 0x5A,  // MS&?9IMZ
                                /* 0078 */  0x45, 0x32, 0x5A, 0x3A, 0x36, 0x5E, 0x25, 0x53,  // E2Z:6^%S
                                /* 0080 */  0x21, 0x20, 0x2D, 0x20, 0x43, 0x6F, 0x70, 0x79,  // ! - Copy
                                /* 0088 */  0x72, 0x69, 0x67, 0x68, 0x74, 0x20, 0x32, 0x30,  // right 20
                                /* 0090 */  0x32, 0x33, 0x20, 0x4E, 0x56, 0x49, 0x44, 0x49,  // 23 NVIDI
                                /* 0098 */  0x41, 0x20, 0x43, 0x6F, 0x72, 0x70, 0x6F, 0x72,  // A Corpor
                                /* 00A0 */  0x61, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x41, 0x6C,  // ation Al
                                /* 00A8 */  0x6C, 0x20, 0x52, 0x69, 0x67, 0x68, 0x74, 0x73,  // l Rights
                                /* 00B0 */  0x20, 0x52, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65,  //  Reserve
                                /* 00B8 */  0x64, 0x2D, 0x37, 0x32, 0x35, 0x31, 0x31, 0x35,  // d-725115
                                /* 00C0 */  0x36, 0x36, 0x31, 0x33, 0x33, 0x31, 0x28, 0x52,  // 661331(R
                                /* 00C8 */  0x29                                             // )
                            })
                        }

                        If ((PDVD == 0x419C834C))
                        {
                            Debug = "Get VK key SDC"
                            Return (Buffer (0xC9)
                            {
                                /* 0000 */  0x22, 0xF9, 0xD7, 0xA5, 0xAF, 0xEA, 0x62, 0x18,  // ".....b.
                                /* 0008 */  0x4B, 0x56, 0xC9, 0x00, 0x00, 0x00, 0x01, 0x00,  // KV......
                                /* 0010 */  0x39, 0x31, 0x34, 0x35, 0x37, 0x32, 0x32, 0x32,  // 91457222
                                /* 0018 */  0x37, 0x37, 0x31, 0x36, 0x47, 0x65, 0x6E, 0x75,  // 7716Genu
                                /* 0020 */  0x69, 0x6E, 0x65, 0x20, 0x4E, 0x56, 0x49, 0x44,  // ine NVID
                                /* 0028 */  0x49, 0x41, 0x20, 0x43, 0x65, 0x72, 0x74, 0x69,  // IA Certi
                                /* 0030 */  0x66, 0x69, 0x65, 0x64, 0x20, 0x47, 0x53, 0x79,  // fied GSy
                                /* 0038 */  0x6E, 0x63, 0x20, 0x52, 0x65, 0x61, 0x64, 0x79,  // nc Ready
                                /* 0040 */  0x20, 0x50, 0x6C, 0x61, 0x74, 0x66, 0x6F, 0x72,  //  Platfor
                                /* 0048 */  0x6D, 0x20, 0x66, 0x6F, 0x72, 0x20, 0x49, 0x41,  // m for IA
                                /* 0050 */  0x43, 0x4F, 0x42, 0x46, 0x4D, 0x4A, 0x52, 0x57,  // COBFMJRW
                                /* 0058 */  0x46, 0x4F, 0x41, 0x57, 0x46, 0x5A, 0x47, 0x49,  // FOAWFZGI
                                /* 0060 */  0x53, 0x4A, 0x20, 0x2D, 0x20, 0x50, 0x5C, 0x4A,  // SJ - P\J
                                /* 0068 */  0x42, 0x26, 0x3E, 0x4E, 0x2D, 0x38, 0x2B, 0x3C,  // B&>N-8+<
                                /* 0070 */  0x27, 0x32, 0x32, 0x4E, 0x3C, 0x4C, 0x38, 0x30,  // '22N<L80
                                /* 0078 */  0x27, 0x5D, 0x29, 0x48, 0x31, 0x26, 0x34, 0x4D,  // '])H1&4M
                                /* 0080 */  0x41, 0x20, 0x2D, 0x20, 0x43, 0x6F, 0x70, 0x79,  // A - Copy
                                /* 0088 */  0x72, 0x69, 0x67, 0x68, 0x74, 0x20, 0x32, 0x30,  // right 20
                                /* 0090 */  0x32, 0x33, 0x20, 0x4E, 0x56, 0x49, 0x44, 0x49,  // 23 NVIDI
                                /* 0098 */  0x41, 0x20, 0x43, 0x6F, 0x72, 0x70, 0x6F, 0x72,  // A Corpor
                                /* 00A0 */  0x61, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x41, 0x6C,  // ation Al
                                /* 00A8 */  0x6C, 0x20, 0x52, 0x69, 0x67, 0x68, 0x74, 0x73,  // l Rights
                                /* 00B0 */  0x20, 0x52, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65,  //  Reserve
                                /* 00B8 */  0x64, 0x2D, 0x37, 0x32, 0x35, 0x31, 0x31, 0x35,  // d-725115
                                /* 00C0 */  0x36, 0x36, 0x31, 0x33, 0x33, 0x31, 0x28, 0x52,  // 661331(R
                                /* 00C8 */  0x29                                             // )
                            })
                        }
                    }

                    Return (0x80000002)
                }
                Case (0x14)
                {
                    Return (Package (0x20)
                    {
                        0x8000A450, 
                        0x0200, 
                        Zero, 
                        Zero, 
                        0x05, 
                        One, 
                        0x03E8, 
                        0x32, 
                        0x03E8, 
                        0x0B, 
                        0x32, 
                        0x64, 
                        0x96, 
                        0xC8, 
                        0x012C, 
                        0x0190, 
                        0x01FE, 
                        0x0276, 
                        0x02F8, 
                        0x0366, 
                        0x03E8, 
                        Zero, 
                        0x64, 
                        0xC8, 
                        0x012C, 
                        0x0190, 
                        0x01F4, 
                        0x0258, 
                        0x02BC, 
                        0x0320, 
                        0x0384, 
                        0x03E8
                    })
                }

            }

            Return (0x80000002)
        }

        Method (NVOP, 4, Serialized)
        {
            Debug = "<<< NVOP >>>"
            If ((Arg1 != 0x0100))
            {
                Return (0x80000002)
            }

            Switch (ToInteger (Arg2))
            {
                Case (Zero)
                {
                    Return (Buffer (0x04)
                    {
                         0x01, 0x00, 0x00, 0x04                           // ....
                    })
                }
                Case (0x1A)
                {
                    CreateField (Arg3, Zero, One, FLCH)
                    CreateField (Arg3, One, One, DVSR)
                    CreateField (Arg3, 0x02, One, DVSC)
                    CreateField (Arg3, 0x18, 0x02, OPCE)
                    If ((ToInteger (FLCH) & (ToInteger (OPCE) != OMPR)))
                    {
                        \_SB.PCI0.GPP9.PEGP.OMPR = OPCE /* \_SB_.PCI0.GPP9.PEGP.NVOP.OPCE */
                    }

                    Local0 = Buffer (0x04)
                        {
                             0x00, 0x00, 0x00, 0x00                           // ....
                        }
                    CreateField (Local0, Zero, One, OPEN)
                    CreateField (Local0, 0x03, 0x02, CGCS)
                    CreateField (Local0, 0x06, One, SHPC)
                    CreateField (Local0, 0x08, One, SNSR)
                    CreateField (Local0, 0x18, 0x03, DGPC)
                    CreateField (Local0, 0x1B, 0x02, OHAC)
                    OPEN = One
                    SHPC = One
                    DGPC = One
                    OHAC = 0x03
                    If (ToInteger (DVSC))
                    {
                        If (ToInteger (DVSR))
                        {
                            GPRF = One
                        }
                        Else
                        {
                            GPRF = Zero
                        }
                    }

                    SNSR = GPRF /* \_SB_.PCI0.GPP9.PEGP.GPRF */
                    If ((DGPS == Zero))
                    {
                        CGCS = 0x03
                    }
                    Else
                    {
                        CGCS = Zero
                    }

                    Return (Local0)
                }
                Case (0x1B)
                {
                    Name (BUFF, Zero)
                    CreateField (Arg3, Zero, One, OACC)
                    CreateField (Arg3, One, One, UOAC)
                    CreateField (Arg3, 0x02, 0x08, OPDA)
                    CreateField (Arg3, 0x0A, One, OPDE)
                    Local1 = Zero
                    Local1 = \_SB.PCI0.GPP9.PEGP.HDAE
                    Return (Local1)
                }

            }

            Return (0x80000002)
        }

        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            CreateByteField (Arg0, 0x03, GUID)
            If ((Arg0 == ToUUID ("d4a50b75-65c7-46f7-bfb7-41514cea0244") /* Unknown UUID */))
            {
                Return (\_SB.PCI0.GPP9.PEGP.NBCI (Arg0, Arg1, Arg2, Arg3))
            }

            If ((Arg0 == ToUUID ("a3132d01-8cda-49ba-a52e-bc9d46df6b81") /* Unknown UUID */))
            {
                Return (\_SB.PCI0.GPP9.PEGP.GPS (Arg0, Arg1, Arg2, Arg3))
            }

            If ((Arg0 == ToUUID ("cbeca351-067b-4924-9cbd-b46b00b86f34") /* Unknown UUID */))
            {
                Return (\_SB.PCI0.GPP9.PEGP.NVJT (Arg0, Arg1, Arg2, Arg3))
            }

            If ((Arg0 == ToUUID ("a486d8f8-0bda-471b-a72b-6042a6b5bee0") /* Unknown UUID */))
            {
                Return (\_SB.PCI0.GPP9.PEGP.NVOP (Arg0, Arg1, Arg2, Arg3))
            }

            Return (0x80000001)
        }
    }

    Scope (\_SB.PCI0.GPP9.PEGP)
    {
        Method (GC6I, 0, Serialized)
        {
            Debug = "<<< GC6I >>>"
            \_SB.PCI0.GPP9.PEGP.LTRE = \_SB.PCI0.GPP9.LREN
            \_SB.PCI0.GPP9.DL23 (One)
            Sleep (0x0A)
            M010 (REST, Zero)
        }

        Method (GC6O, 0, Serialized)
        {
            Debug = "<<< GC6O >>>"
            M010 (REST, One)
            Sleep (0x0A)
            \_SB.PCI0.GPP9.L23D (One)
            \_SB.PCI0.GPP9.CMDR |= 0x04
            \_SB.PCI0.GPP9.D0ST = Zero
            While ((\_SB.PCI0.GPP9.PEGP.NVID != 0x10DE))
            {
                Sleep (One)
            }

            \_SB.PCI0.GPP9.LREN = \_SB.PCI0.GPP9.PEGP.LTRE
            \_SB.PCI0.GPP9.CEDR = One
        }

        Method (NVJT, 4, Serialized)
        {
            Debug = "------- NV JT DSM --------"
            If ((Arg1 < 0x0100))
            {
                Return (0x80000001)
            }

            Switch (ToInteger (Arg2))
            {
                Case (Zero)
                {
                    Debug = "JT fun0 JT_FUNC_SUPPORT"
                    Return (Buffer (0x04)
                    {
                         0x1B, 0x00, 0x00, 0x00                           // ....
                    })
                }
                Case (One)
                {
                    Debug = "JT fun1 JT_FUNC_CAPS"
                    Name (JTCA, Buffer (0x04)
                    {
                         0x00                                             // .
                    })
                    CreateField (JTCA, Zero, One, JTEN)
                    CreateField (JTCA, One, 0x02, SREN)
                    CreateField (JTCA, 0x03, 0x02, PLPR)
                    CreateField (JTCA, 0x05, One, SRPR)
                    CreateField (JTCA, 0x06, 0x02, FBPR)
                    CreateField (JTCA, 0x08, 0x02, GUPR)
                    CreateField (JTCA, 0x0A, One, GC6R)
                    CreateField (JTCA, 0x0B, One, PTRH)
                    CreateField (JTCA, 0x0D, One, MHYB)
                    CreateField (JTCA, 0x0E, One, RPCL)
                    CreateField (JTCA, 0x0F, 0x02, GC6V)
                    CreateField (JTCA, 0x11, One, GEIS)
                    CreateField (JTCA, 0x12, One, GSWS)
                    CreateField (JTCA, 0x14, 0x0C, JTRV)
                    JTEN = One
                    GC6R = Zero
                    RPCL = One
                    SREN = One
                    FBPR = Zero
                    MHYB = One
                    GC6V = 0x02
                    JTRV = 0x0200
                    Return (JTCA) /* \_SB_.PCI0.GPP9.PEGP.NVJT.JTCA */
                }
                Case (0x02)
                {
                    Debug = "JT fun2 JT_FUNC_POLICYSELECT"
                    Return (0x80000002)
                }
                Case (0x03)
                {
                    Debug = "JT fun3 JT_FUNC_POWERCONTROL"
                    CreateField (Arg3, Zero, 0x03, GPPC)
                    CreateField (Arg3, 0x04, One, PLPC)
                    CreateField (Arg3, 0x07, One, ECOC)
                    CreateField (Arg3, 0x0E, 0x02, DFGC)
                    CreateField (Arg3, 0x10, 0x03, GPCX)
                    \_SB.PCI0.GPP9.TGPC = Arg3
                    If (((ToInteger (GPPC) != Zero) || (ToInteger (DFGC
                        ) != Zero)))
                    {
                        TDGC = ToInteger (DFGC)
                        DGCX = ToInteger (GPCX)
                    }

                    Name (JTPC, Buffer (0x04)
                    {
                         0x00                                             // .
                    })
                    CreateField (JTPC, Zero, 0x03, GUPS)
                    CreateField (JTPC, 0x03, One, GPWO)
                    CreateField (JTPC, 0x07, One, PLST)
                    If ((ToInteger (DFGC) != Zero))
                    {
                        GPWO = One
                        GUPS = One
                        Return (JTPC) /* \_SB_.PCI0.GPP9.PEGP.NVJT.JTPC */
                    }

                    If ((ToInteger (GPPC) == One))
                    {
                        GC6I ()
                        PLST = One
                        GUPS = Zero
                    }
                    ElseIf ((ToInteger (GPPC) == 0x02))
                    {
                        GC6I ()
                        If ((ToInteger (PLPC) == Zero))
                        {
                            PLST = Zero
                        }

                        GUPS = Zero
                    }
                    ElseIf ((ToInteger (GPPC) == 0x03))
                    {
                        GC6O ()
                        If ((ToInteger (PLPC) != Zero))
                        {
                            PLST = Zero
                        }

                        GPWO = One
                        GUPS = One
                    }
                    ElseIf ((ToInteger (GPPC) == 0x04))
                    {
                        GC6O ()
                        If ((ToInteger (PLPC) != Zero))
                        {
                            PLST = Zero
                        }

                        GPWO = One
                        GUPS = One
                    }
                    ElseIf ((M009 (0x28) == One))
                    {
                        Debug = "   JT GETS() return 0x1"
                        GPWO = One
                        GUPS = One
                    }
                    Else
                    {
                        Debug = "   JT GETS() return 0x3"
                        GPWO = Zero
                        GUPS = 0x03
                    }

                    Return (JTPC) /* \_SB_.PCI0.GPP9.PEGP.NVJT.JTPC */
                }
                Case (0x04)
                {
                    Debug = "   JT fun4 JT_FUNC_PLATPOLICY"
                    CreateField (Arg3, 0x02, One, PAUD)
                    CreateField (Arg3, 0x03, One, PADM)
                    CreateField (Arg3, 0x04, 0x04, PDGS)
                    Local0 = Zero
                    Local0 = (\_SB.PCI0.GPP9.PEGP.HDAE << 0x02)
                    Return (Local0)
                }

            }

            Return (0x80000002)
        }
    }

    Scope (\_SB.PCI0.GPP9.PEGP)
    {
        Name (NLIM, Zero)
        Name (PSLS, Zero)
        Name (CTGP, Zero)
        Name (GPSP, Buffer (0x28){})
        CreateDWordField (GPSP, Zero, RETN)
        CreateDWordField (GPSP, 0x04, VRV1)
        CreateDWordField (GPSP, 0x08, TGPU)
        CreateDWordField (GPSP, 0x0C, PDTS)
        CreateDWordField (GPSP, 0x10, SFAN)
        CreateDWordField (GPSP, 0x14, SKNT)
        CreateDWordField (GPSP, 0x18, CPUE)
        CreateDWordField (GPSP, 0x1C, TMP1)
        CreateDWordField (GPSP, 0x20, TMP2)
        Method (GPS, 4, Serialized)
        {
            Debug = "------- NV GPS DSM --------"
            If ((Arg1 != 0x0200))
            {
                Return (0x80000002)
            }

            Switch (ToInteger (Arg2))
            {
                Case (Zero)
                {
                    Debug = "GPS fun 0"
                    Return (Buffer (0x08)
                    {
                         0x01, 0x00, 0x0C, 0x00, 0x01, 0x04, 0x00, 0x00   // ........
                    })
                }
                Case (0x12)
                {
                    Debug = "GPS fun 18"
                }
                Case (0x13)
                {
                    Debug = "GPS fun 19"
                    If (\_SB.PCI0.SBRG.EC0.ECOK)
                    {
                        Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x2000)
                        \_SB.PCI0.SBRG.EC0.SDNT = One
                        Release (\_SB.PCI0.SBRG.EC0.MUT0)
                    }

                    CreateDWordField (Arg3, Zero, TEMP)
                    If ((TEMP == Zero))
                    {
                        Return (0x04)
                    }

                    If ((TEMP && 0x04))
                    {
                        Return (0x04)
                    }
                }
                Case (0x20)
                {
                    Debug = "   GPS fun 32"
                    Name (RET1, Zero)
                    CreateBitField (Arg3, 0x02, SPBI)
                    If (NLIM)
                    {
                        RET1 |= One
                    }

                    If (PSLS)
                    {
                        RET1 |= 0x02
                    }

                    If (CTGP)
                    {
                        RET1 |= 0x00400000
                    }

                    Return (RET1) /* \_SB_.PCI0.GPP9.PEGP.GPS_.RET1 */
                }
                Case (0x2A)
                {
                    Debug = "   GPS fun 42"
                    CreateField (Arg3, Zero, 0x04, PSH0)
                    CreateBitField (Arg3, 0x08, GPUT)
                    VRV1 = 0x00010000
                    Switch (ToInteger (PSH0))
                    {
                        Case (Zero)
                        {
                            Return (GPSP) /* \_SB_.PCI0.GPP9.PEGP.GPSP */
                        }
                        Case (One)
                        {
                            RETN = 0x0100
                            RETN |= ToInteger (PSH0)
                            Return (GPSP) /* \_SB_.PCI0.GPP9.PEGP.GPSP */
                        }
                        Case (0x02)
                        {
                            RETN = 0x0102
                            If ((NBFM == One))
                            {
                                NBFM = Zero
                                TGPU = GTPM /* External reference */
                            }
                            Else
                            {
                                If ((TGPU == Zero))
                                {
                                    Local0 = \_SB.PCI0.SBRG.EC0.FTBL /* External reference */
                                    Switch (ToInteger (Local0))
                                    {
                                        Case (0x02)
                                        {
                                            TGPU = 0x57
                                        }
                                        Case (One)
                                        {
                                            TGPU = 0x57
                                        }
                                        Case (Zero)
                                        {
                                            TGPU = 0x57
                                        }
                                        Default
                                        {
                                            TGPU = 0x57
                                        }

                                    }
                                }
                                Else
                                {
                                }

                                NLIM = Zero
                            }

                            Return (GPSP) /* \_SB_.PCI0.GPP9.PEGP.GPSP */
                        }

                    }

                    Return (0x80000002)
                }

            }

            Return (0x80000002)
        }
    }

    Scope (\_SB)
    {
        Device (NPCF)
        {
            Name (ACBT, Zero)
            Name (DCBT, Zero)
            Name (DBAC, Zero)
            Name (DBDC, Zero)
            Name (AMAT, 0x78)
            Name (AMIT, 0xFFB0)
            Name (ATPP, 0xF0)
            Name (DTPP, Zero)
            Name (TPPL, 0x02A8)
            Name (DROS, Zero)
            Name (LTBL, Zero)
            Name (STBL, Zero)
            Name (CDIS, Zero)
            Name (CUSL, Zero)
            Name (CUCT, Zero)
            Name (WM2M, One)
            Name (CTDI, Zero)
            Name (GTDI, Zero)
            Name (AVGF, Zero)
            Name (AVGI, Zero)
            Name (AVG0, Zero)
            Name (AVG1, Zero)
            Name (AVG2, Zero)
            Name (AVG3, Zero)
            Name (AVG4, Zero)
            Name (SFTN, Zero)
            Method (GMIN, 2, Serialized)
            {
                If ((Arg0 > Arg1))
                {
                    Return (Arg1)
                }
                Else
                {
                    Return (Arg0)
                }
            }

            Method (GMAX, 2, Serialized)
            {
                If ((Arg0 > Arg1))
                {
                    Return (Arg0)
                }
                Else
                {
                    Return (Arg1)
                }
            }

            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                CDIS = Zero
                Return ("NVDA0820")
            }

            Method (_INI, 0, NotSerialized)  // _INI: Initialize
            {
                SFTN = 0x06
            }

            Name (_UID, "NPCF")  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((CDIS == One))
                {
                    Return (0x0D)
                }

                Return (0x0F)
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                CDIS = One
            }

            Method (CMPC, 2, NotSerialized)
            {
                Local1 = SizeOf (Arg0)
                If ((Local1 != SizeOf (Arg1)))
                {
                    Return (Zero)
                }

                Local0 = Zero
                While ((Local0 < Local1))
                {
                    If ((DerefOf (Arg0 [Local0]) != DerefOf (Arg1 [Local0]
                        )))
                    {
                        Return (Zero)
                    }

                    Local0++
                }

                Return (One)
            }

            Name (SCFI, Buffer (0x0C)
            {
                /* 0000 */  0xFF, 0x00, 0x3B, 0x44, 0x44, 0x46, 0x46, 0x48,  // ..;DDFFH
                /* 0008 */  0x48, 0x4A, 0x4A, 0x5F                           // HJJ_
            })
            Name (SGFI, Buffer (0x0C)
            {
                /* 0000 */  0xFF, 0x00, 0x37, 0x41, 0x41, 0x43, 0x43, 0x45,  // ..7AACCE
                /* 0008 */  0x45, 0x47, 0x47, 0x57                           // EGGW
            })
            Method (MAVT, 1, Serialized)
            {
                Switch (ToInteger (AVGI))
                {
                    Case (Zero)
                    {
                        AVG0 = Arg0
                    }
                    Case (One)
                    {
                        AVG1 = Arg0
                    }
                    Case (0x02)
                    {
                        AVG2 = Arg0
                    }
                    Case (0x03)
                    {
                        AVG3 = Arg0
                    }
                    Case (0x04)
                    {
                        AVG4 = Arg0
                    }

                }

                If ((AVGI >= 0x04))
                {
                    AVGI = Zero
                    AVGF = One
                }
                Else
                {
                    AVGI += One
                }

                If ((AVGF >= One))
                {
                    Divide ((AVG0 + (AVG1 + (AVG2 + (AVG3 + AVG4))
                        )), 0x05, Local1, Local0)
                }
                Else
                {
                    Divide ((AVG0 + (AVG1 + (AVG2 + (AVG3 + AVG4))
                        )), AVGI, Local1, Local0)
                }

                Return (Local0)
            }

            Method (FCPI, 1, Serialized)
            {
                Local0 = CTDI /* \_SB_.NPCF.CTDI */
                While ((Local0 < SFTN))
                {
                    Local1 = ((Local0 * 0x02) + One)
                    If ((Arg0 >= DerefOf (SCFI [Local1])))
                    {
                        CTDI = Local0
                        Local0++
                    }
                    Else
                    {
                        Break
                    }
                }

                If ((CTDI == Local0))
                {
                    While ((Local0 > Zero))
                    {
                        Local1 = (Local0 * 0x02)
                        If ((Arg0 <= DerefOf (SCFI [Local1])))
                        {
                            Local0--
                            CTDI = Local0
                        }
                        Else
                        {
                            Break
                        }
                    }
                }

                Return (CTDI) /* \_SB_.NPCF.CTDI */
            }

            Method (FGPI, 1, Serialized)
            {
                Local0 = GTDI /* \_SB_.NPCF.GTDI */
                While ((Local0 < SFTN))
                {
                    Local1 = ((Local0 * 0x02) + One)
                    If ((Arg0 >= DerefOf (SGFI [Local1])))
                    {
                        GTDI = Local0
                        Local0++
                    }
                    Else
                    {
                        Break
                    }
                }

                If ((GTDI == Local0))
                {
                    While ((Local0 > Zero))
                    {
                        Local1 = (Local0 * 0x02)
                        If ((Arg0 <= DerefOf (SGFI [Local1])))
                        {
                            Local0--
                            GTDI = Local0
                        }
                        Else
                        {
                            Break
                        }
                    }
                }

                Return (GTDI) /* \_SB_.NPCF.GTDI */
            }

            Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
            {
                If ((Arg0 == ToUUID ("36b49710-2483-11e7-9598-0800200c9a66") /* Unknown UUID */))
                {
                    Return (NPCF (Arg0, Arg1, Arg2, Arg3))
                }
            }

            Method (NTCU, 0, Serialized)
            {
                Switch (ToInteger (TCNT))
                {
                    Case (0x20)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00F, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C010, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C011, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C012, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C013, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C014, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C015, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C016, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C017, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C018, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C019, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C01F, 0x85) // Device-Specific
                    }
                    Case (0x18)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00F, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C010, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C011, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C012, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C013, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C014, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C015, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C016, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C017, 0x85) // Device-Specific
                    }
                    Case (0x14)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00F, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C010, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C011, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C012, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C013, 0x85) // Device-Specific
                    }
                    Case (0x12)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00F, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C010, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C011, 0x85) // Device-Specific
                    }
                    Case (0x10)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00E, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00F, 0x85) // Device-Specific
                    }
                    Case (0x0E)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00C, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00D, 0x85) // Device-Specific
                    }
                    Case (0x0C)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00A, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C00B, 0x85) // Device-Specific
                    }
                    Case (0x0A)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C008, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C009, 0x85) // Device-Specific
                    }
                    Case (0x08)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C007, 0x85) // Device-Specific
                    }
                    Case (0x07)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C006, 0x85) // Device-Specific
                    }
                    Case (0x06)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C005, 0x85) // Device-Specific
                    }
                    Case (0x05)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C004, 0x85) // Device-Specific
                    }
                    Case (0x04)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C003, 0x85) // Device-Specific
                    }
                    Case (0x03)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C002, 0x85) // Device-Specific
                    }
                    Case (0x02)
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                        Notify (\_SB.PLTF.C001, 0x85) // Device-Specific
                    }
                    Default
                    {
                        Notify (\_SB.PLTF.C000, 0x85) // Device-Specific
                    }

                }
            }

            Method (NPCF, 4, Serialized)
            {
                Debug = "------- NVPCF DSM --------"
                If ((ToInteger (Arg1) != 0x0200))
                {
                    Return (0x80000001)
                }

                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Debug = "   NVPCF sub-func#0"
                        Name (BUFF, Buffer (0x04)
                        {
                             0xBF, 0x06, 0x00, 0x00                           // ....
                        })
                        Local1 = DerefOf (BUFF [One])
                        BUFF [One] = (Local1 | One)
                        Return (BUFF) /* \_SB_.NPCF.NPCF.BUFF */
                    }
                    Case (One)
                    {
                        Debug = "   NVPCF sub-func#1"
                        Return (Buffer (0x0E)
                        {
                            /* 0000 */  0x20, 0x03, 0x01, 0x01, 0x25, 0x04, 0x05, 0x01,  //  ...%...
                            /* 0008 */  0x01, 0x03, 0x00, 0x00, 0x00, 0xA8               // ......
                        })
                    }
                    Case (0x02)
                    {
                        Debug = "   NVPCF sub-func#2"
                        Name (PBD2, Buffer (0x31)
                        {
                             0x00                                             // .
                        })
                        CreateByteField (PBD2, Zero, PTV2)
                        CreateByteField (PBD2, One, PHB2)
                        CreateByteField (PBD2, 0x02, GSB2)
                        CreateByteField (PBD2, 0x03, CTB2)
                        CreateByteField (PBD2, 0x04, NCE2)
                        PTV2 = 0x25
                        PHB2 = 0x05
                        GSB2 = 0x10
                        CTB2 = 0x1C
                        NCE2 = One
                        CreateWordField (PBD2, 0x05, TGPA)
                        CreateWordField (PBD2, 0x07, TGPD)
                        CreateByteField (PBD2, 0x15, PC01)
                        CreateByteField (PBD2, 0x16, PC02)
                        CreateWordField (PBD2, 0x19, TPPA)
                        CreateWordField (PBD2, 0x1B, TPPD)
                        CreateWordField (PBD2, 0x1D, MAGA)
                        CreateWordField (PBD2, 0x1F, MAGD)
                        CreateWordField (PBD2, 0x21, MIGA)
                        CreateWordField (PBD2, 0x23, MIGD)
                        CreateDWordField (PBD2, 0x25, DROP)
                        CreateDWordField (PBD2, 0x29, LTBC)
                        CreateDWordField (PBD2, 0x2D, STBC)
                        CreateField (Arg3, 0x28, 0x02, NIGS)
                        CreateByteField (Arg3, 0x15, IORC)
                        CreateField (Arg3, 0xB0, One, PWCS)
                        CreateField (Arg3, 0xB1, One, PWTS)
                        CreateField (Arg3, 0xB2, One, CGPS)
                        If ((ToInteger (NIGS) == Zero))
                        {
                            TGPA = ACBT /* \_SB_.NPCF.ACBT */
                            TGPD = DCBT /* \_SB_.NPCF.DCBT */
                            PC01 = Zero
                            PC02 = (DBAC | (DBDC << One))
                            TPPA = ATPP /* \_SB_.NPCF.ATPP */
                            TPPD = DTPP /* \_SB_.NPCF.DTPP */
                            MAGA = AMAT /* \_SB_.NPCF.AMAT */
                            MIGA = AMIT /* \_SB_.NPCF.AMIT */
                            DROP = DROS /* \_SB_.NPCF.DROS */
                        }

                        If ((ToInteger (NIGS) == One))
                        {
                            If ((ToInteger (PWCS) == One)){}
                            Else
                            {
                            }

                            If ((ToInteger (PWTS) == One)){}
                            Else
                            {
                            }

                            If ((ToInteger (CGPS) == One)){}
                            Else
                            {
                            }

                            TGPA = Zero
                            TGPD = Zero
                            PC01 = Zero
                            PC02 = Zero
                            TPPA = Zero
                            TPPD = Zero
                            MAGA = Zero
                            MIGA = Zero
                            MAGD = Zero
                            MIGD = Zero
                        }

                        Return (PBD2) /* \_SB_.NPCF.NPCF.PBD2 */
                    }
                    Case (0x03)
                    {
                        Debug = "   NVPCF sub-func#3"
                        If (((\_SB.NPCF.WM2M & One) == One))
                        {
                            Return (Buffer (0x1E)
                            {
                                /* 0000 */  0x11, 0x04, 0x0D, 0x02, 0x00, 0xFF, 0x00, 0x3B,  // .......;
                                /* 0008 */  0x44, 0x44, 0x46, 0x46, 0x48, 0x48, 0x4A, 0x4A,  // DDFFHHJJ
                                /* 0010 */  0x5F, 0x05, 0xFF, 0x00, 0x37, 0x41, 0x41, 0x43,  // _...7AAC
                                /* 0018 */  0x43, 0x45, 0x45, 0x47, 0x47, 0x57               // CEEGGW
                            })
                        }
                    }
                    Case (0x04)
                    {
                        Debug = "   NVPCF sub-func#4"
                        If (((\_SB.NPCF.WM2M & One) == One))
                        {
                            Return (Buffer (0x32)
                            {
                                /* 0000 */  0x11, 0x04, 0x2E, 0x01, 0x05, 0x00, 0x01, 0x02,  // ........
                                /* 0008 */  0x03, 0x04, 0x03, 0x00, 0x01, 0x02, 0x00, 0x00,  // ........
                                /* 0010 */  0x00, 0x01, 0x02, 0x03, 0x00, 0x00, 0x00, 0x01,  // ........
                                /* 0018 */  0x02, 0x03, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03,  // ........
                                /* 0020 */  0x01, 0x01, 0x01, 0x01, 0x02, 0x03, 0x02, 0x02,  // ........
                                /* 0028 */  0x02, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x03,  // ........
                                /* 0030 */  0x03, 0x03                                       // ..
                            })
                        }
                    }
                    Case (0x05)
                    {
                        Debug = "   NVPCF sub-func#5"
                        Name (PBD5, Buffer (0x28)
                        {
                             0x00                                             // .
                        })
                        CreateByteField (PBD5, Zero, PTV5)
                        CreateByteField (PBD5, One, PHB5)
                        CreateByteField (PBD5, 0x02, TEB5)
                        CreateByteField (PBD5, 0x03, NTE5)
                        PTV5 = 0x11
                        PHB5 = 0x04
                        TEB5 = 0x24
                        NTE5 = One
                        CreateDWordField (PBD5, 0x04, F5O0)
                        CreateDWordField (PBD5, 0x08, F5O1)
                        CreateDWordField (PBD5, 0x0C, F5O2)
                        CreateDWordField (PBD5, 0x10, F5O3)
                        CreateDWordField (PBD5, 0x14, F5O4)
                        CreateDWordField (PBD5, 0x18, F5O5)
                        CreateDWordField (PBD5, 0x1C, F5O6)
                        CreateDWordField (PBD5, 0x20, F5O7)
                        CreateDWordField (PBD5, 0x24, F5O8)
                        CreateField (Arg3, 0x20, 0x03, INC5)
                        CreateDWordField (Arg3, 0x08, F5P1)
                        CreateDWordField (Arg3, 0x0C, F5P2)
                        Switch (ToInteger (INC5))
                        {
                            Case (Zero)
                            {
                                F5O0 = WM2M /* \_SB_.NPCF.WM2M */
                                F5O1 = Zero
                                F5O2 = Zero
                                F5O3 = Zero
                            }
                            Case (One)
                            {
                                F5O0 = 0x0C
                                F5O1 = Zero
                                F5O2 = Zero
                                F5O3 = Zero
                            }
                            Case (0x02)
                            {
                                F5O0 = Zero
                                Local0 = \_SB.PCI0.SBRG.EC0.CTMP /* External reference */
                                Local1 = \_SB.PCI0.SBRG.EC0.VRTT /* External reference */
                                Local0 = MAVT (Local0)
                                Local2 = FCPI (Local0)
                                F5O1 = ((Local0 << 0x10) | (Local2 & 0xFF))
                                Local2 = FGPI (Local1)
                                F5O2 = ((Local1 << 0x10) | (Local2 & 0xFF))
                                F5O3 = Zero
                                F5O4 = Zero
                                F5O5 = Zero
                                F5O6 = Zero
                                F5O7 = Zero
                                F5O8 = Zero
                            }
                            Case (0x03)
                            {
                                CUSL = (F5P1 & 0xFF)
                            }
                            Case (0x04)
                            {
                                CUCT = F5P2 /* \_SB_.NPCF.NPCF.F5P2 */
                            }
                            Default
                            {
                                Return (0x80000002)
                            }

                        }

                        Return (PBD5) /* \_SB_.NPCF.NPCF.PBD5 */
                    }
                    Case (0x07)
                    {
                        Debug = "   NVPCF sub-func#7"
                        CreateDWordField (Arg3, 0x05, AMAX)
                        CreateDWordField (Arg3, 0x09, ARAT)
                        CreateDWordField (Arg3, 0x0D, DMAX)
                        CreateDWordField (Arg3, 0x11, DRAT)
                        CreateDWordField (Arg3, 0x15, TGPM)
                        Return (Zero)
                    }
                    Case (0x08)
                    {
                        Debug = "   NVPCF sub-func#8"
                        Return (Buffer (0x6A)
                        {
                            /* 0000 */  0x10, 0x04, 0x11, 0x06, 0x64, 0xD4, 0x17, 0x00,  // ....d...
                            /* 0008 */  0x00, 0xB8, 0x88, 0x00, 0x00, 0xF0, 0x55, 0x00,  // ......U.
                            /* 0010 */  0x00, 0xE8, 0x80, 0x00, 0x00, 0x50, 0xD4, 0x17,  // .....P..
                            /* 0018 */  0x00, 0x00, 0xB8, 0x88, 0x00, 0x00, 0x38, 0x4A,  // ......8J
                            /* 0020 */  0x00, 0x00, 0x48, 0x71, 0x00, 0x00, 0x3C, 0xD4,  // ..Hq..<.
                            /* 0028 */  0x17, 0x00, 0x00, 0xB8, 0x88, 0x00, 0x00, 0x50,  // .......P
                            /* 0030 */  0x46, 0x00, 0x00, 0x60, 0x6D, 0x00, 0x00, 0x2E,  // F..`m...
                            /* 0038 */  0x7C, 0x15, 0x00, 0x00, 0xB8, 0x88, 0x00, 0x00,  // |.......
                            /* 0040 */  0x98, 0x3A, 0x00, 0x00, 0xD8, 0x59, 0x00, 0x00,  // .:...Y..
                            /* 0048 */  0x19, 0x7C, 0x15, 0x00, 0x00, 0xB8, 0x88, 0x00,  // .|......
                            /* 0050 */  0x00, 0x98, 0x3A, 0x00, 0x00, 0xF0, 0x55, 0x00,  // ..:...U.
                            /* 0058 */  0x00, 0x0A, 0x7C, 0x15, 0x00, 0x00, 0xB8, 0x88,  // ..|.....
                            /* 0060 */  0x00, 0x00, 0xB0, 0x36, 0x00, 0x00, 0x08, 0x52,  // ...6...R
                            /* 0068 */  0x00, 0x00                                       // ..
                        })
                    }
                    Case (0x09)
                    {
                        Debug = "   NVPCF sub-func#9"
                        CreateDWordField (Arg3, 0x03, CPTD)
                        Local0 = CPTD /* \_SB_.NPCF.NPCF.CPTD */
                        Divide (Local0, 0x03E8, Local1, Local2)
                        \_SB.PCI0.SBRG.EC0.NDF9 = Local2
                        Debug = Concatenate (Concatenate ("NVPCF F09 set CPU power limit = ", Local2), " hW")
                        Return (Zero)
                    }
                    Case (0x0A)
                    {
                        Debug = "   NVPCF sub-func#10"
                        Name (PBDA, Buffer (0x08)
                        {
                             0x00                                             // .
                        })
                        CreateByteField (PBDA, Zero, DTTV)
                        CreateByteField (PBDA, One, DTSH)
                        CreateByteField (PBDA, 0x02, DTSE)
                        CreateByteField (PBDA, 0x03, DTTE)
                        CreateDWordField (PBDA, 0x04, DTTL)
                        DTTV = 0x10
                        DTSH = 0x04
                        DTSE = 0x04
                        DTTE = One
                        DTTL = TPPL /* \_SB_.NPCF.TPPL */
                        Return (PBDA) /* \_SB_.NPCF.NPCF.PBDA */
                    }

                }

                Return (0x80000002)
            }
        }
    }
}

