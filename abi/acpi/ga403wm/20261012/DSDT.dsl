/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260930 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of DSDT.aml
 *
 * Original Table Header:
 *     Signature        "DSDT"
 *     Length           0x000103D1 (66513)
 *     Revision         0x02
 *     Checksum         0x2F
 *     OEM ID           "_ASUS_"
 *     OEM Table ID     "Notebook"
 *     OEM Revision     0x01072009 (17244169)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20230331 (539165489)
 */
DefinitionBlock ("", "DSDT", 2, "_ASUS_", "Notebook", 0x01072009)
{
    External (_SB_.ALIB, MethodObj)    // 2 Arguments
    External (_SB_.APTS, MethodObj)    // 1 Arguments
    External (_SB_.ATKD.MAKY, UnknownObj)
    External (_SB_.ATKD.WMNB.M009, MethodObj)    // 1 Arguments
    External (_SB_.AWAK, MethodObj)    // 1 Arguments
    External (_SB_.GSRV, MethodObj)    // 1 Arguments
    External (_SB_.LID0, DeviceObj)
    External (_SB_.NPCF, DeviceObj)
    External (_SB_.NPCF.ACBT, IntObj)
    External (_SB_.NPCF.AMAT, IntObj)
    External (_SB_.NPCF.AMIT, IntObj)
    External (_SB_.NPCF.ATPP, IntObj)
    External (_SB_.NPCF.DBAC, IntObj)
    External (_SB_.NPCF.DBDC, IntObj)
    External (_SB_.NPCF.DTPP, IntObj)
    External (_SB_.NPCF.TPPL, IntObj)
    External (_SB_.NPCF.WM2M, IntObj)
    External (_SB_.PCI0.GFX0.VGA_.LCD_, DeviceObj)
    External (_SB_.PCI0.GPP9.PEGP, DeviceObj)
    External (_SB_.PCI0.GPP9.PEGP.EDP1, DeviceObj)
    External (_SB_.PCI0.GPP9.PEGP.NLIM, IntObj)
    External (_SB_.PCI0.GPP9.PEGP.TGPU, IntObj)
    External (_SB_.PCI0.GPPA.VGA_.LCD_, DeviceObj)
    External (_SB_.PCI0.SBRG.EC0_.ACIN, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.BHCH, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.BHPE, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.CTMP, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.DBEA, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.DBEB, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.ECOK, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.LIDS, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MBCP, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MBCT, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MBDV, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MBVT, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MDCP, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.MUT0, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.NOAC, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.RCAP, UnknownObj)
    External (_SB_.PCI0.SBRG.EC0_.SKEY, MethodObj)    // 1 Arguments
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
    External (_SB_.U4PC, IntObj)
    External (_SB_.UBTC, DeviceObj)
    External (_SB_.UBTC.QUCM, MethodObj)    // 0 Arguments
    External (AFN4, MethodObj)    // 1 Arguments
    External (AFN7, MethodObj)    // 1 Arguments
    External (CRBI, UnknownObj)
    External (M017, MethodObj)    // 6 Arguments
    External (M019, MethodObj)    // 4 Arguments
    External (M020, MethodObj)    // 5 Arguments
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
    External (M404, BuffObj)
    External (M408, MutexObj)
    External (M414, FieldUnitObj)
    External (M428, MethodObj)    // 6 Arguments
    External (M444, FieldUnitObj)
    External (M449, FieldUnitObj)
    External (M453, FieldUnitObj)
    External (M454, FieldUnitObj)
    External (M455, FieldUnitObj)
    External (M456, FieldUnitObj)
    External (M457, FieldUnitObj)
    External (M460, MethodObj)    // 7 Arguments
    External (M4C0, FieldUnitObj)
    External (M4F0, FieldUnitObj)
    External (M601, MethodObj)    // 6 Arguments
    External (M602, MethodObj)    // 3 Arguments
    External (M610, FieldUnitObj)
    External (M620, FieldUnitObj)
    External (M631, FieldUnitObj)
    External (M652, FieldUnitObj)
    External (MPTS, MethodObj)    // 1 Arguments
    External (MWAK, MethodObj)    // 1 Arguments

    Name (PEBL, 0x10000000)
    Name (NBTS, 0x5000)
    Name (CPVD, One)
    Name (SMBB, 0x0B20)
    Name (SMBL, 0x20)
    Name (SMB0, 0x0B00)
    Name (SMBM, 0x10)
    Name (PMBS, 0x0800)
    Name (PMLN, 0xA0)
    Name (SMIO, 0xB2)
    Name (APCB, 0xFEC00000)
    Name (APCL, 0x1000)
    Name (HPTB, 0xFED00000)
    Name (WDTB, Zero)
    Name (WDTL, Zero)
    Name (GIOB, 0xFED81500)
    Name (IOMB, 0xFED80D00)
    Name (SSMB, 0xFED80200)
    Name (UTDB, Zero)
    Name (PWEN, 0x09)
    Name (REST, 0x28)
    Name (PWOK, 0x9A)
    Name (IOBS, Zero)
    Name (IOB2, Zero)
    Name (ASSB, Zero)
    Name (AOTB, Zero)
    Name (AAXB, Zero)
    Name (PEHP, One)
    Name (SHPC, One)
    Name (PEPM, One)
    Name (PECS, One)
    Name (ITKE, Zero)
    Name (PEBS, 0xE0000000)
    Name (PELN, 0x10000000)
    Name (CSMI, 0x61)
    Name (SMIA, 0xB2)
    Name (OFST, 0x35)
    Name (TRST, 0x02)
    Name (TCMF, Zero)
    Name (TMF1, Zero)
    Name (TTPF, Zero)
    Name (DTPT, Zero)
    Name (TTDP, One)
    Name (TPMB, 0xFFFFFFFF)
    Name (TPBS, 0x1000)
    Name (TPMC, 0xFFFFFFFF)
    Name (TPCS, 0x1000)
    Name (TPMM, 0xFED40000)
    Name (FTPM, 0xFFFFFFFF)
    Name (PPIM, 0x6F678F18)
    Name (PPIL, 0x1C)
    Name (TPMF, One)
    Name (PPIV, One)
    Name (AMDT, 0x02)
    Name (MBEC, Zero)
    Name (NBTP, 0xFEC00000)
    Name (PEER, Zero)
    Name (OSFG, Zero)
    Name (EXSI, 0xAB)
    Method (_PIC, 1, NotSerialized)  // _PIC: Interrupt Model
    {
        If (Arg0)
        {
            \_SB.DSPI ()
            \_SB.PCI0.NAPE ()
        }

        PXXX (Arg0)
    }

    OperationRegion (DEB0, SystemIO, 0x80, 0x04)
    Field (DEB0, DWordAcc, NoLock, Preserve)
    {
        DBG8,   32
    }

    Name (PICM, Zero)
    Method (PXXX, 1, NotSerialized)
    {
        If (Arg0)
        {
            DBGX = 0xAA
        }
        Else
        {
            DBGX = 0xAC
        }

        PICM = Arg0
    }

    Name (OSVR, Ones)
    Method (OSFL, 0, NotSerialized)
    {
        If ((OSVR != Ones))
        {
            Return (OSVR) /* \OSVR */
        }

        If ((PICM == Zero))
        {
            DBGX = 0xAC
        }

        OSVR = 0x03
        If (CondRefOf (\_OSI))
        {
            If (_OSI ("Windows 2001"))
            {
                OSVR = 0x04
            }

            If (_OSI ("Windows 2001.1"))
            {
                OSVR = 0x05
            }

            If (_OSI ("FreeBSD"))
            {
                OSVR = 0x06
            }

            If (_OSI ("HP-UX"))
            {
                OSVR = 0x07
            }

            If (_OSI ("OpenVMS"))
            {
                OSVR = 0x08
            }

            If (_OSI ("Windows 2001 SP1"))
            {
                OSVR = 0x09
            }

            If (_OSI ("Windows 2001 SP2"))
            {
                OSVR = 0x0A
            }

            If (_OSI ("Windows 2001 SP3"))
            {
                OSVR = 0x0B
            }

            If (_OSI ("Windows 2006"))
            {
                OSVR = 0x0C
            }

            If (_OSI ("Windows 2006 SP1"))
            {
                OSVR = 0x0D
            }

            If (_OSI ("Windows 2009"))
            {
                OSVR = 0x0E
            }

            If (_OSI ("Windows 2012"))
            {
                OSVR = 0x0F
            }

            If (_OSI ("Windows 2013"))
            {
                OSVR = 0x10
            }
        }
        Else
        {
            If (MCTH (_OS, "Microsoft Windows NT"))
            {
                OSVR = Zero
            }

            If (MCTH (_OS, "Microsoft Windows"))
            {
                OSVR = One
            }

            If (MCTH (_OS, "Microsoft WindowsME: Millennium Edition"))
            {
                OSVR = 0x02
            }

            If (MCTH (_OS, "Linux"))
            {
                OSVR = 0x03
            }

            If (MCTH (_OS, "FreeBSD"))
            {
                OSVR = 0x06
            }

            If (MCTH (_OS, "HP-UX"))
            {
                OSVR = 0x07
            }

            If (MCTH (_OS, "OpenVMS"))
            {
                OSVR = 0x08
            }
        }

        Return (OSVR) /* \OSVR */
    }

    Method (MCTH, 2, NotSerialized)
    {
        If ((SizeOf (Arg0) < SizeOf (Arg1)))
        {
            Return (Zero)
        }

        Local0 = (SizeOf (Arg0) + One)
        Name (BUF0, Buffer (Local0){})
        Name (BUF1, Buffer (Local0){})
        BUF0 = Arg0
        BUF1 = Arg1
        While (Local0)
        {
            Local0--
            If ((DerefOf (BUF0 [Local0]) != DerefOf (BUF1 [Local0]
                )))
            {
                Return (Zero)
            }
        }

        Return (One)
    }

    Name (PRWP, Package (0x02)
    {
        Zero, 
        Zero
    })
    Method (GPRW, 2, NotSerialized)
    {
        PRWP [Zero] = Arg0
        Local0 = (SS1 << One)
        Local0 |= (SS2 << 0x02)
        Local0 |= (SS3 << 0x03)
        Local0 |= (SS4 << 0x04)
        If (((One << Arg1) & Local0))
        {
            PRWP [One] = Arg1
        }
        Else
        {
            Local0 >>= One
            If (((OSFL () == One) || (OSFL () == 0x02)))
            {
                FindSetLeftBit (Local0, PRWP [One])
            }
            Else
            {
                FindSetRightBit (Local0, PRWP [One])
            }
        }

        If ((CNSB == One))
        {
            If ((Arg1 <= 0x03))
            {
                PRWP [One] = Zero
            }
        }

        Return (PRWP) /* \PRWP */
    }

    Name (WAKP, Package (0x02)
    {
        Zero, 
        Zero
    })
    Method (UPWP, 1, NotSerialized)
    {
        If (DerefOf (WAKP [Zero]))
        {
            WAKP [One] = Zero
        }
        Else
        {
            WAKP [One] = Arg0
        }
    }

    OperationRegion (DEB3, SystemIO, 0x80, One)
    Field (DEB3, ByteAcc, NoLock, Preserve)
    {
        DBGX,   8
    }

    OperationRegion (DEB1, SystemIO, 0x90, 0x02)
    Field (DEB1, WordAcc, NoLock, Preserve)
    {
        DBG9,   16
    }

    Name (SS1, Zero)
    Name (SS2, Zero)
    Name (SS3, Zero)
    Name (SS4, One)
    Name (IOST, 0xFFFF)
    Name (TOPM, 0x00000000)
    Name (ROMS, 0xFFE00000)
    Name (VGAF, One)
    Scope (_SB)
    {
        Name (PRSA, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {4,5,6,10,11,14,15}
        })
        Alias (PRSA, PRSB)
        Alias (PRSA, PRSC)
        Alias (PRSA, PRSD)
        Alias (PRSA, PRSE)
        Alias (PRSA, PRSF)
        Alias (PRSA, PRSG)
        Alias (PRSA, PRSH)
        Name (PD01, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKD, , 
                Zero
            }
        })
        Name (AR01, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x18
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x19
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x1A
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x1B
            }
        })
        Name (PD41, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKH, , 
                Zero
            }
        })
        Name (AR41, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x1C
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x1D
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x1E
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x1F
            }
        })
        Name (PD81, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKD, , 
                Zero
            }
        })
        Name (AR81, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x20
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x21
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x22
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x23
            }
        })
        Name (PDC1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKH, , 
                Zero
            }
        })
        Name (ARC1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x24
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x25
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x26
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x27
            }
        })
        Name (PDC5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKD, , 
                Zero
            }
        })
        Name (ARC5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x28
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x29
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x2A
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x2B
            }
        })
        Name (PDC9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKH, , 
                Zero
            }
        })
        Name (ARC9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x2C
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x2D
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x2E
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x2F
            }
        })
        Name (PDCD, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKF, , 
                Zero
            }
        })
        Name (ARCD, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x2E
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x2F
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x2C
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x2D
            }
        })
        Name (PDD1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKB, , 
                Zero
            }
        })
        Name (ARD1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x2A
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x2B
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x28
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x29
            }
        })
        Name (PDD5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKF, , 
                Zero
            }
        })
        Name (ARD5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x26
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x27
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x24
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x25
            }
        })
        Name (PDD9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKB, , 
                Zero
            }
        })
        Name (ARD9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x22
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x23
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x20
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x21
            }
        })
        Name (PDDD, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKF, , 
                Zero
            }
        })
        Name (ARDD, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x1E
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x1F
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x1C
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x1D
            }
        })
        Name (PDE1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKB, , 
                Zero
            }
        })
        Name (ARE1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x1A
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x1B
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x18
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x19
            }
        })
        Name (PDE5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKA, , 
                Zero
            }
        })
        Name (ARE5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x19
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x1A
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x1B
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x18
            }
        })
        Name (PDE9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKG, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKE, , 
                Zero
            }
        })
        Name (ARE9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x1D
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x1E
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x1F
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x1C
            }
        })
        Name (PDED, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKA, , 
                Zero
            }
        })
        Name (ARED, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x21
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x22
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x23
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x20
            }
        })
        Name (PDF1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKG, , 
                Zero
            }
        })
        Name (ARF1, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x27
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x24
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x25
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x26
            }
        })
        Name (PDF5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKD, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKC, , 
                Zero
            }
        })
        Name (ARF5, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x2B
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x28
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x29
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x2A
            }
        })
        Name (PDF9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                LNKH, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                LNKE, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                LNKF, , 
                Zero
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                LNKG, , 
                Zero
            }
        })
        Name (ARF9, Package (0x04)
        {
            Package (0x04)
            {
                0xFFFF, 
                Zero, 
                Zero, 
                0x2F
            }, 

            Package (0x04)
            {
                0xFFFF, 
                One, 
                Zero, 
                0x2C
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x02, 
                Zero, 
                0x2D
            }, 

            Package (0x04)
            {
                0xFFFF, 
                0x03, 
                Zero, 
                0x2E
            }
        })
        Name (PD00, Package (0x04)
        {
            Package (0x04)
            {
                0x0014FFFF, 
                Zero, 
                LNKA, , 
                Zero
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                One, 
                LNKB, , 
                Zero
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                0x02, 
                LNKC, , 
                Zero
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                0x03, 
                LNKD, , 
                Zero
            }
        })
        Name (ARXX, Package (0x04)
        {
            Package (0x04)
            {
                0x0014FFFF, 
                Zero, 
                Zero, 
                0x10
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                One, 
                Zero, 
                0x11
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                0x02, 
                Zero, 
                0x12
            }, 

            Package (0x04)
            {
                0x0014FFFF, 
                0x03, 
                Zero, 
                0x13
            }
        })
    }

    Scope (_SB)
    {
        Device (PCI0)
        {
            Name (_HID, EisaId ("PNP0A08") /* PCI Express Bus */)  // _HID: Hardware ID
            Name (_CID, EisaId ("PNP0A03") /* PCI Bus */)  // _CID: Compatible ID
            Name (_ADR, Zero)  // _ADR: Address
            Method (^BN00, 0, NotSerialized)
            {
                Return (Zero)
            }

            Method (_BBN, 0, NotSerialized)  // _BBN: BIOS Bus Number
            {
                Return (BN00 ())
            }

            Name (_UID, Zero)  // _UID: Unique ID
            Method (_PRT, 0, NotSerialized)  // _PRT: PCI Routing Table
            {
                If (PICM)
                {
                    Return (AR00) /* \_SB_.PCI0.AR00 */
                }

                Return (PD00) /* \_SB_.PD00 */
            }

            Method (NPTS, 1, NotSerialized)
            {
                APTS (Arg0)
            }

            Method (NWAK, 1, NotSerialized)
            {
                AWAK (Arg0)
            }

            Name (CPRB, One)
            Name (LVGA, 0x01)
            Name (STAV, 0x0F)
            Name (BRB, 0x0000)
            Name (BRL, 0x0100)
            Name (IOB, 0x1000)
            Name (IOL, 0xF000)
            Name (MBB, 0x80000000)
            Name (MBL, 0x60000000)
            Name (MAB, 0x0000000880000000)
            Name (MAL, 0x0000007F80000000)
            Name (MAM, 0x00000087FFFFFFFF)
            Name (NRSB, 0x6F666000)
            OperationRegion (NRSV, SystemMemory, NRSB, 0x1000)
            Field (NRSV, AnyAcc, NoLock, Preserve)
            {
                RSTE,   32, 
                Offset (0x08), 
                Offset (0x10), 
                RSB0,   32, 
                Offset (0x18), 
                RSS0,   32, 
                Offset (0x20), 
                RSB1,   32, 
                Offset (0x28), 
                RSS1,   32, 
                Offset (0x30), 
                RSB2,   32, 
                Offset (0x38), 
                RSS2,   32, 
                Offset (0x40), 
                RSB3,   32, 
                Offset (0x48), 
                RSS3,   32, 
                Offset (0x50)
            }

            Name (CRS1, ResourceTemplate ()
            {
                WordBusNumber (ResourceProducer, MinFixed, MaxFixed, PosDecode,
                    0x0000,             // Granularity
                    0x0000,             // Range Minimum
                    0x007F,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0080,             // Length
                    ,, _Y00)
                IO (Decode16,
                    0x0CF8,             // Range Minimum
                    0x0CF8,             // Range Maximum
                    0x01,               // Alignment
                    0x08,               // Length
                    )
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x0000,             // Range Minimum
                    0x03AF,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x03B0,             // Length
                    ,, , TypeStatic, DenseTranslation)
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x03E0,             // Range Minimum
                    0x0CF7,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0918,             // Length
                    ,, , TypeStatic, DenseTranslation)
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x0000,             // Range Minimum
                    0x0000,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0000,             // Length
                    ,, _Y02, TypeStatic, DenseTranslation)
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x0D00,             // Range Minimum
                    0x0FFF,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0300,             // Length
                    ,, _Y01, TypeStatic, DenseTranslation)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x00000000,         // Range Minimum
                    0x00000000,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x00000000,         // Length
                    ,, _Y03, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, NonCacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x000C0000,         // Range Minimum
                    0x000DFFFF,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x00020000,         // Length
                    ,, , AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x02000000,         // Range Minimum
                    0xFFDFFFFF,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0xFDE00000,         // Length
                    ,, _Y04, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x02000000,         // Range Minimum
                    0xFFDFFFFF,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0xFDE00000,         // Length
                    ,, _Y05, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x00000000,         // Range Minimum
                    0x00000000,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x00000000,         // Length
                    ,, _Y06, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x00000000,         // Range Minimum
                    0x00000000,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x00000000,         // Length
                    ,, _Y07, AddressRangeMemory, TypeStatic)
                QWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x0000000000000000, // Granularity
                    0x0000000000000000, // Range Minimum
                    0x0000000000000000, // Range Maximum
                    0x0000000000000000, // Translation Offset
                    0x0000000000000000, // Length
                    ,, _Y08, AddressRangeMemory, TypeStatic)
            })
            Name (CRS2, ResourceTemplate ()
            {
                WordBusNumber (ResourceProducer, MinFixed, MaxFixed, PosDecode,
                    0x0000,             // Granularity
                    0x0080,             // Range Minimum
                    0x00FF,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0080,             // Length
                    ,, _Y09)
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x0000,             // Range Minimum
                    0x0000,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0000,             // Length
                    ,, _Y0B, TypeStatic, DenseTranslation)
                WordIO (ResourceProducer, MinFixed, MaxFixed, PosDecode, EntireRange,
                    0x0000,             // Granularity
                    0x0000,             // Range Minimum
                    0x0000,             // Range Maximum
                    0x0000,             // Translation Offset
                    0x0000,             // Length
                    ,, _Y0A, TypeStatic, DenseTranslation)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x00000000,         // Range Minimum
                    0x00000000,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x00000000,         // Length
                    ,, _Y0C, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x80000000,         // Range Minimum
                    0xFFFFFFFF,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x80000000,         // Length
                    ,, _Y0D, AddressRangeMemory, TypeStatic)
                DWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x00000000,         // Granularity
                    0x80000000,         // Range Minimum
                    0xFFFFFFFF,         // Range Maximum
                    0x00000000,         // Translation Offset
                    0x80000000,         // Length
                    ,, _Y0E, AddressRangeMemory, TypeStatic)
                QWordMemory (ResourceProducer, PosDecode, MinFixed, MaxFixed, Cacheable, ReadWrite,
                    0x0000000000000000, // Granularity
                    0x0000000000000000, // Range Minimum
                    0x0000000000000000, // Range Maximum
                    0x0000000000000000, // Translation Offset
                    0x0000000000000000, // Length
                    ,, _Y0F, AddressRangeMemory, TypeStatic)
            })
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (STAV) /* \_SB_.PCI0.STAV */
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                DBG8 = 0x25
                If (CPRB)
                {
                    CreateWordField (CRS1, \_SB.PCI0._Y00._MIN, MIN0)  // _MIN: Minimum Base Address
                    CreateWordField (CRS1, \_SB.PCI0._Y00._MAX, MAX0)  // _MAX: Maximum Base Address
                    CreateWordField (CRS1, \_SB.PCI0._Y00._LEN, LEN0)  // _LEN: Length
                    MIN0 = BRB /* \_SB_.PCI0.BRB_ */
                    LEN0 = BRL /* \_SB_.PCI0.BRL_ */
                    Local0 = LEN0 /* \_SB_.PCI0._CRS.LEN0 */
                    MAX0 = (MIN0 + Local0--)
                    CreateWordField (CRS1, \_SB.PCI0._Y01._MIN, MIN1)  // _MIN: Minimum Base Address
                    CreateWordField (CRS1, \_SB.PCI0._Y01._MAX, MAX1)  // _MAX: Maximum Base Address
                    CreateWordField (CRS1, \_SB.PCI0._Y01._LEN, LEN1)  // _LEN: Length
                    If ((IOB == 0x1000))
                    {
                        Local0 = IOL /* \_SB_.PCI0.IOL_ */
                        MAX1 = (IOB + Local0--)
                        Local0 = (MAX1 - MIN1) /* \_SB_.PCI0._CRS.MIN1 */
                        LEN1 = (Local0 + One)
                    }
                    Else
                    {
                        MIN1 = IOB /* \_SB_.PCI0.IOB_ */
                        LEN1 = IOL /* \_SB_.PCI0.IOL_ */
                        Local0 = LEN1 /* \_SB_.PCI0._CRS.LEN1 */
                        MAX1 = (MIN1 + Local0--)
                    }

                    If (((LVGA == One) || (LVGA == 0x55)))
                    {
                        If (VGAF)
                        {
                            CreateWordField (CRS1, \_SB.PCI0._Y02._MIN, IMN1)  // _MIN: Minimum Base Address
                            CreateWordField (CRS1, \_SB.PCI0._Y02._MAX, IMX1)  // _MAX: Maximum Base Address
                            CreateWordField (CRS1, \_SB.PCI0._Y02._LEN, ILN1)  // _LEN: Length
                            IMN1 = 0x03B0
                            IMX1 = 0x03DF
                            ILN1 = 0x30
                            CreateDWordField (CRS1, \_SB.PCI0._Y03._MIN, VMN1)  // _MIN: Minimum Base Address
                            CreateDWordField (CRS1, \_SB.PCI0._Y03._MAX, VMX1)  // _MAX: Maximum Base Address
                            CreateDWordField (CRS1, \_SB.PCI0._Y03._LEN, VLN1)  // _LEN: Length
                            VMN1 = 0x000A0000
                            VMX1 = 0x000BFFFF
                            VLN1 = 0x00020000
                            VGAF = Zero
                        }
                    }

                    CreateDWordField (CRS1, \_SB.PCI0._Y04._MIN, MIN3)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y04._MAX, MAX3)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y04._LEN, LEN3)  // _LEN: Length
                    CreateDWordField (CRS1, \_SB.PCI0._Y05._MIN, MIN7)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y05._MAX, MAX7)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y05._LEN, LEN7)  // _LEN: Length
                    CreateDWordField (CRS1, \_SB.PCI0._Y06._MIN, MIN9)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y06._MAX, MAX9)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y06._LEN, LEN9)  // _LEN: Length
                    CreateDWordField (CRS1, \_SB.PCI0._Y07._MIN, MINA)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y07._MAX, MAXA)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS1, \_SB.PCI0._Y07._LEN, LENA)  // _LEN: Length
                    Local7 = Zero
                    If ((NRSB != 0x00010000))
                    {
                        If ((RSTE == One))
                        {
                            Local7 = One
                            MIN3 = RSB0 /* \_SB_.PCI0.RSB0 */
                            LEN3 = RSS0 /* \_SB_.PCI0.RSS0 */
                            Local0 = (RSB0 + RSS0) /* \_SB_.PCI0.RSS0 */
                            If ((Local0 != Zero))
                            {
                                Local0 -= One
                            }

                            MAX3 = Local0
                            MIN7 = RSB1 /* \_SB_.PCI0.RSB1 */
                            LEN7 = RSS1 /* \_SB_.PCI0.RSS1 */
                            Local0 = (RSB1 + RSS1) /* \_SB_.PCI0.RSS1 */
                            If ((Local0 != Zero))
                            {
                                Local0 -= One
                            }

                            MAX7 = Local0
                            MIN9 = RSB2 /* \_SB_.PCI0.RSB2 */
                            LEN9 = RSS2 /* \_SB_.PCI0.RSS2 */
                            Local0 = (RSB2 + RSS2) /* \_SB_.PCI0.RSS2 */
                            If ((Local0 != Zero))
                            {
                                Local0 -= One
                            }

                            MAX9 = Local0
                            MINA = RSB3 /* \_SB_.PCI0.RSB3 */
                            LENA = RSS3 /* \_SB_.PCI0.RSS3 */
                            Local0 = (RSB3 + RSS3) /* \_SB_.PCI0.RSS3 */
                            If ((Local0 != Zero))
                            {
                                Local0 -= One
                            }

                            MAXA = Local0
                        }
                    }

                    If ((Local7 == Zero))
                    {
                        Local0 = (MBB + MBL) /* \_SB_.PCI0.MBL_ */
                        If ((Local0 < NBTP))
                        {
                            MIN3 = MBB /* \_SB_.PCI0.MBB_ */
                            LEN3 = MBL /* \_SB_.PCI0.MBL_ */
                            Local0 = LEN3 /* \_SB_.PCI0._CRS.LEN3 */
                            MAX3 = (MIN3 + Local0--)
                            MIN7 = Zero
                            MAX7 = Zero
                            LEN7 = Zero
                        }
                        Else
                        {
                            MIN3 = MBB /* \_SB_.PCI0.MBB_ */
                            LEN3 = (NBTP - MBB)
                            Local0 = LEN3 /* \_SB_.PCI0._CRS.LEN3 */
                            MAX3 = (MIN3 + Local0--)
                            If (((MBL - LEN3) < 0x00200000))
                            {
                                MIN7 = Zero
                                MAX7 = Zero
                                LEN7 = Zero
                            }
                            Else
                            {
                                MIN7 = 0xFEE00000
                                Local0 = (0xFEE00000 - NBTP)
                                LEN7 = (MBL - Local0)
                                LEN7 = (LEN7 - LEN3)
                                Local0 = LEN7 /* \_SB_.PCI0._CRS.LEN7 */
                                MAX7 = (MIN7 + Local0--)
                            }
                        }
                    }

                    If (MAL)
                    {
                        CreateQWordField (CRS1, \_SB.PCI0._Y08._MIN, MN8)  // _MIN: Minimum Base Address
                        CreateQWordField (CRS1, \_SB.PCI0._Y08._MAX, MX8)  // _MAX: Maximum Base Address
                        CreateQWordField (CRS1, \_SB.PCI0._Y08._LEN, LN8)  // _LEN: Length
                        MN8 = MAB /* \_SB_.PCI0.MAB_ */
                        LN8 = MAL /* \_SB_.PCI0.MAL_ */
                        MX8 = MAM /* \_SB_.PCI0.MAM_ */
                    }

                    DBG8 = 0x24
                    Return (CRS1) /* \_SB_.PCI0.CRS1 */
                }
                Else
                {
                    CreateWordField (CRS2, \_SB.PCI0._Y09._MIN, MIN2)  // _MIN: Minimum Base Address
                    CreateWordField (CRS2, \_SB.PCI0._Y09._MAX, MAX2)  // _MAX: Maximum Base Address
                    CreateWordField (CRS2, \_SB.PCI0._Y09._LEN, LEN2)  // _LEN: Length
                    MIN2 = BRB /* \_SB_.PCI0.BRB_ */
                    LEN2 = BRL /* \_SB_.PCI0.BRL_ */
                    Local1 = LEN2 /* \_SB_.PCI0._CRS.LEN2 */
                    MAX2 = (MIN2 + Local1--)
                    CreateWordField (CRS2, \_SB.PCI0._Y0A._MIN, MIN4)  // _MIN: Minimum Base Address
                    CreateWordField (CRS2, \_SB.PCI0._Y0A._MAX, MAX4)  // _MAX: Maximum Base Address
                    CreateWordField (CRS2, \_SB.PCI0._Y0A._LEN, LEN4)  // _LEN: Length
                    MIN4 = IOB /* \_SB_.PCI0.IOB_ */
                    LEN4 = IOL /* \_SB_.PCI0.IOL_ */
                    Local1 = LEN4 /* \_SB_.PCI0._CRS.LEN4 */
                    MAX4 = (MIN4 + Local1--)
                    If (LVGA)
                    {
                        CreateWordField (CRS2, \_SB.PCI0._Y0B._MIN, IMN2)  // _MIN: Minimum Base Address
                        CreateWordField (CRS2, \_SB.PCI0._Y0B._MAX, IMX2)  // _MAX: Maximum Base Address
                        CreateWordField (CRS2, \_SB.PCI0._Y0B._LEN, ILN2)  // _LEN: Length
                        IMN2 = 0x03B0
                        IMX2 = 0x03DF
                        ILN2 = 0x30
                        CreateDWordField (CRS2, \_SB.PCI0._Y0C._MIN, VMN2)  // _MIN: Minimum Base Address
                        CreateDWordField (CRS2, \_SB.PCI0._Y0C._MAX, VMX2)  // _MAX: Maximum Base Address
                        CreateDWordField (CRS2, \_SB.PCI0._Y0C._LEN, VLN2)  // _LEN: Length
                        VMN2 = 0x000A0000
                        VMX2 = 0x000BFFFF
                        VLN2 = 0x00020000
                    }

                    CreateDWordField (CRS2, \_SB.PCI0._Y0D._MIN, MIN5)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS2, \_SB.PCI0._Y0D._MAX, MAX5)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS2, \_SB.PCI0._Y0D._LEN, LEN5)  // _LEN: Length
                    MIN5 = MBB /* \_SB_.PCI0.MBB_ */
                    LEN5 = (NBTP - MBB)
                    Local1 = LEN5 /* \_SB_.PCI0._CRS.LEN5 */
                    MAX5 = (MIN5 + Local1--)
                    CreateDWordField (CRS2, \_SB.PCI0._Y0E._MIN, MIN6)  // _MIN: Minimum Base Address
                    CreateDWordField (CRS2, \_SB.PCI0._Y0E._MAX, MAX6)  // _MAX: Maximum Base Address
                    CreateDWordField (CRS2, \_SB.PCI0._Y0E._LEN, LEN6)  // _LEN: Length
                    MIN6 = (NBTP + NBTS) /* \NBTS */
                    LEN6 = (MBL - NBTS)
                    LEN6 = (LEN6 - LEN5)
                    Local0 = LEN6 /* \_SB_.PCI0._CRS.LEN6 */
                    MAX6 = (MIN6 + Local0--)
                    If (MAL)
                    {
                        CreateQWordField (CRS2, \_SB.PCI0._Y0F._MIN, MN9)  // _MIN: Minimum Base Address
                        CreateQWordField (CRS2, \_SB.PCI0._Y0F._MAX, MX9)  // _MAX: Maximum Base Address
                        CreateQWordField (CRS2, \_SB.PCI0._Y0F._LEN, LN9)  // _LEN: Length
                        MN9 = MAB /* \_SB_.PCI0.MAB_ */
                        LN9 = MAL /* \_SB_.PCI0.MAL_ */
                        MX9 = MAM /* \_SB_.PCI0.MAM_ */
                    }

                    DBG8 = 0x23
                    Return (CRS2) /* \_SB_.PCI0.CRS2 */
                }
            }

            Method (_OSC, 4, Serialized)  // _OSC: Operating System Capabilities
            {
                Name (SUPP, Zero)
                Name (CTRL, Zero)
                CreateDWordField (Arg3, Zero, CDW1)
                CreateDWordField (Arg3, 0x04, CDW2)
                CreateDWordField (Arg3, 0x08, CDW3)
                If ((Arg0 == ToUUID ("33db4d5b-1ff7-401c-9657-7441c03dd766") /* PCI Host Bridge Device */))
                {
                    SUPP = CDW2 /* \_SB_.PCI0._OSC.CDW2 */
                    CTRL = CDW3 /* \_SB_.PCI0._OSC.CDW3 */
                    If (((SUPP & 0x16) != 0x16))
                    {
                        CTRL &= 0x1E
                    }

                    If (!PEHP)
                    {
                        CTRL &= 0x1E
                    }

                    If (!SHPC)
                    {
                        CTRL &= 0x1D
                    }

                    If (!PEPM)
                    {
                        CTRL &= 0x1B
                    }

                    If (!PEER)
                    {
                        CTRL &= 0x15
                    }

                    If (!PECS)
                    {
                        CTRL &= 0x0F
                    }

                    If ((Arg1 != One))
                    {
                        CDW1 |= 0x08
                    }

                    If ((CDW3 != CTRL))
                    {
                        CDW1 |= 0x10
                    }

                    CDW3 = CTRL /* \_SB_.PCI0._OSC.CTRL */
                    Return (Arg3)
                }
                Else
                {
                    CDW1 |= 0x04
                    Return (Arg3)
                }
            }

            Mutex (NAPM, 0x00)
            Method (NAPE, 0, NotSerialized)
            {
                Acquire (NAPM, 0xFFFF)
                DBG8 = 0x11
                Local0 = (PEBS + 0xB8)
                OperationRegion (VARM, SystemMemory, Local0, 0x08)
                Field (VARM, DWordAcc, NoLock, Preserve)
                {
                    NAPX,   32, 
                    NAPD,   32
                }

                Local1 = NAPX /* \_SB_.PCI0.NAPE.NAPX */
                NAPX = 0x14300000
                Local0 = NAPD /* \_SB_.PCI0.NAPE.NAPD */
                Local0 &= 0xFFFFFFEF
                NAPD = Local0
                NAPX = Local1
                DBG8 = 0x12
                Release (NAPM)
            }

            Device (IOMA)
            {
                Name (_ADR, 0x02)  // _ADR: Address
            }

            Device (SBRG)
            {
                Name (_ADR, 0x00140003)  // _ADR: Address
                OperationRegion (SMI0, SystemIO, SMIO, One)
                Field (SMI0, ByteAcc, NoLock, Preserve)
                {
                    SMIC,   8
                }

                Scope (\_SB)
                {
                    Scope (PCI0)
                    {
                        Device (S900)
                        {
                            Name (_HID, EisaId ("PNP0C02") /* PNP Motherboard Resources */)  // _HID: Hardware ID
                            Name (_UID, 0x0700)  // _UID: Unique ID
                            Name (_STA, 0x0F)  // _STA: Status
                            Name (CRS, ResourceTemplate ()
                            {
                                IO (Decode16,
                                    0x0010,             // Range Minimum
                                    0x0010,             // Range Maximum
                                    0x00,               // Alignment
                                    0x10,               // Length
                                    )
                                IO (Decode16,
                                    0x0022,             // Range Minimum
                                    0x0022,             // Range Maximum
                                    0x00,               // Alignment
                                    0x1E,               // Length
                                    )
                                IO (Decode16,
                                    0x0063,             // Range Minimum
                                    0x0063,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0065,             // Range Minimum
                                    0x0065,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0067,             // Range Minimum
                                    0x0067,             // Range Maximum
                                    0x00,               // Alignment
                                    0x09,               // Length
                                    )
                                IO (Decode16,
                                    0x0072,             // Range Minimum
                                    0x0072,             // Range Maximum
                                    0x00,               // Alignment
                                    0x0E,               // Length
                                    )
                                IO (Decode16,
                                    0x0080,             // Range Minimum
                                    0x0080,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0084,             // Range Minimum
                                    0x0084,             // Range Maximum
                                    0x00,               // Alignment
                                    0x03,               // Length
                                    )
                                IO (Decode16,
                                    0x0088,             // Range Minimum
                                    0x0088,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x008C,             // Range Minimum
                                    0x008C,             // Range Maximum
                                    0x00,               // Alignment
                                    0x03,               // Length
                                    )
                                IO (Decode16,
                                    0x0090,             // Range Minimum
                                    0x0090,             // Range Maximum
                                    0x00,               // Alignment
                                    0x10,               // Length
                                    )
                                IO (Decode16,
                                    0x00A2,             // Range Minimum
                                    0x00A2,             // Range Maximum
                                    0x00,               // Alignment
                                    0x1E,               // Length
                                    )
                                IO (Decode16,
                                    0x00B1,             // Range Minimum
                                    0x00B1,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x00E0,             // Range Minimum
                                    0x00E0,             // Range Maximum
                                    0x00,               // Alignment
                                    0x10,               // Length
                                    )
                                IO (Decode16,
                                    0x04D0,             // Range Minimum
                                    0x04D0,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x040B,             // Range Minimum
                                    0x040B,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x04D6,             // Range Minimum
                                    0x04D6,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0C00,             // Range Minimum
                                    0x0C00,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0C14,             // Range Minimum
                                    0x0C14,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0C50,             // Range Minimum
                                    0x0C50,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0C52,             // Range Minimum
                                    0x0C52,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0C6C,             // Range Minimum
                                    0x0C6C,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0C6F,             // Range Minimum
                                    0x0C6F,             // Range Maximum
                                    0x00,               // Alignment
                                    0x01,               // Length
                                    )
                                IO (Decode16,
                                    0x0CD0,             // Range Minimum
                                    0x0CD0,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0CD2,             // Range Minimum
                                    0x0CD2,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0CD4,             // Range Minimum
                                    0x0CD4,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0CD6,             // Range Minimum
                                    0x0CD6,             // Range Maximum
                                    0x00,               // Alignment
                                    0x02,               // Length
                                    )
                                IO (Decode16,
                                    0x0CD8,             // Range Minimum
                                    0x0CD8,             // Range Maximum
                                    0x00,               // Alignment
                                    0x08,               // Length
                                    )
                                IO (Decode16,
                                    0x0000,             // Range Minimum
                                    0x0000,             // Range Maximum
                                    0x00,               // Alignment
                                    0x00,               // Length
                                    _Y10)
                                IO (Decode16,
                                    0x0000,             // Range Minimum
                                    0x0000,             // Range Maximum
                                    0x00,               // Alignment
                                    0x00,               // Length
                                    _Y12)
                                IO (Decode16,
                                    0x0000,             // Range Minimum
                                    0x0000,             // Range Maximum
                                    0x00,               // Alignment
                                    0x00,               // Length
                                    _Y11)
                                IO (Decode16,
                                    0x0900,             // Range Minimum
                                    0x0900,             // Range Maximum
                                    0x00,               // Alignment
                                    0x10,               // Length
                                    )
                                IO (Decode16,
                                    0x0910,             // Range Minimum
                                    0x0910,             // Range Maximum
                                    0x00,               // Alignment
                                    0x10,               // Length
                                    )
                                IO (Decode16,
                                    0x0060,             // Range Minimum
                                    0x0060,             // Range Maximum
                                    0x00,               // Alignment
                                    0x00,               // Length
                                    )
                                IO (Decode16,
                                    0x0064,             // Range Minimum
                                    0x0064,             // Range Maximum
                                    0x00,               // Alignment
                                    0x00,               // Length
                                    )
                                Memory32Fixed (ReadWrite,
                                    0x00000000,         // Address Base
                                    0x00000000,         // Address Length
                                    _Y13)
                                Memory32Fixed (ReadWrite,
                                    0xFEC01000,         // Address Base
                                    0x00001000,         // Address Length
                                    )
                                Memory32Fixed (ReadWrite,
                                    0xFEDC0000,         // Address Base
                                    0x00001000,         // Address Length
                                    )
                                Memory32Fixed (ReadWrite,
                                    0xFEE00000,         // Address Base
                                    0x00001000,         // Address Length
                                    )
                                Memory32Fixed (ReadWrite,
                                    0xFED80000,         // Address Base
                                    0x00010000,         // Address Length
                                    )
                                Memory32Fixed (ReadWrite,
                                    0x00000000,         // Address Base
                                    0x00000000,         // Address Length
                                    _Y14)
                                Memory32Fixed (ReadWrite,
                                    0x00000000,         // Address Base
                                    0x00000000,         // Address Length
                                    _Y15)
                                Memory32Fixed (ReadWrite,
                                    0x00000000,         // Address Base
                                    0x00000000,         // Address Length
                                    _Y16)
                            })
                            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                            {
                                CreateWordField (CRS, \_SB.PCI0.S900._Y10._MIN, PBB)  // _MIN: Minimum Base Address
                                CreateWordField (CRS, \_SB.PCI0.S900._Y10._MAX, PBH)  // _MAX: Maximum Base Address
                                CreateByteField (CRS, \_SB.PCI0.S900._Y10._LEN, PML)  // _LEN: Length
                                PBB = PMBS /* \PMBS */
                                PBH = PMBS /* \PMBS */
                                PML = PMLN /* \PMLN */
                                If (SMBB)
                                {
                                    CreateWordField (CRS, \_SB.PCI0.S900._Y11._MIN, SMB1)  // _MIN: Minimum Base Address
                                    CreateWordField (CRS, \_SB.PCI0.S900._Y11._MAX, SMH1)  // _MAX: Maximum Base Address
                                    CreateByteField (CRS, \_SB.PCI0.S900._Y11._LEN, SML1)  // _LEN: Length
                                    SMB1 = SMBB /* \SMBB */
                                    SMH1 = SMBB /* \SMBB */
                                    SML1 = SMBL /* \SMBL */
                                    CreateWordField (CRS, \_SB.PCI0.S900._Y12._MIN, SMBZ)  // _MIN: Minimum Base Address
                                    CreateWordField (CRS, \_SB.PCI0.S900._Y12._MAX, SMH0)  // _MAX: Maximum Base Address
                                    CreateByteField (CRS, \_SB.PCI0.S900._Y12._LEN, SML0)  // _LEN: Length
                                    SMBZ = SMB0 /* \SMB0 */
                                    SMH0 = SMB0 /* \SMB0 */
                                    SML0 = SMBM /* \SMBM */
                                }

                                If (APCB)
                                {
                                    CreateDWordField (CRS, \_SB.PCI0.S900._Y13._BAS, APB)  // _BAS: Base Address
                                    CreateDWordField (CRS, \_SB.PCI0.S900._Y13._LEN, APL)  // _LEN: Length
                                    APB = APCB /* \APCB */
                                    APL = APCL /* \APCL */
                                }

                                CreateDWordField (CRS, \_SB.PCI0.S900._Y14._BAS, SPIB)  // _BAS: Base Address
                                CreateDWordField (CRS, \_SB.PCI0.S900._Y14._LEN, SPIL)  // _LEN: Length
                                SPIB = 0xFEC10000
                                SPIL = 0x1000
                                If (WDTB)
                                {
                                    CreateDWordField (CRS, \_SB.PCI0.S900._Y15._BAS, WDTB)  // _BAS: Base Address
                                    CreateDWordField (CRS, \_SB.PCI0.S900._Y15._LEN, WDTL)  // _LEN: Length
                                    WDTB = \WDTB
                                    WDTL = \WDTL
                                }

                                CreateDWordField (CRS, \_SB.PCI0.S900._Y16._BAS, ROMB)  // _BAS: Base Address
                                CreateDWordField (CRS, \_SB.PCI0.S900._Y16._LEN, ROML)  // _LEN: Length
                                ROMB = 0xFF000000
                                ROML = 0x01000000
                                Return (CRS) /* \_SB_.PCI0.S900.CRS_ */
                            }
                        }
                    }
                }

                Scope (\_SB)
                {
                    Scope (PCI0)
                    {
                        Scope (SBRG)
                        {
                            Method (RRIO, 4, NotSerialized)
                            {
                                Debug = "RRIO"
                            }

                            Method (RDMA, 3, NotSerialized)
                            {
                                Debug = "rDMA"
                            }
                        }
                    }
                }
            }

            Device (D035)
            {
                Name (_ADR, 0x00140006)  // _ADR: Address
            }
        }
    }

    Name (_S0, Package (0x04)  // _S0_: S0 System State
    {
        Zero, 
        Zero, 
        Zero, 
        Zero
    })
    Name (XS3, Package (0x04)
    {
        0x03, 
        Zero, 
        Zero, 
        Zero
    })
    Name (_S4, Package (0x04)  // _S4_: S4 System State
    {
        0x04, 
        Zero, 
        Zero, 
        Zero
    })
    Name (_S5, Package (0x04)  // _S5_: S5 System State
    {
        0x05, 
        Zero, 
        Zero, 
        Zero
    })
    Method (_PTS, 1, NotSerialized)  // _PTS: Prepare To Sleep
    {
        If (Arg0)
        {
            XPTS (Arg0)
            \_SB.TPM.TPTS (Arg0)
            MPTS (Arg0)
            SPTS (Arg0)
            \_SB.PCI0.NPTS (Arg0)
        }
    }

    Method (_WAK, 1, NotSerialized)  // _WAK: Wake
    {
        If (((Arg0 == 0x03) || (Arg0 == 0x04)))
        {
            If ((PICM != Zero))
            {
                \_SB.PCI0.NAPE ()
            }
        }

        If ((Arg0 == 0x04))
        {
            PT80 (0xE4)
            If ((\_SB.CMBS == Zero))
            {
                Notify (\_SB.PWRB, 0x02) // Device Wake
            }
            Else
            {
                Notify (\_SB.BTNS, 0x02) // Device Wake
            }
        }

        DBG8 = (Arg0 << 0x04)
        \_SB.PCI0.NWAK (Arg0)
        DBG8 = (Arg0 << 0x04)
        SWAK (Arg0)
        MWAK (Arg0)
        XWAK (Arg0)
        \_SB.ACAD.ACDC = 0xFF
        Return (WAKP) /* \WAKP */
    }

    Scope (_SB)
    {
        OperationRegion (PIRQ, SystemIO, 0x0C00, 0x02)
        Field (PIRQ, ByteAcc, NoLock, Preserve)
        {
            PIDX,   8, 
            PDAT,   8
        }

        IndexField (PIDX, PDAT, ByteAcc, NoLock, Preserve)
        {
            PIRA,   8, 
            PIRB,   8, 
            PIRC,   8, 
            PIRD,   8, 
            PIRE,   8, 
            PIRF,   8, 
            PIRG,   8, 
            PIRH,   8, 
            Offset (0x0C), 
            SIRA,   8, 
            SIRB,   8, 
            SIRC,   8, 
            SIRD,   8, 
            PIRS,   8, 
            Offset (0x13), 
            HDAD,   8, 
            Offset (0x17), 
            SDCL,   8, 
            Offset (0x1A), 
            SDIO,   8, 
            Offset (0x30), 
            USB1,   8, 
            Offset (0x34), 
            USB3,   8, 
            Offset (0x41), 
            SATA,   8, 
            Offset (0x62), 
            GIOC,   8, 
            Offset (0x70), 
            I2C0,   8, 
            I2C1,   8, 
            I2C2,   8, 
            I2C3,   8, 
            URT0,   8, 
            URT1,   8, 
            Offset (0x80), 
            AIRA,   8, 
            AIRB,   8, 
            AIRC,   8, 
            AIRD,   8, 
            AIRE,   8, 
            AIRF,   8, 
            AIRG,   8, 
            AIRH,   8
        }

        OperationRegion (KBDD, SystemIO, 0x64, One)
        Field (KBDD, ByteAcc, NoLock, Preserve)
        {
            PD64,   8
        }

        Method (DSPI, 0, NotSerialized)
        {
            INTA (0x1F)
            INTB (0x1F)
            INTC (0x1F)
            INTD (0x1F)
            Local1 = PD64 /* \_SB_.PD64 */
            PIRE = 0x1F
            PIRF = 0x1F
            PIRG = 0x1F
            PIRH = 0x1F
            Local1 = PD64 /* \_SB_.PD64 */
            AIRA = 0x10
            AIRB = 0x11
            AIRC = 0x12
            AIRD = 0x13
            AIRE = 0x14
            AIRF = 0x15
            AIRG = 0x16
            AIRH = 0x17
        }

        Method (INTA, 1, NotSerialized)
        {
            PIRA = Arg0
            HDAD = Arg0
        }

        Method (INTB, 1, NotSerialized)
        {
            PIRB = Arg0
        }

        Method (INTC, 1, NotSerialized)
        {
            PIRC = Arg0
            USB1 = Arg0
            USB3 = Arg0
        }

        Method (INTD, 1, NotSerialized)
        {
            PIRD = Arg0
            SATA = Arg0
        }

        Name (BUFA, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {15}
        })
        Name (IPRA, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {5,10,11}
        })
        Name (IPRB, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {5,10,11}
        })
        Name (IPRC, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {5,10,11}
        })
        Name (IPRD, ResourceTemplate ()
        {
            IRQ (Level, ActiveLow, Shared, )
                {5,10,11}
        })
        Device (LNKA)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRA)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSA) /* \_SB_.PRSA */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                INTA (0x1F)
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRA) /* \_SB_.PIRA */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                INTA (Local0)
            }
        }

        Device (LNKB)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRB)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSB) /* \_SB_.PRSB */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                INTB (0x1F)
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRB) /* \_SB_.PIRB */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                INTB (Local0)
            }
        }

        Device (LNKC)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRC)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSC) /* \_SB_.PRSC */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                INTC (0x1F)
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRC) /* \_SB_.PIRC */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                INTC (Local0)
            }
        }

        Device (LNKD)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x04)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRD)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSD) /* \_SB_.PRSD */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                INTD (0x1F)
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRD) /* \_SB_.PIRD */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                INTD (Local0)
            }
        }

        Device (LNKE)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x05)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRE)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSE) /* \_SB_.PRSE */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                PIRE = 0x1F
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRE) /* \_SB_.PIRE */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (PIRE, Local0)
                Local0--
                PIRE = Local0
            }
        }

        Device (LNKF)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x06)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRF)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSF) /* \_SB_.PRSF */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                PIRF = 0x1F
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRF) /* \_SB_.PIRF */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                PIRF = Local0
            }
        }

        Device (LNKG)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x07)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRG)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSG) /* \_SB_.PRSG */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                PIRG = 0x1F
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRG) /* \_SB_.PIRG */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                PIRG = Local0
            }
        }

        Device (LNKH)
        {
            Name (_HID, EisaId ("PNP0C0F") /* PCI Interrupt Link Device */)  // _HID: Hardware ID
            Name (_UID, 0x08)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (PIRH)
                {
                    Return (0x0B)
                }
                Else
                {
                    Return (0x09)
                }
            }

            Method (_PRS, 0, NotSerialized)  // _PRS: Possible Resource Settings
            {
                Return (PRSH) /* \_SB_.PRSH */
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
                PIRH = 0x1F
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                CreateWordField (BUFA, One, IRQX)
                IRQX = (One << PIRH) /* \_SB_.PIRH */
                Return (BUFA) /* \_SB_.BUFA */
            }

            Method (_SRS, 1, NotSerialized)  // _SRS: Set Resource Settings
            {
                CreateWordField (Arg0, One, IRA)
                FindSetRightBit (IRA, Local0)
                Local0--
                PIRH = Local0
            }
        }
    }

    Name (OSTB, Ones)
    Name (TPOS, Zero)
    Name (OSSP, Zero)
    Method (SEQL, 2, Serialized)
    {
        Local0 = SizeOf (Arg0)
        Local1 = SizeOf (Arg1)
        If ((Local0 != Local1))
        {
            Return (Zero)
        }

        Name (BUF0, Buffer (Local0){})
        BUF0 = Arg0
        Name (BUF1, Buffer (Local0){})
        BUF1 = Arg1
        Local2 = Zero
        While ((Local2 < Local0))
        {
            Local3 = DerefOf (BUF0 [Local2])
            Local4 = DerefOf (BUF1 [Local2])
            If ((Local3 != Local4))
            {
                Return (Zero)
            }

            Local2++
        }

        Return (One)
    }

    Method (OSTP, 0, NotSerialized)
    {
        If ((OSTB == Ones))
        {
            If (CondRefOf (\_OSI, Local0))
            {
                OSTB = Zero
                TPOS = Zero
                If (_OSI ("Windows 2001"))
                {
                    OSTB = 0x08
                    TPOS = 0x08
                }

                If (_OSI ("Windows 2001.1"))
                {
                    OSTB = 0x20
                    TPOS = 0x20
                }

                If (_OSI ("Windows 2001 SP1"))
                {
                    OSTB = 0x10
                    TPOS = 0x10
                }

                If (_OSI ("Windows 2001 SP2"))
                {
                    OSTB = 0x11
                    TPOS = 0x11
                }

                If (_OSI ("Windows 2001 SP3"))
                {
                    OSTB = 0x12
                    TPOS = 0x12
                }

                If (_OSI ("Windows 2006"))
                {
                    OSTB = 0x40
                    TPOS = 0x40
                }

                If (_OSI ("Windows 2006 SP1"))
                {
                    OSTB = 0x41
                    TPOS = 0x41
                    OSSP = One
                }

                If (_OSI ("Windows 2009"))
                {
                    OSSP = One
                    OSTB = 0x50
                    TPOS = 0x50
                }

                If (_OSI ("Windows 2012"))
                {
                    OSSP = One
                    OSTB = 0x60
                    TPOS = 0x60
                }

                If (_OSI ("Windows 2013"))
                {
                    OSSP = One
                    OSTB = 0x61
                    TPOS = 0x61
                }

                If (_OSI ("Windows 2015"))
                {
                    OSSP = One
                    OSTB = 0x70
                    TPOS = 0x70
                }
            }
            ElseIf (CondRefOf (\_OS, Local0))
            {
                If (SEQL (_OS, "Microsoft Windows"))
                {
                    OSTB = One
                    TPOS = One
                }
                ElseIf (SEQL (_OS, "Microsoft WindowsME: Millennium Edition"))
                {
                    OSTB = 0x02
                    TPOS = 0x02
                }
                ElseIf (SEQL (_OS, "Microsoft Windows NT"))
                {
                    OSTB = 0x04
                    TPOS = 0x04
                }
                Else
                {
                    OSTB = Zero
                    TPOS = Zero
                }
            }
            Else
            {
                OSTB = Zero
                TPOS = Zero
            }
        }

        Return (OSTB) /* \OSTB */
    }

    Scope (_SB.PCI0)
    {
        Method (_INI, 0, NotSerialized)  // _INI: Initialize
        {
            If ((PICM != Zero))
            {
                DSPI ()
                NAPE ()
            }

            OSTP ()
            OSFL ()
        }
    }

    OperationRegion (DBG0, SystemIO, 0x80, One)
    Field (DBG0, ByteAcc, NoLock, Preserve)
    {
        IO80,   8
    }

    OperationRegion (DBG1, SystemIO, 0x80, 0x04)
    Field (DBG1, DWordAcc, NoLock, Preserve)
    {
        P80H,   32
    }

    OperationRegion (PCPT, SystemIO, 0x80, 0x04)
    Field (PCPT, DWordAcc, NoLock, Preserve)
    {
        PC80,   32
    }

    OperationRegion (PSMI, SystemIO, 0xB0, 0x02)
    Field (PSMI, ByteAcc, NoLock, Preserve)
    {
        APMC,   8, 
        APMD,   8
    }

    OperationRegion (PMI0, SystemMemory, 0xFED80300, 0x0100)
    Field (PMI0, AnyAcc, NoLock, Preserve)
    {
            ,   6, 
        HPEN,   1, 
        Offset (0x60), 
        P1EB,   16
    }

    OperationRegion (GSMG, SystemMemory, 0xFED81500, 0x03FF)
    Field (GSMG, AnyAcc, NoLock, Preserve)
    {
        Offset (0x5C), 
        Offset (0x5E), 
        GS23,   1, 
            ,   5, 
        GV23,   1, 
        GE23,   1, 
        Offset (0xA0), 
        Offset (0xA2), 
        GS40,   1, 
            ,   5, 
        GV40,   1, 
        GE40,   1
    }

    OperationRegion (GSMM, SystemMemory, 0xFED80000, 0x1000)
    Field (GSMM, AnyAcc, NoLock, Preserve)
    {
        Offset (0x288), 
            ,   1, 
        CLPS,   1, 
        Offset (0x296), 
            ,   7, 
        TMSE,   1, 
        Offset (0x2B0), 
            ,   2, 
        SLPS,   2
    }

    OperationRegion (PMI2, SystemMemory, 0xFED80300, 0x0100)
    Field (PMI2, AnyAcc, NoLock, Preserve)
    {
        Offset (0xBB), 
            ,   6, 
        PWDE,   1, 
        Offset (0xBC)
    }

    OperationRegion (P1E0, SystemIO, P1EB, 0x04)
    Field (P1E0, ByteAcc, NoLock, Preserve)
    {
            ,   14, 
        PEWS,   1, 
        WSTA,   1, 
            ,   14, 
        PEWD,   1
    }

    OperationRegion (IOCC, SystemIO, 0x0400, 0x80)
    Field (IOCC, ByteAcc, NoLock, Preserve)
    {
        Offset (0x01), 
            ,   2, 
        RTCS,   1
    }

    Name (CNSB, One)
    Name (RDHW, Zero)
    Name (TBEN, Zero)
    Name (TBNH, 0x03)
    Name (DPTC, Zero)
    Name (THPN, 0x05)
    Name (THPD, 0x04)
    Name (NFCS, 0x04)
    Method (PT80, 1, Serialized)
    {
        Local0 = (Arg0 & 0x00FFFFFF)
        PC80 = (Local0 | 0xDB000000)
    }

    Scope (_SB)
    {
        Name (CMBS, 0x00)
        Device (PWRB)
        {
            Name (_HID, EisaId ("PNP0C0C") /* Power Button Device */)  // _HID: Hardware ID
            Name (_DDN, "Power button")  // _DDN: DOS Device Name
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Name (PSTA, Zero)
                M460 ("PLA-ASL-\\_SB.PWRB._STA = 0xB\n", Zero, Zero, Zero, Zero, Zero, Zero)
                If ((CMBS == Zero))
                {
                    PSTA = 0x0B
                }

                Return (PSTA) /* \_SB_.PWRB._STA.PSTA */
            }
        }

        Device (BTNS)
        {
            Name (_HID, "ACPI0011" /* Generic Buttons Device */)  // _HID: Hardware ID
            Name (_DDN, "Generic buttons device")  // _DDN: DOS Device Name
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    GpioInt (Edge, ActiveBoth, Exclusive, PullUp, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0000
                        }
                })
                Return (RBUF) /* \_SB_.BTNS._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Name (PSTA, Zero)
                M460 ("PLA-ASL-\\_SB.BTNS._STA = 0xB\n", Zero, Zero, Zero, Zero, Zero, Zero)
                If ((CMBS == One))
                {
                    PSTA = 0x0B
                }

                Return (PSTA) /* \_SB_.BTNS._STA.PSTA */
            }

            Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
            {
                ToUUID ("fa6bd625-9ce8-470d-a2c7-b3ca36c4282e") /* Generic Buttons Device */, 
                Package (0x02)
                {
                    Package (0x05)
                    {
                        Zero, 
                        One, 
                        Zero, 
                        One, 
                        0x0D
                    }, 

                    Package (0x05)
                    {
                        One, 
                        Zero, 
                        One, 
                        One, 
                        0x81
                    }
                }
            })
        }

        Device (AMDM)
        {
            Name (_HID, EisaId ("PNP0C02") /* PNP Motherboard Resources */)  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
            {
                Memory32Fixed (ReadWrite,
                    0xE0000000,         // Address Base
                    0x10000000,         // Address Length
                    )
            })
        }

        Scope (PCI0)
        {
            Mutex (MGCC, 0x00)
            Name (AR00, Package (0x12)
            {
                Package (0x04)
                {
                    0x0001FFFF, 
                    Zero, 
                    Zero, 
                    0x18
                }, 

                Package (0x04)
                {
                    0x0001FFFF, 
                    One, 
                    Zero, 
                    0x19
                }, 

                Package (0x04)
                {
                    0x0001FFFF, 
                    0x02, 
                    Zero, 
                    0x1A
                }, 

                Package (0x04)
                {
                    0x0002FFFF, 
                    Zero, 
                    Zero, 
                    0x1C
                }, 

                Package (0x04)
                {
                    0x0002FFFF, 
                    One, 
                    Zero, 
                    0x1D
                }, 

                Package (0x04)
                {
                    0x0002FFFF, 
                    0x02, 
                    Zero, 
                    0x1E
                }, 

                Package (0x04)
                {
                    0x0002FFFF, 
                    0x03, 
                    Zero, 
                    0x1F
                }, 

                Package (0x04)
                {
                    0x0003FFFF, 
                    Zero, 
                    Zero, 
                    0x20
                }, 

                Package (0x04)
                {
                    0x0003FFFF, 
                    One, 
                    Zero, 
                    0x21
                }, 

                Package (0x04)
                {
                    0x0003FFFF, 
                    0x02, 
                    Zero, 
                    0x22
                }, 

                Package (0x04)
                {
                    0x0003FFFF, 
                    0x03, 
                    Zero, 
                    0x23
                }, 

                Package (0x04)
                {
                    0x0008FFFF, 
                    Zero, 
                    Zero, 
                    0x24
                }, 

                Package (0x04)
                {
                    0x0008FFFF, 
                    One, 
                    Zero, 
                    0x25
                }, 

                Package (0x04)
                {
                    0x0008FFFF, 
                    0x02, 
                    Zero, 
                    0x26
                }, 

                Package (0x04)
                {
                    0x0014FFFF, 
                    Zero, 
                    Zero, 
                    0x10
                }, 

                Package (0x04)
                {
                    0x0014FFFF, 
                    One, 
                    Zero, 
                    0x11
                }, 

                Package (0x04)
                {
                    0x0014FFFF, 
                    0x02, 
                    Zero, 
                    0x12
                }, 

                Package (0x04)
                {
                    0x0014FFFF, 
                    0x03, 
                    Zero, 
                    0x13
                }
            })
            Device (GPP0)
            {
                Name (_ADR, 0x00010001)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x18
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x19
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x1A
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x1B
                    }
                })
            }

            Device (GPP1)
            {
                Name (_ADR, 0x00010002)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x1C
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x1D
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x1E
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x1F
                    }
                })
            }

            Device (GPP3)
            {
                Name (_ADR, 0x00020001)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x24
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x25
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x26
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x27
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPP4)
            {
                Name (_ADR, 0x00020002)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x28
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x29
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x2A
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x2B
                    }
                })
                Device (SDCR)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                }
            }

            Device (GPP5)
            {
                Name (_ADR, 0x00020003)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x2C
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x2D
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x2E
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x2F
                    }
                })
                Device (WLAN)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                    Method (MTCC, 0, Serialized)
                    {
                        Name (CCDE, Package (0x07)
                        {
                            0x4D, 
                            0x54, 
                            0x43, 
                            0x43, 
                            Zero, 
                            0xFF, 
                            0xFF
                        })
                        Return (CCDE) /* \_SB_.PCI0.GPP5.WLAN.MTCC.CCDE */
                    }
                }

                Device (BTH0)
                {
                    Name (_HID, "QCOM6390")  // _HID: Hardware ID
                    Name (_S4W, 0x02)  // _S4W: S4 Device Wake State
                    Name (_S0W, 0x02)  // _S0W: S0 Device Wake State
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                        Return (Zero)
                    }

                    Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                    {
                        Name (UBUF, ResourceTemplate ()
                        {
                            UartSerialBusV2 (0x0001C200, DataBitsEight, StopBitsOne,
                                0xC0, LittleEndian, ParityTypeNone, FlowControlHardware,
                                0x0020, 0x0020, "\\_SB.FUR0",
                                0x00, ResourceConsumer, , Exclusive,
                                )
                            GpioInt (Edge, ActiveLow, ExclusiveAndWake, PullUp, 0x0000,
                                "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                                )
                                {   // Pin list
                                    0x0004
                                }
                        })
                        Return (UBUF) /* \_SB_.PCI0.GPP5.BTH0._CRS.UBUF */
                    }
                }

                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPP6)
            {
                Name (_ADR, 0x00020004)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x2E
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x2F
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x2C
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x2D
                    }
                })
                Device (RTL8)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                    Name (DSEN, 0x00)
                    Name (RPB, Zero)
                    Name (RPD, Zero)
                    Name (RPF, Zero)
                    Method (_INI, 0, Serialized)  // _INI: Initialize
                    {
                        M460 ("PLA-ASL-RTK-DashLanDevice-_INI\n", Zero, Zero, Zero, Zero, Zero, Zero)
                        RPD = (^^_ADR >> 0x10)
                        RPF = (^^_ADR & 0xFFFF)
                        M460 ("PLA-ASL-RTK-DashLanDevice-_INI Parent B/D/F: %X/%X/%X\n", RPB, RPD, RPF, Zero, Zero, Zero)
                    }

                    Method (_REG, 2, NotSerialized)  // _REG: Region Availability
                    {
                        If (((Arg0 == 0x02) && (Arg1 == One)))
                        {
                            M460 ("PLA-ASL-RTK-DashLanDevice-_REG Dash Option: %d\n", DSEN, Zero, Zero, Zero, Zero, Zero)
                            If ((DSEN == Zero))
                            {
                                Local0 = M017 (RPB, RPD, RPF, 0x19, Zero, 0x08)
                                Local1 = M017 (Local0, Zero, Zero, Zero, Zero, 0x10)
                                M460 ("PLA-ASL-RTK-DashLanDevice-_REG Vendor ID: 0x%X\n", Local1, Zero, Zero, Zero, Zero, Zero)
                                If ((Local1 == 0x10EC))
                                {
                                    Local2 = M019 (Local0, Zero, Zero, 0x10)
                                    Local2 &= 0xFFF0
                                    OperationRegion (VAIO, SystemIO, Local2, 0x0100)
                                    Field (VAIO, ByteAcc, NoLock, Preserve)
                                    {
                                        Offset (0x40), 
                                        XX40,   32, 
                                        Offset (0x64), 
                                        XX64,   32, 
                                        XX68,   32, 
                                        Offset (0xB0), 
                                        XXB0,   32
                                    }

                                    Local1 = XX40 /* \_SB_.PCI0.GPP6.RTL8._REG.XX40 */
                                    XXB0 = 0x6E000000
                                    Sleep (0x02)
                                    Local2 = XXB0 /* \_SB_.PCI0.GPP6.RTL8._REG.XXB0 */
                                    If (((Local1 & 0x7C800000) == 0x50000000))
                                    {
                                        M460 ("PLA-ASL-RTK-DashLanDevice-_REG Disable multi-function for RTK8111EP\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                        XX64 = 0xFFFFFFFF
                                        XX68 = 0x8001F000
                                        Sleep (0x02)
                                        XX64 = 0xFFFFFFFF
                                        XX68 = 0x8002F000
                                        Sleep (0x02)
                                        XX64 = 0xFFFFFFFF
                                        XX68 = 0x8003F000
                                        Sleep (0x02)
                                        XX64 = 0xFFFFFFFF
                                        XX68 = 0x8004F000
                                    }
                                    ElseIf (((((Local1 & 0x7CF00000) == 0x54A00000) || ((
                                        Local1 & 0x7CF00000) == 0x54B00000)) && ((Local2 & 0x78) == Zero)))
                                    {
                                        M460 ("PLA-ASL-RTK-DashLanDevice-_REG Disable multi-function for RTK8111FP\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                        XX64 = 0xFFFFFFFF
                                        XX68 = 0x8002F000
                                        Sleep (0x02)
                                        XX68 = 0x8004F000
                                        Sleep (0x02)
                                        XX68 = 0x8007F000
                                    }
                                    Else
                                    {
                                        M460 ("PLA-ASL-RTK-DashLanDevice-_REG Do nothing for other RTK Controller\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                    }
                                }
                            }
                        }
                    }
                }

                Device (RUSB)
                {
                    Name (_ADR, 0x04)  // _ADR: Address
                }

                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPP7)
            {
                Name (_ADR, 0x00020005)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x2A
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x2B
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x28
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x29
                    }
                })
                Device (WWAN)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                }

                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPP8)
            {
                Name (_ADR, 0x00020006)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x26
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x27
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x24
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x25
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPP9)
            {
                Name (_ADR, 0x00030001)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x22
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x23
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x20
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x21
                    }
                })
            }

            Device (GP10)
            {
                Name (_ADR, 0x00030002)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x1E
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x1F
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x1C
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x1D
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GP11)
            {
                Name (_ADR, 0x00030003)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x1A
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x1B
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x18
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x19
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GP12)
            {
                Name (_ADR, 0x00030004)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x19
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x1A
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x1B
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x18
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GP13)
            {
                Name (_ADR, 0x00030005)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x1D
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x1E
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x1F
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x1C
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GP14)
            {
                Name (_ADR, 0x00030006)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x21
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x22
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x23
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x20
                    }
                })
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
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

            Device (GPPA)
            {
                Name (_ADR, 0x00080001)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x27
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x24
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x25
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x26
                    }
                })
                Device (VGA)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                    Name (DOSA, Zero)
                    Method (SINI, 0, Serialized)
                    {
                        M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA0._INI\n", Zero, Zero, Zero, Zero, Zero, Zero)
                    }

                    Method (SREG, 2, NotSerialized)
                    {
                        M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA0._REG Arg0:0x%x Arg1:0x%x\n", Arg0, Arg1, Zero, Zero, Zero, Zero)
                        If ((Arg1 == One))
                        {
                            ALIB (0xBB, Zero)
                            M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA0._REG Set/clear the IGPU C2P register DEADBEEF\n", Zero, Zero, Zero, Zero, Zero, Zero)
                        }
                    }

                    Method (_DOS, 1, NotSerialized)  // _DOS: Disable Output Switching
                    {
                        DOSA = Arg0
                    }

                    Method (_DOD, 0, NotSerialized)  // _DOD: Display Output Devices
                    {
                        M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA._DOD\n", Zero, Zero, Zero, Zero, Zero, Zero)
                        Return (Package (0x07)
                        {
                            0x00010110, 
                            0x00010210, 
                            0x00010220, 
                            0x00010230, 
                            0x00010240, 
                            0x00031000, 
                            0x00032000
                        })
                    }

                    Device (LCD)
                    {
                        Name (_ADR, 0x0110)  // _ADR: Address
                        Name (BCLB, Package (0x34)
                        {
                            0x5A, 
                            0x3C, 
                            0x02, 
                            0x04, 
                            0x06, 
                            0x08, 
                            0x0A, 
                            0x0C, 
                            0x0E, 
                            0x10, 
                            0x12, 
                            0x14, 
                            0x16, 
                            0x18, 
                            0x1A, 
                            0x1C, 
                            0x1E, 
                            0x20, 
                            0x22, 
                            0x24, 
                            0x26, 
                            0x28, 
                            0x2A, 
                            0x2C, 
                            0x2E, 
                            0x30, 
                            0x32, 
                            0x34, 
                            0x36, 
                            0x38, 
                            0x3A, 
                            0x3C, 
                            0x3E, 
                            0x40, 
                            0x42, 
                            0x44, 
                            0x46, 
                            0x48, 
                            0x4A, 
                            0x4C, 
                            0x4E, 
                            0x50, 
                            0x52, 
                            0x54, 
                            0x56, 
                            0x58, 
                            0x5A, 
                            0x5C, 
                            0x5E, 
                            0x60, 
                            0x62, 
                            0x64
                        })
                        Method (_BCL, 0, NotSerialized)  // _BCL: Brightness Control Levels
                        {
                            M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA.LCD._BCL\n", Zero, Zero, Zero, Zero, Zero, Zero)
                            Return (BCLB) /* \_SB_.PCI0.GPPA.VGA_.LCD_.BCLB */
                        }

                        Method (_BCM, 1, NotSerialized)  // _BCM: Brightness Control Method
                        {
                            M460 ("PLA-ASL-\\_SB.PCI0.GPPA.VGA.LCD._BCM Arg0 = 0x%X\n", ToInteger (Arg0), Zero, Zero, Zero, Zero, Zero)
                            Divide ((Arg0 * 0xFF), 0x64, Local1, Local0)
                            AFN7 (Local0)
                        }
                    }
                }

                Device (PSP)
                {
                    Name (_ADR, 0x02)  // _ADR: Address
                }

                Device (ACP)
                {
                    Name (_ADR, 0x05)  // _ADR: Address
                }

                Device (AZAL)
                {
                    Name (_ADR, 0x06)  // _ADR: Address
                }

                Device (HDAU)
                {
                    Name (_ADR, One)  // _ADR: Address
                }

                Device (XHC1)
                {
                    Name (_ADR, 0x04)  // _ADR: Address
                }

                Device (MP2C)
                {
                    Name (_ADR, 0x07)  // _ADR: Address
                }
            }

            Device (GPPB)
            {
                Name (_ADR, 0x00080002)  // _ADR: Address
                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x2B
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x28
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x29
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x2A
                    }
                })
                Device (IPU)
                {
                    Name (_ADR, One)  // _ADR: Address
                }
            }

            Device (GPPC)
            {
                Name (_ADR, 0x00080003)  // _ADR: Address
                Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
                {
                    If ((Arg0 == ToUUID ("e5c937d0-3553-4d7a-9117-ea4d19c3434d") /* Device Labeling Interface */))
                    {
                        Switch (ToInteger (Arg2))
                        {
                            Case (Zero)
                            {
                                Return (Buffer (One)
                                {
                                     0xFF                                             // .
                                })
                            }
                            Case (0x05)
                            {
                                Return (Zero)
                            }
                            Default
                            {
                                Return (Zero)
                            }

                        }
                    }
                    Else
                    {
                        Return (Buffer (One)
                        {
                             0x00                                             // .
                        })
                    }
                }

                Name (_PRT, Package (0x04)  // _PRT: PCI Routing Table
                {
                    Package (0x04)
                    {
                        0xFFFF, 
                        Zero, 
                        Zero, 
                        0x2F
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        One, 
                        Zero, 
                        0x2C
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x02, 
                        Zero, 
                        0x2D
                    }, 

                    Package (0x04)
                    {
                        0xFFFF, 
                        0x03, 
                        Zero, 
                        0x2E
                    }
                })
                Device (XHC0)
                {
                    Name (_ADR, Zero)  // _ADR: Address
                }

                Device (XHC3)
                {
                    Name (_ADR, 0x03)  // _ADR: Address
                    Device (RHUB)
                    {
                        Name (_ADR, Zero)  // _ADR: Address
                        Device (PRT1)
                        {
                            Name (_ADR, One)  // _ADR: Address
                            Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC3.RHUB.PRT1._UPC\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Local0 = 0x3D
                                If (CondRefOf (\_SB.U4PC))
                                {
                                    If (((U4PC & 0x04) == Zero))
                                    {
                                        Local0 &= 0xFB
                                    }
                                }

                                Return (M602 (One, 0x09, Local0))
                            }

                            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC3.RHUB.PRT1._PLD\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Return (M601 (0x03, One, 0x0301, 0x03, 0x0112, Zero))
                            }
                        }

                        Device (PRT2)
                        {
                            Name (_ADR, 0x02)  // _ADR: Address
                            Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC3.RHUB.PRT2._UPC\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Local0 = 0x3D
                                If (CondRefOf (\_SB.U4PC))
                                {
                                    If (((U4PC & 0x04) == Zero))
                                    {
                                        Local0 &= 0xFB
                                    }
                                }

                                Return (M602 (One, 0x09, Local0))
                            }

                            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC3.RHUB.PRT2._PLD\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Return (M601 (0x03, One, 0x0301, 0x03, 0x0112, Zero))
                            }
                        }
                    }
                }

                Device (XHC4)
                {
                    Name (_ADR, 0x04)  // _ADR: Address
                    Device (RHUB)
                    {
                        Name (_ADR, Zero)  // _ADR: Address
                        Device (PRT1)
                        {
                            Name (_ADR, One)  // _ADR: Address
                            Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC4.RHUB.PRT1._UPC\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Local0 = 0x3D
                                If (CondRefOf (\_SB.U4PC))
                                {
                                    If (((U4PC & 0x04) == Zero))
                                    {
                                        Local0 &= 0xFB
                                    }
                                }

                                Return (M602 (One, 0x09, Local0))
                            }

                            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC4.RHUB.PRT1._PLD\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Return (M601 (0x03, One, 0x0401, 0x03, 0x0112, Zero))
                            }
                        }

                        Device (PRT2)
                        {
                            Name (_ADR, 0x02)  // _ADR: Address
                            Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC4.RHUB.PRT2._UPC\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Local0 = 0x3D
                                If (CondRefOf (\_SB.U4PC))
                                {
                                    If (((U4PC & 0x04) == Zero))
                                    {
                                        Local0 &= 0xFB
                                    }
                                }

                                Return (M602 (One, 0x09, Local0))
                            }

                            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                            {
                                M460 ("PLA-ASL-\\_SB.PCI0.GPPC.XHC4.RHUB.PRT2._PLD\n", Zero, Zero, Zero, Zero, Zero, Zero)
                                Return (M601 (0x03, One, 0x0401, 0x03, 0x0112, Zero))
                            }
                        }
                    }
                }

                Device (NHI0)
                {
                    Name (_ADR, 0x05)  // _ADR: Address
                }

                Device (NHI1)
                {
                    Name (_ADR, 0x06)  // _ADR: Address
                }
            }

            Device (HPET)
            {
                Name (_HID, EisaId ("PNP0103") /* HPET System Timer */)  // _HID: Hardware ID
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                    Return (0x0F)
                }

                Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
                {
                    M460 ("PLA-ASL-\\_SB.PCI0.HPET._CRS\n", Zero, Zero, Zero, Zero, Zero, Zero)
                    Name (BUF0, ResourceTemplate ()
                    {
                        IRQNoFlags ()
                            {0}
                        IRQNoFlags ()
                            {8}
                        Memory32Fixed (ReadOnly,
                            0xFED00000,         // Address Base
                            0x00000400,         // Address Length
                            _Y17)
                    })
                    CreateDWordField (BUF0, \_SB.PCI0.HPET._CRS._Y17._BAS, HPEB)  // _BAS: Base Address
                    Local0 = 0xFED00000
                    HPEB = (Local0 & 0xFFFFFC00)
                    Return (BUF0) /* \_SB_.PCI0.HPET._CRS.BUF0 */
                }
            }

            Device (SMBS)
            {
                Name (_ADR, 0x00140000)  // _ADR: Address
            }

            Scope (SBRG)
            {
                Device (DMAC)
                {
                    Name (_HID, EisaId ("PNP0200") /* PC-class DMA Controller */)  // _HID: Hardware ID
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x0000,             // Range Minimum
                            0x0000,             // Range Maximum
                            0x01,               // Alignment
                            0x10,               // Length
                            )
                        IO (Decode16,
                            0x0081,             // Range Minimum
                            0x0081,             // Range Maximum
                            0x01,               // Alignment
                            0x0F,               // Length
                            )
                        IO (Decode16,
                            0x00C0,             // Range Minimum
                            0x00C0,             // Range Maximum
                            0x01,               // Alignment
                            0x20,               // Length
                            )
                        DMA (Compatibility, NotBusMaster, Transfer8_16, )
                            {4}
                    })
                }

                Device (COPR)
                {
                    Name (_HID, EisaId ("PNP0C04") /* x87-compatible Floating Point Processing Unit */)  // _HID: Hardware ID
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x00F0,             // Range Minimum
                            0x00F0,             // Range Maximum
                            0x01,               // Alignment
                            0x0F,               // Length
                            )
                        IRQNoFlags ()
                            {13}
                    })
                }

                Device (PIC)
                {
                    Name (_HID, EisaId ("PNP0000") /* 8259-compatible Programmable Interrupt Controller */)  // _HID: Hardware ID
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x0020,             // Range Minimum
                            0x0020,             // Range Maximum
                            0x01,               // Alignment
                            0x02,               // Length
                            )
                        IO (Decode16,
                            0x00A0,             // Range Minimum
                            0x00A0,             // Range Maximum
                            0x01,               // Alignment
                            0x02,               // Length
                            )
                        IRQNoFlags ()
                            {2}
                    })
                }

                Device (RTC)
                {
                    Name (_HID, EisaId ("PNP0B00") /* AT Real-Time Clock */)  // _HID: Hardware ID
                    Name (_FIX, Package (0x01)  // _FIX: Fixed Register Resource Provider
                    {
                        0x000BD041
                    })
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x0070,             // Range Minimum
                            0x0070,             // Range Maximum
                            0x01,               // Alignment
                            0x02,               // Length
                            )
                        IO (Decode16,
                            0x0072,             // Range Minimum
                            0x0072,             // Range Maximum
                            0x01,               // Alignment
                            0x02,               // Length
                            )
                    })
                }

                Device (SPKR)
                {
                    Name (_HID, EisaId ("PNP0800") /* Microsoft Sound System Compatible Device */)  // _HID: Hardware ID
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x0061,             // Range Minimum
                            0x0061,             // Range Maximum
                            0x01,               // Alignment
                            0x01,               // Length
                            )
                    })
                }

                Device (TMR)
                {
                    Name (_HID, EisaId ("PNP0100") /* PC-class System Timer */)  // _HID: Hardware ID
                    Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                    {
                        IO (Decode16,
                            0x0040,             // Range Minimum
                            0x0040,             // Range Maximum
                            0x01,               // Alignment
                            0x04,               // Length
                            )
                    })
                }
            }
        }
    }

    Name (TSOS, 0x75)
    Name (HCIB, One)
    Name (I2A0, 0x05)
    Name (I2A1, 0x06)
    Name (I2A2, 0x07)
    Name (I2A3, 0x08)
    Name (UAA0, 0x0B)
    Name (UAA1, 0x0C)
    Name (I3A1, 0x0D)
    Name (I3A2, 0x0E)
    Name (I3A3, 0x0F)
    Name (UAA2, 0x10)
    Name (UAA4, 0x14)
    Name (I3A0, 0x15)
    Name (UAA3, 0x1A)
    If (CondRefOf (\_OSI))
    {
        If (_OSI ("Windows 2009"))
        {
            TSOS = 0x50
        }

        If (_OSI ("Windows 2015"))
        {
            TSOS = 0x70
        }
    }

    Scope (_SB)
    {
        OperationRegion (SMIC, SystemMemory, 0xFED80000, 0x00800000)
        Field (SMIC, ByteAcc, NoLock, Preserve)
        {
            Offset (0x36A), 
            SMIB,   8
        }

        OperationRegion (SSMI, SystemIO, SMIB, 0x02)
        Field (SSMI, AnyAcc, NoLock, Preserve)
        {
            SMIW,   16
        }

        OperationRegion (ECMC, SystemIO, 0x72, 0x02)
        Field (ECMC, AnyAcc, NoLock, Preserve)
        {
            ECMI,   8, 
            ECMD,   8
        }

        IndexField (ECMI, ECMD, ByteAcc, NoLock, Preserve)
        {
            Offset (0x08), 
            FRTB,   32
        }

        OperationRegion (FRTP, SystemMemory, FRTB, 0x0100)
        Field (FRTP, AnyAcc, NoLock, Preserve)
        {
            PEBA,   32, 
            Offset (0x04), 
                ,   5, 
            IC0E,   1, 
            IC1E,   1, 
            IC2E,   1, 
            IC3E,   1, 
            IC4E,   1, 
            IC5E,   1, 
            UT0E,   1, 
            UT1E,   1, 
            I31E,   1, 
            I32E,   1, 
            I33E,   1, 
            UT2E,   1, 
                ,   1, 
            EMMD,   2, 
            UT4E,   1, 
            I30E,   1, 
                ,   1, 
            XHCE,   1, 
                ,   1, 
                ,   1, 
            UT3E,   1, 
            ESPI,   1, 
            EMME,   1, 
            HFPE,   1, 
            HD0E,   1, 
            HD2E,   1, 
            Offset (0x08), 
            PCEF,   1, 
                ,   4, 
            IC0D,   1, 
            IC1D,   1, 
            IC2D,   1, 
            IC3D,   1, 
            IC4D,   1, 
            IC5D,   1, 
            UT0D,   1, 
            UT1D,   1, 
            I31D,   1, 
            I32D,   1, 
            I33D,   1, 
            UT2D,   1, 
                ,   1, 
            EHCD,   1, 
                ,   1, 
            UT4D,   1, 
            I30D,   1, 
                ,   1, 
            XHCD,   1, 
            SD_D,   1, 
                ,   1, 
            UT3D,   1, 
                ,   1, 
            EMD3,   1, 
                ,   1, 
            US4D,   1, 
            S03D,   1, 
            UT0O,   1, 
            UT1O,   1, 
            UT2O,   1, 
            UT3O,   1, 
            Offset (0x1A), 
            I30M,   1, 
            I31M,   1, 
            I32M,   1, 
            I33M,   1, 
            Offset (0x2D), 
            UT0I,   1, 
            UT1I,   1, 
            UT2I,   1, 
            UT3I,   1, 
            UT4I,   1, 
            Offset (0x2E), 
            UL0I,   1, 
            UL1I,   1, 
            UL2I,   1, 
            UL3I,   1
        }

        OperationRegion (FCFG, SystemMemory, PEBA, 0x01000000)
        Field (FCFG, DWordAcc, NoLock, Preserve)
        {
            Offset (0xA3078), 
                ,   2, 
            LDQ0,   1, 
            Offset (0xA30CB), 
                ,   7, 
            AUSS,   1
        }

        OperationRegion (IOMX, SystemMemory, 0xFED80D00, 0x0100)
        Field (IOMX, AnyAcc, NoLock, Preserve)
        {
            Offset (0x15), 
            IM15,   8, 
            Offset (0x16), 
            IM16,   8, 
            Offset (0x1F), 
            IM1F,   8, 
            Offset (0x20), 
            IM20,   8, 
            Offset (0x44), 
            IM44,   8, 
            Offset (0x46), 
            IM46,   8, 
            Offset (0x4A), 
            IM4A,   8, 
            Offset (0x4B), 
            IM4B,   8, 
            Offset (0x57), 
            IM57,   8, 
            Offset (0x58), 
            IM58,   8, 
            Offset (0x68), 
            IM68,   8, 
            Offset (0x69), 
            IM69,   8, 
            Offset (0x6A), 
            IM6A,   8, 
            Offset (0x6B), 
            IM6B,   8, 
            Offset (0x6D), 
            IM6D,   8
        }

        OperationRegion (FACR, SystemMemory, 0xFED81E00, 0x0100)
        Field (FACR, AnyAcc, NoLock, Preserve)
        {
            Offset (0x80), 
                ,   28, 
            RD28,   1, 
                ,   1, 
            RQTY,   1, 
            Offset (0x84), 
                ,   28, 
            SD28,   1, 
                ,   1, 
            Offset (0xA0), 
            PG1A,   1
        }

        OperationRegion (LUIE, SystemMemory, 0xFEDC0020, 0x04)
        Field (LUIE, AnyAcc, NoLock, Preserve)
        {
            IER0,   1, 
            IER1,   1, 
            IER2,   1, 
            IER3,   1, 
            UOL0,   1, 
            UOL1,   1, 
            UOL2,   1, 
            UOL3,   1, 
            WUR0,   2, 
            WUR1,   2, 
            WUR2,   2, 
            WUR3,   2
        }

        Method (FRUI, 1, Serialized)
        {
            If ((Arg0 == Zero))
            {
                Return (IUA0) /* \_SB_.IUA0 */
            }
            ElseIf ((Arg0 == One))
            {
                Return (IUA1) /* \_SB_.IUA1 */
            }
            ElseIf ((Arg0 == 0x02))
            {
                Return (IUA2) /* \_SB_.IUA2 */
            }
            ElseIf ((Arg0 == 0x03))
            {
                Return (IUA3) /* \_SB_.IUA3 */
            }
            Else
            {
                Return (0x03)
            }
        }

        Method (FUIO, 1, Serialized)
        {
            If ((IER0 == One))
            {
                If ((WUR0 == Arg0))
                {
                    Return (Zero)
                }
            }

            If ((IER1 == One))
            {
                If ((WUR1 == Arg0))
                {
                    Return (One)
                }
            }

            If ((IER2 == One))
            {
                If ((WUR2 == Arg0))
                {
                    Return (0x02)
                }
            }

            If ((IER3 == One))
            {
                If ((WUR3 == Arg0))
                {
                    Return (0x03)
                }
            }

            Return (0x0F)
        }

        Method (SRAD, 2, Serialized)
        {
            Local0 = (Arg0 << One)
            Local0 += 0xFED81E40
            OperationRegion (ADCR, SystemMemory, Local0, 0x02)
            Field (ADCR, ByteAcc, NoLock, Preserve)
            {
                ADTD,   2, 
                ADPS,   1, 
                ADPD,   1, 
                ADSO,   1, 
                ADSC,   1, 
                ADSR,   1, 
                ADIS,   1, 
                ADDS,   3
            }

            ADIS = One
            ADSR = Zero
            Stall (Arg1)
            ADSR = One
            ADIS = Zero
            Stall (Arg1)
        }

        Method (DSAD, 2, Serialized)
        {
            Local0 = (Arg0 << One)
            Local0 += 0xFED81E40
            OperationRegion (ADCR, SystemMemory, Local0, 0x02)
            Field (ADCR, ByteAcc, NoLock, Preserve)
            {
                ADTD,   2, 
                ADPS,   1, 
                ADPD,   1, 
                ADSO,   1, 
                ADSC,   1, 
                ADSR,   1, 
                ADIS,   1, 
                ADDS,   3
            }

            If ((Arg1 != ADTD))
            {
                If ((Arg1 == Zero))
                {
                    ADTD = Zero
                    ADPD = One
                    Local0 = ADDS /* \_SB_.DSAD.ADDS */
                    While ((Local0 != 0x07))
                    {
                        Local0 = ADDS /* \_SB_.DSAD.ADDS */
                    }
                }

                If ((Arg1 == 0x03))
                {
                    ADPD = Zero
                    Local0 = ADDS /* \_SB_.DSAD.ADDS */
                    While ((Local0 != Zero))
                    {
                        Local0 = ADDS /* \_SB_.DSAD.ADDS */
                    }

                    ADTD = 0x03
                }
            }
        }

        Method (HSAD, 2, Serialized)
        {
            Local3 = (One << Arg0)
            Local0 = (Arg0 << One)
            Local0 += 0xFED81E40
            OperationRegion (ADCR, SystemMemory, Local0, 0x02)
            Field (ADCR, ByteAcc, NoLock, Preserve)
            {
                ADTD,   2, 
                ADPS,   1, 
                ADPD,   1, 
                ADSO,   1, 
                ADSC,   1, 
                ADSR,   1, 
                ADIS,   1, 
                ADDS,   3
            }

            If ((Arg1 != ADTD))
            {
                If ((Arg1 == Zero))
                {
                    PG1A = One
                    ADTD = Zero
                    ADPD = One
                    Local0 = ADDS /* \_SB_.HSAD.ADDS */
                    While ((Local0 != 0x07))
                    {
                        Local0 = ADDS /* \_SB_.HSAD.ADDS */
                    }

                    RQTY = One
                    RD28 = One
                    Local0 = SD28 /* \_SB_.SD28 */
                    While (!Local0)
                    {
                        Local0 = SD28 /* \_SB_.SD28 */
                    }
                }

                If ((Arg1 == 0x03))
                {
                    RQTY = Zero
                    RD28 = One
                    Local0 = SD28 /* \_SB_.SD28 */
                    While (Local0)
                    {
                        Local0 = SD28 /* \_SB_.SD28 */
                    }

                    ADPD = Zero
                    Local0 = ADDS /* \_SB_.HSAD.ADDS */
                    While ((Local0 != Zero))
                    {
                        Local0 = ADDS /* \_SB_.HSAD.ADDS */
                    }

                    ADTD = 0x03
                    PG1A = Zero
                }
            }
        }

        OperationRegion (FPIC, SystemIO, 0x0C00, 0x02)
        Field (FPIC, AnyAcc, NoLock, Preserve)
        {
            FPII,   8, 
            FPID,   8
        }

        IndexField (FPII, FPID, ByteAcc, NoLock, Preserve)
        {
            Offset (0xF0), 
            IC0I,   8, 
            Offset (0xF1), 
            IC1I,   8, 
            Offset (0xF2), 
            IC2I,   8, 
            Offset (0xF3), 
            IC3I,   8, 
            Offset (0xF4), 
            IUA0,   8, 
            Offset (0xF5), 
            IUA1,   8, 
            Offset (0xF7), 
            IUA4,   8, 
            Offset (0xF8), 
            IUA2,   8, 
            Offset (0xF9), 
            IUA3,   8
        }
    }

    Scope (_SB)
    {
        Device (HFP1)
        {
            Name (_HID, "AMDI0060")  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (HFPE)
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0xFEC11000,         // Address Base
                        0x00000100,         // Address Length
                        )
                })
                Return (RBUF) /* \_SB_.HFP1._CRS.RBUF */
            }
        }

        Device (HID0)
        {
            Name (_HID, "AMDI0063")  // _HID: Hardware ID
            Name (_CID, "PNP0C51")  // _CID: Compatible ID
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (HD0E)
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0xFEC13000,         // Address Base
                        0x00000200,         // Address Length
                        )
                    GpioInt (Edge, ActiveHigh, SharedAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x00AB
                        }
                })
                Return (RBUF) /* \_SB_.HID0._CRS.RBUF */
            }
        }

        Device (HID2)
        {
            Name (_HID, "AMDI0063")  // _HID: Hardware ID
            Name (_CID, "PNP0C51")  // _CID: Compatible ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (HD2E)
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0xFEC12000,         // Address Base
                        0x00000200,         // Address Length
                        )
                    GpioInt (Edge, ActiveHigh, SharedAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x00AB
                        }
                })
                Return (RBUF) /* \_SB_.HID2._CRS.RBUF */
            }
        }

        Device (GPIO)
        {
            Name (_HID, "AMDI0030")  // _HID: Hardware ID
            Name (_CID, "AMDI0030")  // _CID: Compatible ID
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Level, ActiveLow, Shared, ,, )
                    {
                        0x00000007,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFED81500,         // Address Base
                        0x00000400,         // Address Length
                        )
                })
                Return (RBUF) /* \_SB_.GPIO._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((TSOS >= 0x70))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }

        Device (PPKG)
        {
            Name (_HID, "AMDI0052")  // _HID: Hardware ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }
        }
    }

    Scope (_SB)
    {
        Device (FUR0)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If (CondRefOf (UT0O, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return ("AMDI0029")
                    }
                }

                Return ("AMDI0020")
            }

            Name (_UID, "ID00")  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y18)
                    {
                        0x00000003,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDC9000,         // Address Base
                        0x00001000,         // Address Length
                        )
                    Memory32Fixed (ReadWrite,
                        0xFEDC7000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.FUR0._CRS._Y18._INT, IRQW)  // _INT: Interrupts
                IRQW = IUA0 /* \_SB_.IUA0 */
                Return (BUF0) /* \_SB_.FUR0._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((UT0I == One))
                {
                    Return (Zero)
                }

                If ((TSOS >= 0x70))
                {
                    If ((UT0E == One))
                    {
                        If ((FUIO (Zero) == 0x0F))
                        {
                            Return (0x0F)
                        }
                    }
                }

                Return (Zero)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((UT0D && UT0E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((UT0D && UT0E))
                {
                    DSAD (0x0B, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((UT0D && UT0E))
                {
                    DSAD (0x0B, 0x03)
                }
            }
        }

        Device (FUR1)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If (CondRefOf (UT1O, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return ("AMDI0029")
                    }
                }

                Return ("AMDI0020")
            }

            Name (_UID, "ID01")  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y19)
                    {
                        0x00000011,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDCA000,         // Address Base
                        0x00001000,         // Address Length
                        )
                    Memory32Fixed (ReadWrite,
                        0xFEDC8000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.FUR1._CRS._Y19._INT, IRQW)  // _INT: Interrupts
                IRQW = IUA1 /* \_SB_.IUA1 */
                Return (BUF0) /* \_SB_.FUR1._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((UT1I == One))
                {
                    Return (Zero)
                }

                If ((TSOS >= 0x70))
                {
                    If ((UT1E == One))
                    {
                        If ((FUIO (One) == 0x0F))
                        {
                            Return (0x0F)
                        }
                    }
                }

                Return (Zero)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((UT1D && UT1E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((UT1D && UT1E))
                {
                    DSAD (0x0C, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((UT1D && UT1E))
                {
                    DSAD (0x0C, 0x03)
                }
            }
        }

        Device (FUR2)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If (CondRefOf (UT2O, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return ("AMDI0029")
                    }
                }

                Return ("AMDI0020")
            }

            Name (_UID, "ID02")  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1A)
                    {
                        0x00000005,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDCE000,         // Address Base
                        0x00001000,         // Address Length
                        )
                    Memory32Fixed (ReadWrite,
                        0xFEDCC000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.FUR2._CRS._Y1A._INT, IRQW)  // _INT: Interrupts
                IRQW = IUA2 /* \_SB_.IUA2 */
                Return (BUF0) /* \_SB_.FUR2._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((UT2I == One))
                {
                    Return (Zero)
                }

                If ((TSOS >= 0x70))
                {
                    If ((UT2E == One))
                    {
                        If ((FUIO (0x02) == 0x0F))
                        {
                            Return (0x0F)
                        }
                    }
                }

                Return (Zero)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((UT2D && UT2E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((UT2D && UT2E))
                {
                    DSAD (0x10, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((UT2D && UT2E))
                {
                    DSAD (0x10, 0x03)
                }
            }
        }

        Device (FUR3)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If (CondRefOf (UT3O, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return ("AMDI0029")
                    }
                }

                Return ("AMDI0020")
            }

            Name (_UID, "ID03")  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1B)
                    {
                        0x00000012,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDCF000,         // Address Base
                        0x00001000,         // Address Length
                        )
                    Memory32Fixed (ReadWrite,
                        0xFEDCD000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.FUR3._CRS._Y1B._INT, IRQW)  // _INT: Interrupts
                IRQW = IUA3 /* \_SB_.IUA3 */
                Return (BUF0) /* \_SB_.FUR3._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((UT3I == One))
                {
                    Return (Zero)
                }

                If ((TSOS >= 0x70))
                {
                    If ((UT3E == One))
                    {
                        If ((FUIO (0x03) == 0x0F))
                        {
                            Return (0x0F)
                        }
                    }
                }

                Return (Zero)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((UT3D && UT3E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((UT3D && UT3E))
                {
                    DSAD (0x1A, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((UT3D && UT3E))
                {
                    DSAD (0x1A, 0x03)
                }
            }
        }

        Device (FUR4)
        {
            Name (_HID, "AMDI0020")  // _HID: Hardware ID
            Name (_UID, "ID04")  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1C)
                    {
                        0x00000010,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDD1000,         // Address Base
                        0x00001000,         // Address Length
                        )
                    Memory32Fixed (ReadWrite,
                        0xFEDD0000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateByteField (BUF0, \_SB.FUR4._CRS._Y1C._INT, IRQB)  // _INT: Interrupts
                IRQB = IUA4 /* \_SB_.IUA4 */
                Return (BUF0) /* \_SB_.FUR4._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((UT4I == One))
                {
                    Return (Zero)
                }

                If ((TSOS >= 0x70))
                {
                    If ((UT4E == One))
                    {
                        If ((FUIO (0x04) == 0x0F))
                        {
                            Return (0x0F)
                        }
                    }
                }

                Return (Zero)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((UT4D && UT4E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((UT4D && UT4E))
                {
                    DSAD (0x14, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((UT4D && UT4E))
                {
                    DSAD (0x14, 0x03)
                }
            }
        }
    }

    Scope (_SB)
    {
        Device (I2CA)
        {
            Name (_HID, "AMDI0010")  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1D)
                    {
                        0x0000000A,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDC2000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I2CA._CRS._Y1D._INT, IRQW)  // _INT: Interrupts
                IRQW = IC0I /* \_SB_.IC0I */
                Return (BUF0) /* \_SB_.I2CA._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I20I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((IC0E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I2A0, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((IC0D && IC0E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((IC0D && IC0E))
                {
                    DSAD (I2A0, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((IC0D && IC0E))
                {
                    DSAD (I2A0, 0x03)
                }
            }
        }

        Device (I2CB)
        {
            Name (_HID, "AMDI0010")  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1E)
                    {
                        0x0000000B,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDC3000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I2CB._CRS._Y1E._INT, IRQW)  // _INT: Interrupts
                IRQW = IC1I /* \_SB_.IC1I */
                Return (BUF0) /* \_SB_.I2CB._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I21I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((IC1E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I2A1, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((IC1D && IC1E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((IC1D && IC1E))
                {
                    DSAD (I2A1, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((IC1D && IC1E))
                {
                    DSAD (I2A1, 0x03)
                }
            }
        }

        Device (I2CC)
        {
            Name (_HID, "AMDI0010")  // _HID: Hardware ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y1F)
                    {
                        0x00000004,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDC4000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I2CC._CRS._Y1F._INT, IRQW)  // _INT: Interrupts
                IRQW = IC2I /* \_SB_.IC2I */
                Return (BUF0) /* \_SB_.I2CC._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I22I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((IC2E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I2A2, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((IC2D && IC2E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((IC2D && IC2E))
                {
                    DSAD (I2A2, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((IC2D && IC2E))
                {
                    DSAD (I2A2, 0x03)
                }
            }
        }

        Device (I2CD)
        {
            Name (_HID, "AMDI0010")  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y20)
                    {
                        0x00000006,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDC5000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I2CD._CRS._Y20._INT, IRQW)  // _INT: Interrupts
                IRQW = IC3I /* \_SB_.IC3I */
                Return (BUF0) /* \_SB_.I2CD._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I23I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((IC3E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I2A3, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((IC3D && IC3E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((IC3D && IC3E))
                {
                    DSAD (I2A3, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((IC3D && IC3E))
                {
                    DSAD (I2A3, 0x03)
                }
            }
        }
    }

    Scope (_SB.I2CA)
    {
        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("d93e4d1c-58bb-493c-a06a-605a717f9e2e") /* Unknown UUID */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }
                    Case (One)
                    {
                        Return (Buffer (0x04)
                        {
                             0xE5, 0x00, 0x6A, 0x00                           // ..j.
                        })
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB.I2CB)
    {
        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("d93e4d1c-58bb-493c-a06a-605a717f9e2e") /* Unknown UUID */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }
                    Case (One)
                    {
                        Return (Buffer (0x04)
                        {
                             0xE5, 0x00, 0x6A, 0x00                           // ..j.
                        })
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB.I2CC)
    {
        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("d93e4d1c-58bb-493c-a06a-605a717f9e2e") /* Unknown UUID */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }
                    Case (One)
                    {
                        Return (Buffer (0x04)
                        {
                             0xE5, 0x00, 0x6A, 0x00                           // ..j.
                        })
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB.I2CD)
    {
        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("d93e4d1c-58bb-493c-a06a-605a717f9e2e") /* Unknown UUID */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }
                    Case (One)
                    {
                        Return (Buffer (0x04)
                        {
                             0xE5, 0x00, 0x6A, 0x00                           // ..j.
                        })
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB)
    {
        Name (I3ID, "AMDI0015")
        Name (I2ID, "AMDI0016")
        Name (HCID, "AMDI5017")
        Device (I3CA)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If ((I30M == Zero))
                {
                    If (CondRefOf (HCIB))
                    {
                        Return (HCID) /* \_SB_.HCID */
                    }
                    Else
                    {
                        Return (I3ID) /* \_SB_.I3ID */
                    }
                }
                Else
                {
                    Return (I2ID) /* \_SB_.I2ID */
                }
            }

            Name (_UID, Zero)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y21)
                    {
                        0x0000000A,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDD2000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I3CA._CRS._Y21._INT, IRQW)  // _INT: Interrupts
                IRQW = IC0I /* \_SB_.IC0I */
                Return (BUF0) /* \_SB_.I3CA._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I30I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((I30E == One))
                    {
                        Return (0x0F)
                    }

                    Return (Zero)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I3A0, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((I30D && I30E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((I30D && I30E))
                {
                    DSAD (I3A0, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((I30D && I30E))
                {
                    DSAD (I3A0, 0x03)
                }
            }
        }

        Device (I3CB)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If ((I31M == Zero))
                {
                    If (CondRefOf (HCIB))
                    {
                        Return (HCID) /* \_SB_.HCID */
                    }
                    Else
                    {
                        Return (I3ID) /* \_SB_.I3ID */
                    }
                }
                Else
                {
                    Return (I2ID) /* \_SB_.I2ID */
                }
            }

            Name (_UID, One)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y22)
                    {
                        0x0000000B,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDD3000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I3CB._CRS._Y22._INT, IRQW)  // _INT: Interrupts
                IRQW = IC1I /* \_SB_.IC1I */
                Return (BUF0) /* \_SB_.I3CB._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I31I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((I31E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I3A1, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((I31D && I31E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((I31D && I31E))
                {
                    DSAD (I3A1, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((I31D && I31E))
                {
                    DSAD (I3A1, 0x03)
                }
            }
        }

        Device (I3CC)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If ((I32M == Zero))
                {
                    If (CondRefOf (HCIB))
                    {
                        Return (HCID) /* \_SB_.HCID */
                    }
                    Else
                    {
                        Return (I3ID) /* \_SB_.I3ID */
                    }
                }
                Else
                {
                    Return (I2ID) /* \_SB_.I2ID */
                }
            }

            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y23)
                    {
                        0x00000004,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDD4000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I3CC._CRS._Y23._INT, IRQW)  // _INT: Interrupts
                IRQW = IC2I /* \_SB_.IC2I */
                Return (BUF0) /* \_SB_.I3CC._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I32I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((I32E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I3A2, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((I32D && I32E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((I32D && I32E))
                {
                    DSAD (I3A2, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((I32D && I32E))
                {
                    DSAD (I3A2, 0x03)
                }
            }
        }

        Device (I3CD)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If ((I33M == Zero))
                {
                    If (CondRefOf (HCIB))
                    {
                        Return (HCID) /* \_SB_.HCID */
                    }
                    Else
                    {
                        Return (I3ID) /* \_SB_.I3ID */
                    }
                }
                Else
                {
                    Return (I2ID) /* \_SB_.I2ID */
                }
            }

            Name (_UID, 0x03)  // _UID: Unique ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, Exclusive, ,, _Y24)
                    {
                        0x00000006,
                    }
                    Memory32Fixed (ReadWrite,
                        0xFEDD6000,         // Address Base
                        0x00001000,         // Address Length
                        )
                })
                CreateWordField (BUF0, \_SB.I3CD._CRS._Y24._INT, IRQW)  // _INT: Interrupts
                IRQW = IC3I /* \_SB_.IC3I */
                Return (BUF0) /* \_SB_.I3CD._CRS.BUF0 */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (CondRefOf (I33I, Local0))
                {
                    If ((DerefOf (Local0) == One))
                    {
                        Return (Zero)
                    }
                }

                If ((TSOS >= 0x70))
                {
                    If ((I33E == One))
                    {
                        Return (0x0F)
                    }
                }

                Return (Zero)
            }

            Method (RSET, 0, NotSerialized)
            {
                SRAD (I3A3, 0xC8)
            }

            Method (_S0W, 0, NotSerialized)  // _S0W: S0 Device Wake State
            {
                If ((I33D && I33E))
                {
                    Return (0x04)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If ((I33D && I33E))
                {
                    DSAD (I3A3, Zero)
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                If ((I33D && I33E))
                {
                    DSAD (I3A3, 0x03)
                }
            }
        }
    }

    Scope (_SB.I3CA)
    {
        Method (_DSD, 0, Serialized)  // _DSD: Device-Specific Data
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x04)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }, 

                    ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                    Package (0x02)
                    {
                        "mipi-i3c-ctrlr-0-subproperties", 
                        CTR0, 
                    }
                })
            }
        }

        Method (CTR0, 0, Serialized)
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x02)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }
                })
            }
        }
    }

    Scope (_SB.I3CB)
    {
        Method (_DSD, 0, Serialized)  // _DSD: Device-Specific Data
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x04)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }, 

                    ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                    Package (0x02)
                    {
                        "mipi-i3c-ctrlr-0-subproperties", 
                        CTR0, 
                    }
                })
            }
        }

        Method (CTR0, 0, Serialized)
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x02)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }
                })
            }
        }
    }

    Scope (_SB.I3CC)
    {
        Method (_DSD, 0, Serialized)  // _DSD: Device-Specific Data
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x04)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }, 

                    ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                    Package (0x02)
                    {
                        "mipi-i3c-ctrlr-0-subproperties", 
                        CTR0, 
                    }
                })
            }
        }

        Method (CTR0, 0, Serialized)
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x02)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }
                })
            }
        }
    }

    Scope (_SB.I3CD)
    {
        Method (_DSD, 0, Serialized)  // _DSD: Device-Specific Data
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x04)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }, 

                    ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                    Package (0x02)
                    {
                        "mipi-i3c-ctrlr-0-subproperties", 
                        CTR0, 
                    }
                })
            }
        }

        Method (CTR0, 0, Serialized)
        {
            If (CondRefOf (HCIB))
            {
                Return (Package (0x02)
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x02)
                    {
                        "mipi-i3c-sw-interface-revision", 
                        0x00010000
                    }
                })
            }
        }
    }

    Scope (_SB.PCI0)
    {
        Device (UAR1)
        {
            Name (_HID, EisaId ("PNP0500") /* Standard PC COM Serial Port */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_DDN, "COM1")  // _DDN: DOS Device Name
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Local0 = Zero
                Local1 = FUIO (Zero)
                If ((Local1 != 0x0F))
                {
                    Local0 = 0x0F
                }

                If ((UL0I == One))
                {
                    Local0 = Zero
                }

                Return (Local0)
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    IO (Decode16,
                        0x02E8,             // Range Minimum
                        0x02E8,             // Range Maximum
                        0x01,               // Alignment
                        0x08,               // Length
                        _Y25)
                    IRQNoFlags (_Y26)
                        {3}
                })
                CreateByteField (BUF0, \_SB.PCI0.UAR1._CRS._Y25._MIN, IOLO)  // _MIN: Minimum Base Address
                CreateByteField (BUF0, 0x03, IOHI)
                CreateByteField (BUF0, \_SB.PCI0.UAR1._CRS._Y25._MAX, IORL)  // _MAX: Maximum Base Address
                CreateByteField (BUF0, 0x05, IORH)
                CreateWordField (BUF0, \_SB.PCI0.UAR1._CRS._Y26._INT, IRQL)  // _INT: Interrupts
                Local0 = FUIO (Zero)
                Switch (ToInteger (Local0))
                {
                    Case (Zero)
                    {
                        IOLO = 0xE8
                        IOHI = 0x02
                        IORL = 0xE8
                        IORH = 0x02
                    }
                    Case (One)
                    {
                        IOLO = 0xF8
                        IOHI = 0x02
                        IORL = 0xF8
                        IORH = 0x02
                    }
                    Case (0x02)
                    {
                        IOLO = 0xE8
                        IOHI = 0x03
                        IORL = 0xE8
                        IORH = 0x03
                    }
                    Case (0x03)
                    {
                        IOLO = 0xF8
                        IOHI = 0x03
                        IORL = 0xF8
                        IORH = 0x03
                    }

                }

                IRQL = (One << (FRUI (Zero) & 0x0F))
                Return (BUF0) /* \_SB_.PCI0.UAR1._CRS.BUF0 */
            }
        }

        Device (UAR2)
        {
            Name (_HID, EisaId ("PNP0500") /* Standard PC COM Serial Port */)  // _HID: Hardware ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Name (_DDN, "COM2")  // _DDN: DOS Device Name
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Local0 = Zero
                Local1 = FUIO (One)
                If ((Local1 != 0x0F))
                {
                    Local0 = 0x0F
                }

                If ((UL1I == One))
                {
                    Local0 = Zero
                }

                Return (Local0)
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    IO (Decode16,
                        0x02F8,             // Range Minimum
                        0x02F8,             // Range Maximum
                        0x01,               // Alignment
                        0x08,               // Length
                        _Y27)
                    IRQNoFlags (_Y28)
                        {4}
                })
                CreateByteField (BUF0, \_SB.PCI0.UAR2._CRS._Y27._MIN, IOLO)  // _MIN: Minimum Base Address
                CreateByteField (BUF0, 0x03, IOHI)
                CreateByteField (BUF0, \_SB.PCI0.UAR2._CRS._Y27._MAX, IORL)  // _MAX: Maximum Base Address
                CreateByteField (BUF0, 0x05, IORH)
                CreateWordField (BUF0, \_SB.PCI0.UAR2._CRS._Y28._INT, IRQL)  // _INT: Interrupts
                Local0 = FUIO (One)
                Switch (ToInteger (Local0))
                {
                    Case (Zero)
                    {
                        IOLO = 0xE8
                        IOHI = 0x02
                        IORL = 0xE8
                        IORH = 0x02
                    }
                    Case (One)
                    {
                        IOLO = 0xF8
                        IOHI = 0x02
                        IORL = 0xF8
                        IORH = 0x02
                    }
                    Case (0x02)
                    {
                        IOLO = 0xE8
                        IOHI = 0x03
                        IORL = 0xE8
                        IORH = 0x03
                    }
                    Case (0x03)
                    {
                        IOLO = 0xF8
                        IOHI = 0x03
                        IORL = 0xF8
                        IORH = 0x03
                    }

                }

                IRQL = (One << (FRUI (One) & 0x0F))
                Return (BUF0) /* \_SB_.PCI0.UAR2._CRS.BUF0 */
            }
        }

        Device (UAR3)
        {
            Name (_HID, EisaId ("PNP0500") /* Standard PC COM Serial Port */)  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Name (_DDN, "COM3")  // _DDN: DOS Device Name
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Local0 = Zero
                Local1 = FUIO (0x02)
                If ((Local1 != 0x0F))
                {
                    Local0 = 0x0F
                }

                If ((UL2I == One))
                {
                    Local0 = Zero
                }

                Return (Local0)
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    IO (Decode16,
                        0x03E8,             // Range Minimum
                        0x03E8,             // Range Maximum
                        0x01,               // Alignment
                        0x08,               // Length
                        _Y29)
                    IRQNoFlags (_Y2A)
                        {3}
                })
                CreateByteField (BUF0, \_SB.PCI0.UAR3._CRS._Y29._MIN, IOLO)  // _MIN: Minimum Base Address
                CreateByteField (BUF0, 0x03, IOHI)
                CreateByteField (BUF0, \_SB.PCI0.UAR3._CRS._Y29._MAX, IORL)  // _MAX: Maximum Base Address
                CreateByteField (BUF0, 0x05, IORH)
                CreateWordField (BUF0, \_SB.PCI0.UAR3._CRS._Y2A._INT, IRQL)  // _INT: Interrupts
                Local0 = FUIO (0x02)
                Switch (ToInteger (Local0))
                {
                    Case (Zero)
                    {
                        IOLO = 0xE8
                        IOHI = 0x02
                        IORL = 0xE8
                        IORH = 0x02
                    }
                    Case (One)
                    {
                        IOLO = 0xF8
                        IOHI = 0x02
                        IORL = 0xF8
                        IORH = 0x02
                    }
                    Case (0x02)
                    {
                        IOLO = 0xE8
                        IOHI = 0x03
                        IORL = 0xE8
                        IORH = 0x03
                    }
                    Case (0x03)
                    {
                        IOLO = 0xF8
                        IOHI = 0x03
                        IORL = 0xF8
                        IORH = 0x03
                    }

                }

                IRQL = (One << (FRUI (0x02) & 0x0F))
                Return (BUF0) /* \_SB_.PCI0.UAR3._CRS.BUF0 */
            }
        }

        Device (UAR4)
        {
            Name (_HID, EisaId ("PNP0500") /* Standard PC COM Serial Port */)  // _HID: Hardware ID
            Name (_UID, 0x04)  // _UID: Unique ID
            Name (_DDN, "COM4")  // _DDN: DOS Device Name
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Local0 = Zero
                Local1 = FUIO (0x03)
                If ((Local1 != 0x0F))
                {
                    Local0 = 0x0F
                }

                If ((UL3I == One))
                {
                    Local0 = Zero
                }

                Return (Local0)
            }

            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BUF0, ResourceTemplate ()
                {
                    IO (Decode16,
                        0x03F8,             // Range Minimum
                        0x03F8,             // Range Maximum
                        0x01,               // Alignment
                        0x08,               // Length
                        _Y2B)
                    IRQNoFlags (_Y2C)
                        {4}
                })
                CreateByteField (BUF0, \_SB.PCI0.UAR4._CRS._Y2B._MIN, IOLO)  // _MIN: Minimum Base Address
                CreateByteField (BUF0, 0x03, IOHI)
                CreateByteField (BUF0, \_SB.PCI0.UAR4._CRS._Y2B._MAX, IORL)  // _MAX: Maximum Base Address
                CreateByteField (BUF0, 0x05, IORH)
                CreateWordField (BUF0, \_SB.PCI0.UAR4._CRS._Y2C._INT, IRQL)  // _INT: Interrupts
                Local0 = FUIO (0x03)
                Switch (ToInteger (Local0))
                {
                    Case (Zero)
                    {
                        IOLO = 0xE8
                        IOHI = 0x02
                        IORL = 0xE8
                        IORH = 0x02
                    }
                    Case (One)
                    {
                        IOLO = 0xF8
                        IOHI = 0x02
                        IORL = 0xF8
                        IORH = 0x02
                    }
                    Case (0x02)
                    {
                        IOLO = 0xE8
                        IOHI = 0x03
                        IORL = 0xE8
                        IORH = 0x03
                    }
                    Case (0x03)
                    {
                        IOLO = 0xF8
                        IOHI = 0x03
                        IORL = 0xF8
                        IORH = 0x03
                    }

                }

                IRQL = (One << (FRUI (0x03) & 0x0F))
                Return (BUF0) /* \_SB_.PCI0.UAR4._CRS.BUF0 */
            }
        }
    }

    Scope (_SB.I2CA)
    {
        Device (NFC1)
        {
            Name (_HID, EisaId ("NXP8013"))  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0029, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CA",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioInt (Level, ActiveLow, ExclusiveAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x005B
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x004A
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0090
                        }
                })
                Return (RBUF) /* \_SB_.I2CA.NFC1._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (((TPOS >= 0x60) & (NFCS == Zero)))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }

    Scope (_SB.I2CB)
    {
        Device (NFC1)
        {
            Name (_HID, EisaId ("NXP8013"))  // _HID: Hardware ID
            Name (_UID, 0x02)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0029, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CB",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioInt (Level, ActiveLow, ExclusiveAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x005B
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x004A
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0090
                        }
                })
                Return (RBUF) /* \_SB_.I2CB.NFC1._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (((TPOS >= 0x60) & (NFCS == One)))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }

    Scope (_SB.I2CC)
    {
        Device (NFC1)
        {
            Name (_HID, EisaId ("NXP8013"))  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0029, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CC",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioInt (Level, ActiveLow, ExclusiveAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x005B
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x004A
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0090
                        }
                })
                Return (RBUF) /* \_SB_.I2CC.NFC1._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (((TPOS >= 0x60) & (NFCS == 0x02)))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }

    Scope (_SB.I2CD)
    {
        Device (NFC1)
        {
            Name (_HID, EisaId ("NXP8013"))  // _HID: Hardware ID
            Name (_UID, 0x04)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0029, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CD",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioInt (Level, ActiveLow, ExclusiveAndWake, PullNone, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x005B
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x004A
                        }
                    GpioIo (Exclusive, PullNone, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0090
                        }
                })
                Return (RBUF) /* \_SB_.I2CD.NFC1._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (((TPOS >= 0x60) & (NFCS == 0x03)))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }

    Method (SPTS, 1, NotSerialized)
    {
        CLPS = One
        SLPS = One
        PEWS = Zero
    }

    Method (SWAK, 1, NotSerialized)
    {
        PEWS = Zero
        PEWD = Zero
        If (PICM)
        {
            \_SB.DSPI ()
        }

        If (TMSE)
        {
            TMSE = Zero
        }

        If (((Arg0 == 0x03) || (Arg0 == 0x04)))
        {
            If ((\_SB.CMBS == Zero))
            {
                Notify (\_SB.PWRB, 0x02) // Device Wake
            }
            Else
            {
                Notify (\_SB.BTNS, 0x02) // Device Wake
            }
        }
    }

    Device (_SB.TPM)
    {
        Name (TMRQ, 0xFFFFFFFF)
        Name (TLVL, 0xFFFFFFFF)
        Name (HPMB, 0xFE008000)
        Name (HPML, 0x00001000)
        Name (ITRV, 0xFFFFFFFF)
        Name (ILVV, 0xFFFFFFFF)
        Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
        {
            If (TCMF)
            {
                Return (0x01013469)
            }
            ElseIf ((TTDP == Zero))
            {
                Return (0x310CD041)
            }
            Else
            {
                Return ("MSFT0101")
            }
        }

        OperationRegion (TMMB, SystemMemory, 0xFED40000, 0x5000)
        Field (TMMB, ByteAcc, Lock, Preserve)
        {
            ACC0,   8, 
            Offset (0x08), 
            INTE,   32, 
            INTV,   8, 
            Offset (0x10), 
            INTS,   32, 
            INTF,   32, 
            TSTS,   32, 
            Offset (0x24), 
            FIFO,   32, 
            Offset (0x30), 
            IDTF,   32, 
            Offset (0x4C), 
            SCMD,   32
        }

        Method (_STR, 0, NotSerialized)  // _STR: Description String
        {
            If ((TTDP == Zero))
            {
                Return (Unicode ("TPM 1.2 Device"))
            }
            Else
            {
                Return (Unicode ("TPM 2.0 Device"))
            }
        }

        Name (_UID, One)  // _UID: Unique ID
        Name (CRST, ResourceTemplate ()
        {
            Memory32Fixed (ReadOnly,
                0x00000000,         // Address Base
                0x00001000,         // Address Length
                _Y2D)
            Memory32Fixed (ReadOnly,
                0xFED70000,         // Address Base
                0x00001000,         // Address Length
                _Y2E)
        })
        Name (CRSD, ResourceTemplate ()
        {
            Memory32Fixed (ReadWrite,
                0xFED40000,         // Address Base
                0x00005000,         // Address Length
                _Y2F)
        })
        Name (CRID, ResourceTemplate ()
        {
            Memory32Fixed (ReadWrite,
                0xFED40000,         // Address Base
                0x00005000,         // Address Length
                _Y30)
        })
        Name (CREI, ResourceTemplate ()
        {
            Memory32Fixed (ReadWrite,
                0xFED40000,         // Address Base
                0x00005000,         // Address Length
                )
            GpioInt (Level, ActiveLow, ExclusiveAndWake, PullNone, 0x0000,
                "\\_SB.GPIO", 0x00, ResourceConsumer, _Y31,
                )
                {   // Pin list
                    0x0000
                }
        })
        Name (CRSI, ResourceTemplate ()
        {
            Memory32Fixed (ReadWrite,
                0x00000000,         // Address Base
                0x00000000,         // Address Length
                _Y32)
        })
        Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
        {
            If ((AMDT == One))
            {
                CreateDWordField (CRST, \_SB.TPM._Y2D._BAS, MTFB)  // _BAS: Base Address
                CreateDWordField (CRST, \_SB.TPM._Y2D._LEN, LTFB)  // _LEN: Length
                MTFB = TPMB /* \TPMB */
                LTFB = TPBS /* \TPBS */
                CreateDWordField (CRST, \_SB.TPM._Y2E._BAS, MTFC)  // _BAS: Base Address
                CreateDWordField (CRST, \_SB.TPM._Y2E._LEN, LTFC)  // _LEN: Length
                MTFC = TPMC /* \TPMC */
                LTFC = TPCS /* \TPCS */
                Return (CRST) /* \_SB_.TPM_.CRST */
            }
            Else
            {
                If ((DTPT == One))
                {
                    CreateDWordField (CRSD, \_SB.TPM._Y2F._BAS, MTFE)  // _BAS: Base Address
                    CreateDWordField (CRSD, \_SB.TPM._Y2F._LEN, LTFE)  // _LEN: Length
                    MTFE = 0xFED40000
                    LTFE = 0x5000
                    Return (CRSD) /* \_SB_.TPM_.CRSD */
                }
                ElseIf ((TTPF == One))
                {
                    If (((TMRQ == Zero) || (TMRQ == 0xFFFFFFFF)))
                    {
                        CreateDWordField (CRID, \_SB.TPM._Y30._BAS, MTFD)  // _BAS: Base Address
                        CreateDWordField (CRID, \_SB.TPM._Y30._LEN, LTFD)  // _LEN: Length
                        MTFD = 0xFED40000
                        LTFD = 0x5000
                        Return (CRID) /* \_SB_.TPM_.CRID */
                    }
                    Else
                    {
                        CreateWordField (CREI, 0x23, LIRQ)
                        CreateBitField (CREI, \_SB.TPM._Y31._POL, LLVL)  // _POL: Polarity
                        LIRQ = TMRQ /* \_SB_.TPM_.TMRQ */
                        LLVL = TLVL /* \_SB_.TPM_.TLVL */
                        Return (CREI) /* \_SB_.TPM_.CREI */
                    }
                }
                ElseIf ((TTPF == Zero))
                {
                    If ((AMDT == 0x02))
                    {
                        If (((HPMB != Zero) && (HPMB != 0xFFFFFFFF)))
                        {
                            CreateDWordField (CRSI, \_SB.TPM._Y32._BAS, HSPB)  // _BAS: Base Address
                            CreateDWordField (CRSI, \_SB.TPM._Y32._LEN, HSPL)  // _LEN: Length
                            HSPB = HPMB /* \_SB_.TPM_.HPMB */
                            HSPL = HPML /* \_SB_.TPM_.HPML */
                        }

                        Return (CRSI) /* \_SB_.TPM_.CRSI */
                    }

                    CreateDWordField (CRST, \_SB.TPM._Y2E._BAS, MTFF)  // _BAS: Base Address
                    MTFF = FTPM /* \FTPM */
                    Return (CRST) /* \_SB_.TPM_.CRST */
                }

                MTFE = Zero
                LTFE = Zero
                Return (CRID) /* \_SB_.TPM_.CRID */
            }

            Return (CRID) /* \_SB_.TPM_.CRID */
        }

        Method (_SRS, 1, Serialized)  // _SRS: Set Resource Settings
        {
            If (((TMRQ != Zero) && (TMRQ != 0xFFFFFFFF)))
            {
                If ((AMDT == 0x02)){}
                Else
                {
                    CreateWordField (Arg0, 0x23, IRQ0)
                    CreateWordField (CREI, 0x23, LIRQ)
                    LIRQ = IRQ0 /* \_SB_.TPM_._SRS.IRQ0 */
                    TMRQ = IRQ0 /* \_SB_.TPM_._SRS.IRQ0 */
                    CreateBitField (Arg0, 0x98, ITRG)
                    CreateBitField (CREI, \_SB.TPM._Y31._MOD, LTRG)  // _MOD: Mode
                    LTRG = ITRG /* \_SB_.TPM_._SRS.ITRG */
                    ITRV = ITRG /* \_SB_.TPM_._SRS.ITRG */
                    CreateBitField (Arg0, 0x99, ILVL)
                    CreateBitField (CREI, \_SB.TPM._Y31._POL, LLVL)  // _POL: Polarity
                    LLVL = ILVL /* \_SB_.TPM_._SRS.ILVL */
                    ILVV = ILVL /* \_SB_.TPM_._SRS.ILVL */
                }

                If ((((IDTF & 0x0F) == Zero) || ((IDTF & 0x0F
                    ) == 0x0F)))
                {
                    If ((IRQ0 < 0x10))
                    {
                        INTV = (IRQ0 & 0x0F)
                    }

                    If ((ITRV == One))
                    {
                        INTE |= 0x10
                    }
                    Else
                    {
                        INTE &= 0xFFFFFFEF
                    }

                    If ((ILVV == Zero))
                    {
                        INTE |= 0x08
                    }
                    Else
                    {
                        INTE &= 0xFFFFFFF7
                    }
                }
            }
        }

        OperationRegion (CRBD, SystemMemory, TPMM, 0x48)
        Field (CRBD, AnyAcc, NoLock, Preserve)
        {
            Offset (0x04), 
            HERR,   32, 
            Offset (0x40), 
            HCMD,   32, 
            Offset (0x44), 
            HSTS,   32
        }

        Method (_STA, 0, NotSerialized)  // _STA: Status
        {
            If ((TTDP == Zero))
            {
                If (TPMF)
                {
                    Return (0x0F)
                }

                Return (Zero)
            }
            ElseIf ((TTDP == One))
            {
                If (TPMF)
                {
                    Return (0x0F)
                }

                Return (Zero)
            }

            Return (Zero)
        }

        Method (STRT, 3, Serialized)
        {
            OperationRegion (TPMR, SystemMemory, FTPM, 0x1000)
            Field (TPMR, AnyAcc, NoLock, Preserve)
            {
                Offset (0x04), 
                FERR,   32, 
                Offset (0x0C), 
                BEGN,   32
            }

            Name (TIMR, Zero)
            If ((ToInteger (Arg0) != Zero)){}
            Switch (ToInteger (Arg1))
            {
                Case (Zero)
                {
                    Return (Buffer (One)
                    {
                         0x03                                             // .
                    })
                }
                Case (One)
                {
                    TIMR = Zero
                    If ((AMDT == One))
                    {
                        While (((BEGN == One) && (TIMR < 0x0200)))
                        {
                            If ((BEGN == One))
                            {
                                Sleep (One)
                                TIMR++
                            }
                        }
                    }
                    ElseIf ((((HSTS & 0x02) | (HSTS & One)
                        ) == 0x03))
                    {
                        HCMD = One
                    }
                    Else
                    {
                        FERR = One
                        BEGN = Zero
                    }

                    Return (Zero)
                }

            }

            Return (One)
        }

        Method (CRYF, 3, Serialized)
        {
            If ((ToInteger (Arg0) != One)){}
            Switch (ToInteger (Arg1))
            {
                Case (Zero)
                {
                    Return (Buffer (One)
                    {
                         0x03                                             // .
                    })
                }
                Case (One)
                {
                    Name (TPMV, Package (0x02)
                    {
                        One, 
                        Package (0x02)
                        {
                            One, 
                            0x20
                        }
                    })
                    If ((_STA () == Zero))
                    {
                        Return (Package (0x01)
                        {
                            Zero
                        })
                    }

                    Return (TPMV) /* \_SB_.TPM_.CRYF.TPMV */
                }

            }

            Return (Buffer (One)
            {
                 0x00                                             // .
            })
        }
    }

    Scope (_SB.TPM)
    {
        OperationRegion (TSMI, SystemIO, SMIA, 0x02)
        Field (TSMI, WordAcc, NoLock, Preserve)
        {
            SMI,    16
        }

        OperationRegion (ATNV, SystemMemory, PPIM, PPIL)
        Field (ATNV, AnyAcc, NoLock, Preserve)
        {
            RQST,   32, 
            RCNT,   32, 
            ERRO,   32, 
            FLAG,   32, 
            MISC,   32, 
            OPTN,   32, 
            SRSP,   32
        }

        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("3dddfaa6-361b-4eb4-a424-8d10089d1653") /* Physical Presence Interface */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (0x02)
                        {
                             0xFF, 0x01                                       // ..
                        })
                    }
                    Case (One)
                    {
                        If ((PPIV == Zero))
                        {
                            Return ("1.2")
                        }
                        Else
                        {
                            Return ("1.3")
                        }
                    }
                    Case (0x02)
                    {
                        RQST = DerefOf (Arg3 [Zero])
                        SRSP = Zero
                        FLAG = 0x02
                        TMF1 = OFST /* \OFST */
                        SRSP = Zero
                        SMI = TMF1 /* \TMF1 */
                        Return (SRSP) /* \_SB_.TPM_.SRSP */
                    }
                    Case (0x03)
                    {
                        Name (PPI1, Package (0x02)
                        {
                            Zero, 
                            Zero
                        })
                        PPI1 [One] = RQST /* \_SB_.TPM_.RQST */
                        Return (PPI1) /* \_SB_.TPM_._DSM.PPI1 */
                    }
                    Case (0x04)
                    {
                        Return (TRST) /* \TRST */
                    }
                    Case (0x05)
                    {
                        Name (PPI2, Package (0x03)
                        {
                            Zero, 
                            Zero, 
                            Zero
                        })
                        SRSP = Zero
                        FLAG = 0x05
                        SMI = OFST /* \OFST */
                        PPI2 [One] = RCNT /* \_SB_.TPM_.RCNT */
                        PPI2 [0x02] = ERRO /* \_SB_.TPM_.ERRO */
                        Return (PPI2) /* \_SB_.TPM_._DSM.PPI2 */
                    }
                    Case (0x06)
                    {
                        Return (0x03)
                    }
                    Case (0x07)
                    {
                        RQST = DerefOf (Arg3 [Zero])
                        FLAG = 0x07
                        OPTN = Zero
                        If ((RQST == 0x17))
                        {
                            ToInteger (DerefOf (Arg3 [One]), OPTN) /* \_SB_.TPM_.OPTN */
                        }

                        TMF1 = OFST /* \OFST */
                        SRSP = Zero
                        SMI = TMF1 /* \TMF1 */
                        Return (SRSP) /* \_SB_.TPM_.SRSP */
                    }
                    Case (0x08)
                    {
                        RQST = DerefOf (Arg3 [Zero])
                        FLAG = 0x08
                        TMF1 = OFST /* \OFST */
                        SRSP = Zero
                        SMI = TMF1 /* \TMF1 */
                        Return (SRSP) /* \_SB_.TPM_.SRSP */
                    }
                    Default
                    {
                    }

                }
            }
            ElseIf ((Arg0 == ToUUID ("376054ed-cc13-4675-901c-4756d7f2d45d") /* TPM Memory Clear */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x03                                             // .
                        })
                    }
                    Case (One)
                    {
                        RQST = DerefOf (Arg3 [Zero])
                        FLAG = 0x09
                        TMF1 = OFST /* \OFST */
                        SRSP = Zero
                        SMI = TMF1 /* \TMF1 */
                        Return (SRSP) /* \_SB_.TPM_.SRSP */
                    }
                    Default
                    {
                    }

                }
            }

            If ((Arg0 == ToUUID ("cf8e16a5-c1e8-4e25-b712-4f54a96702c8") /* TPM Hardware Information */))
            {
                Return (CRYF (Arg1, Arg2, Arg3))
            }

            If ((Arg0 == ToUUID ("6bbf6cab-5463-4714-b7cd-f0203c0368d4") /* TPM Start Method */))
            {
                Return (STRT (Arg1, Arg2, Arg3))
            }

            Return (Buffer (One)
            {
                 0x00                                             // .
            })
        }

        Method (TPTS, 1, Serialized)
        {
            Switch (ToInteger (Arg0))
            {
                Case (0x04)
                {
                    RQST = Zero
                    FLAG = 0x09
                    SRSP = Zero
                    SMI = OFST /* \OFST */
                }
                Case (0x05)
                {
                    RQST = Zero
                    FLAG = 0x09
                    SRSP = Zero
                    SMI = OFST /* \OFST */
                }

            }

            Sleep (0x012C)
        }
    }

    Scope (_SB.PCI0.GPPA.PSP)
    {
        Name (_HID, EisaId ("PNP0C02") /* PNP Motherboard Resources */)  // _HID: Hardware ID
        Name (PSPB, 0xFD300000)
        Name (PSPL, 0x00100000)
        Name (_STA, 0x0F)  // _STA: Status
        Name (CRS, ResourceTemplate ()
        {
            Memory32Fixed (ReadWrite,
                0x00000000,         // Address Base
                0x00000000,         // Address Length
                _Y33)
        })
        Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
        {
            CreateDWordField (CRS, \_SB.PCI0.GPPA.PSP._Y33._BAS, PBAS)  // _BAS: Base Address
            CreateDWordField (CRS, \_SB.PCI0.GPPA.PSP._Y33._LEN, PLEN)  // _LEN: Length
            PBAS = PSPB /* \_SB_.PCI0.GPPA.PSP_.PSPB */
            PLEN = PSPL /* \_SB_.PCI0.GPPA.PSP_.PSPL */
            Return (CRS) /* \_SB_.PCI0.GPPA.PSP_.CRS_ */
        }
    }

    OperationRegion (EXBU, SystemMemory, 0x6F665A98, 0x016F)
    Field (EXBU, AnyAcc, Lock, Preserve)
    {
        Offset (0x00), 
        FADR,   32, 
        FSIZ,   16, 
        FSTA,   16, 
        FSFN,   8, 
        AMLA,   32, 
        CCNM,   8, 
        FSMI,   8, 
        ALPR,   32, 
        ACPF,   8, 
        ALSP,   8, 
        ALAE,   8, 
        LBTN,   8, 
        KBLC,   8, 
        KBLV,   8, 
        WLDP,   8, 
        BTDP,   8, 
        TPME,   8, 
        INSK,   8, 
        LBLV,   8, 
        LBLS,   8, 
        EDID,   32, 
        WNVA,   32, 
        WNVB,   32, 
        WNVC,   32, 
        WNVD,   32, 
        UMAS,   32, 
        UMAU,   32, 
        APEM,   32, 
        APEC,   32, 
        APEN,   32, 
        CALX,   32, 
        AII0,   32, 
        AII1,   32, 
        AII2,   32, 
        AII3,   32, 
        AII4,   32, 
        UMAM,   32, 
        DGPM,   32, 
        CUMA,   8, 
        AACI,   8, 
        WOSR,   8, 
        UMFG,   8, 
        GPCE,   8, 
        NBFM,   8, 
        GTPM,   8, 
        TPID,   8, 
        EID0,   2048
    }

    Scope (_SB.PCI0.SBRG)
    {
        Device (EC0)
        {
            Name (_HID, EisaId ("PNP0C09") /* Embedded Controller Device */)  // _HID: Hardware ID
            Method (_CRS, 0, Serialized)  // _CRS: Current Resource Settings
            {
                Name (BFFR, ResourceTemplate ()
                {
                    IO (Decode16,
                        0x0062,             // Range Minimum
                        0x0062,             // Range Maximum
                        0x00,               // Alignment
                        0x01,               // Length
                        )
                    IO (Decode16,
                        0x0066,             // Range Minimum
                        0x0066,             // Range Maximum
                        0x00,               // Alignment
                        0x01,               // Length
                        )
                })
                Return (BFFR) /* \_SB_.PCI0.SBRG.EC0_._CRS.BFFR */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }

            Method (S2SC, 1, Serialized)
            {
            }

            Name (_GPE, 0x0A)  // _GPE: General Purpose Events
            Name (ECOK, Zero)
            Name (OKEC, Zero)
            Name (TMPB, Zero)
            Name (TBAT, Zero)
            Name (BATC, Zero)
            Name (BATS, One)
            Name (PDFG, Zero)
            Method (_REG, 2, NotSerialized)  // _REG: Region Availability
            {
                If ((Arg0 == 0x03))
                {
                    ECOK = Arg1
                    OKEC = Arg1
                }

                Notify (LID0, 0x80) // Status Change
            }

            OperationRegion (ERAM, SystemMemory, 0xFEDD8300, 0x0100)
            Field (ERAM, AnyAcc, NoLock, Preserve)
            {
                Offset (0x00), 
                XKTM,   1, 
                FNED,   1, 
                XFFG,   1, 
                FNDI,   1, 
                TPAP,   1, 
                TPFG,   1, 
                WLRY,   1, 
                BHPE,   1, 
                Offset (0x01), 
                CLOT,   8, 
                Offset (0x02), 
                BATM,   8, 
                Offset (0x03), 
                QCHK,   8, 
                Offset (0x06), 
                FTBL,   8, 
                Offset (0x07), 
                WDTC,   8, 
                Offset (0x08), 
                    ,   1, 
                VIUF,   1, 
                    ,   1, 
                    ,   1, 
                BTCN,   1, 
                    ,   1, 
                TCCN,   1, 
                ACIF,   1, 
                Offset (0x09), 
                SHBS,   1, 
                    ,   1, 
                    ,   1, 
                Offset (0x0A), 
                Offset (0x0B), 
                TXAU,   1, 
                    ,   1, 
                    ,   1, 
                    ,   1, 
                BTPN,   1, 
                Offset (0x0C), 
                NDF9,   8, 
                Offset (0x0D), 
                    ,   1, 
                FGA9,   1, 
                    ,   1, 
                    ,   1, 
                QD4F,   1, 
                TGSF,   1, 
                FGWM,   1, 
                NTWF,   1, 
                Offset (0x0E), 
                    ,   1, 
                    ,   1, 
                    ,   1, 
                BACH,   1, 
                DB2F,   1, 
                MD2F,   1, 
                UMAF,   1, 
                APOL,   1, 
                Offset (0x0F), 
                    ,   1, 
                    ,   1, 
                EZBR,   1, 
                LICL,   1, 
                    ,   1, 
                TXAN,   1, 
                SDP0,   1, 
                SDP1,   1, 
                Offset (0x10), 
                Offset (0x12), 
                Offset (0x12), 
                CHKR,   16, 
                Offset (0x14), 
                WS5W,   8, 
                Offset (0x15), 
                FLHB,   8, 
                FLHE,   8, 
                FLHH,   8, 
                Offset (0x18), 
                SMPR,   8, 
                SMST,   8, 
                SMAD,   8, 
                SMCD,   8, 
                Offset (0x1C), 
                SMD0,   32, 
                Offset (0x3C), 
                SMAA,   8, 
                SMAR,   8, 
                SAD0,   8, 
                SAD1,   8, 
                Offset (0x40), 
                DSCT,   8, 
                Offset (0x41), 
                Offset (0x42), 
                Offset (0x42), 
                KID1,   1, 
                KID2,   1, 
                KIDG,   1, 
                MB2W,   1, 
                MB5W,   1, 
                MB8W,   1, 
                LNWP,   1, 
                MEFW,   1, 
                Offset (0x43), 
                Offset (0x44), 
                Offset (0x44), 
                ACIN,   1, 
                RTCF,   1, 
                RVCC,   1, 
                SWIS,   1, 
                LS4F,   1, 
                RVS3,   1, 
                PSAD,   1, 
                WOLN,   1, 
                Offset (0x45), 
                    ,   1, 
                LRFN,   1, 
                    ,   1, 
                CRON,   1, 
                SMTR,   1, 
                CRWK,   1, 
                ASUK,   1, 
                ASDB,   1, 
                Offset (0x46), 
                MBCT,   16, 
                RCAP,   16, 
                MBVT,   16, 
                BTPL,   8, 
                BTPH,   8, 
                Offset (0x50), 
                Offset (0x51), 
                Offset (0x51), 
                TCO1,   1, 
                Offset (0x52), 
                Offset (0x52), 
                PREC,   1, 
                BNEM,   1, 
                SHIP,   1, 
                WLRF,   1, 
                BLPW,   1, 
                LIDS,   1, 
                PWBN,   1, 
                Offset (0x53), 
                Offset (0x53), 
                    ,   7, 
                ECDC,   1, 
                Offset (0x58), 
                CTMP,   8, 
                Offset (0x59), 
                FAND,   1, 
                SDNT,   1, 
                VGAT,   1, 
                GPUM,   1, 
                F2FT,   1, 
                S3LW,   1, 
                BTS4,   1, 
                TRT3,   1, 
                Offset (0x5A), 
                Offset (0x5B), 
                Offset (0x5B), 
                CCDS,   1, 
                BNEL,   1, 
                RFBN,   1, 
                ECOB,   1, 
                KBLO,   1, 
                KBHI,   1, 
                WSVP,   1, 
                WANS,   1, 
                Offset (0x5C), 
                Offset (0x5D), 
                Offset (0x5D), 
                LIDE,   1, 
                Offset (0x5E), 
                NOAC,   1, 
                    ,   3, 
                ASDW,   1, 
                ASDO,   1, 
                TUFA,   2, 
                Offset (0x5F), 
                Offset (0x60), 
                Offset (0x60), 
                FRS3,   16, 
                Offset (0x62), 
                CMAS,   1, 
                    ,   2, 
                UMPF,   1, 
                TCOT,   1, 
                Offset (0x63), 
                Offset (0x63), 
                DBAT,   16, 
                Offset (0x65), 
                CUTE,   8, 
                Offset (0x66), 
                CFR1,   16, 
                CFR2,   16, 
                Offset (0x6A), 
                MDCP,   16, 
                Offset (0x6C), 
                MBCP,   16, 
                Offset (0x6E), 
                BCMR,   16, 
                Offset (0x70), 
                BCME,   1, 
                BMBN,   1, 
                BMBO,   1, 
                Offset (0x71), 
                Offset (0x71), 
                BATI,   1, 
                FBTF,   1, 
                FBTM,   1, 
                PBTC,   1, 
                RBTA,   1, 
                BATL,   1, 
                FBTD,   1, 
                FBFD,   1, 
                Offset (0x72), 
                FBTC,   1, 
                FBTP,   1, 
                FBTH,   1, 
                NILI,   1, 
                BTGW,   1, 
                BICP,   1, 
                BIWC,   1, 
                ATCD,   1, 
                Offset (0x73), 
                CFBH,   1, 
                DFBH,   1, 
                SCHR,   1, 
                NUFB,   1, 
                FBCS,   1, 
                SLIP,   1, 
                BRFL,   1, 
                HCLB,   1, 
                Offset (0x74), 
                PLST,   4, 
                PLAC,   4, 
                Offset (0x75), 
                MBDV,   16, 
                Offset (0x77), 
                RSOC,   8, 
                Offset (0x78), 
                BTMP,   16, 
                Offset (0x7A), 
                RROC,   8, 
                Offset (0x7B), 
                ROCS,   8, 
                Offset (0x7C), 
                NVDX,   8, 
                Offset (0x7D), 
                DTCL,   8, 
                Offset (0x7E), 
                Offset (0x7F), 
                Offset (0x80), 
                LRP1,   16, 
                Offset (0x82), 
                URP1,   16, 
                Offset (0x84), 
                Offset (0x86), 
                Offset (0x86), 
                Offset (0x88), 
                Offset (0x88), 
                Offset (0x8A), 
                Offset (0x8A), 
                Offset (0x8C), 
                Offset (0x8C), 
                ICCG,   16, 
                Offset (0x8E), 
                ICCA,   16, 
                Offset (0x90), 
                CPKP,   1, 
                Offset (0x91), 
                CPKA,   8, 
                Offset (0x92), 
                Offset (0x93), 
                Offset (0x93), 
                OPMS,   8, 
                Offset (0x94), 
                Offset (0x95), 
                Offset (0x96), 
                Offset (0x97), 
                Offset (0x98), 
                Offset (0x99), 
                Offset (0x9A), 
                Offset (0x9A), 
                SOLH,   8, 
                SOLL,   8, 
                Offset (0x9C), 
                SPTH,   8, 
                SPTL,   8, 
                Offset (0x9E), 
                FPTH,   8, 
                FPTL,   8, 
                Offset (0xA0), 
                MMDF,   1, 
                MAMD,   1, 
                MBCM,   1, 
                Offset (0xA1), 
                Offset (0xA2), 
                Offset (0xA2), 
                OBDN,   16, 
                Offset (0xA4), 
                Offset (0xA5), 
                Offset (0xA6), 
                Offset (0xA7), 
                Offset (0xA8), 
                Offset (0xA9), 
                Offset (0xA9), 
                Offset (0xAA), 
                Offset (0xAA), 
                Offset (0xAB), 
                Offset (0xAB), 
                Offset (0xAC), 
                Offset (0xAC), 
                Offset (0xAD), 
                Offset (0xAD), 
                Offset (0xAE), 
                Offset (0xAE), 
                THRP,   8, 
                Offset (0xAF), 
                OSUT,   8, 
                Offset (0xB0), 
                PRAL,   8, 
                Offset (0xB1), 
                PRAH,   8, 
                Offset (0xB2), 
                CORL,   8, 
                Offset (0xB3), 
                CORH,   8, 
                Offset (0xB4), 
                WDTS,   8, 
                Offset (0xB5), 
                SALC,   8, 
                Offset (0xB6), 
                TFWE,   1, 
                TCME,   1, 
                TRTE,   1, 
                TCLE,   1, 
                Offset (0xB7), 
                Offset (0xB7), 
                HBHT,   8, 
                Offset (0xB8), 
                G40C,   1, 
                LRPS,   1, 
                DMUS,   1, 
                PWMD,   1, 
                MNMS,   1, 
                D9FG,   1, 
                CF9F,   1, 
                Offset (0xB9), 
                Offset (0xB9), 
                BAHY,   1, 
                MAAE,   1, 
                MATF,   1, 
                FNSF,   1, 
                FNS2,   1, 
                FNS3,   1, 
                WTAO,   1, 
                AIOB,   1, 
                Offset (0xBA), 
                Offset (0xBB), 
                Offset (0xBB), 
                Offset (0xBC), 
                Offset (0xBC), 
                Offset (0xBD), 
                Offset (0xBD), 
                PDAI,   1, 
                UPDI,   1, 
                U45N,   1, 
                UPEN,   1, 
                UPNN,   1, 
                PONL,   1, 
                    ,   1, 
                MASP,   1, 
                Offset (0xBE), 
                Offset (0xBF), 
                Offset (0xBF), 
                IGNF,   1, 
                VGNF,   1, 
                UGNF,   1, 
                YGNF,   1, 
                ZGNF,   1, 
                    ,   1, 
                NAGU,   1, 
                Offset (0xC0), 
                Offset (0xC0), 
                SARF,   1, 
                GC6S,   1, 
                NOS4,   1, 
                S4UM,   1, 
                SART,   1, 
                M5FG,   2, 
                Offset (0xC1), 
                Offset (0xC1), 
                PODF,   1, 
                TRSC,   1, 
                NVPS,   1, 
                Offset (0xC3), 
                ASEZ,   5, 
                ECAL,   1, 
                BSAL,   1, 
                EZEE,   1, 
                Offset (0xC5), 
                VRTT,   8, 
                Offset (0xC6), 
                VLTT,   8, 
                Offset (0xC7), 
                MSPB,   1, 
                    ,   1, 
                DPFL,   1, 
                ESPP,   1, 
                Offset (0xCA), 
                    ,   1, 
                ACIO,   1, 
                FMAE,   1, 
                    ,   1, 
                ERPF,   1, 
                    ,   1, 
                ARME,   1, 
                Offset (0xCB), 
                Offset (0xCB), 
                Offset (0xCC), 
                Offset (0xCE), 
                BASN,   16, 
                Offset (0xD0), 
                MBDN,   120, 
                DNCT,   8, 
                Offset (0xE0), 
                NMON,   16, 
                CYCL,   16, 
                ECMJ,   8, 
                ECMN,   8, 
                BTCF,   8, 
                BHCH,   8, 
                Offset (0xEA), 
                DBEA,   8, 
                DBEB,   8, 
                Offset (0xEC), 
                DFVH,   8, 
                DFVL,   8, 
                DVMJ,   8, 
                DVMN,   8, 
                Offset (0xF0), 
                MCNT,   8, 
                Offset (0xFC), 
                LCKY,   1, 
                LALT,   1, 
                LPSK,   1, 
                    ,   1, 
                BUKU,   1, 
                Offset (0xFD), 
                Offset (0xFD), 
                CSKS,   8, 
                Offset (0xFE), 
                Offset (0xFF), 
                Offset (0xFF), 
                Offset (0x100)
            }

            OperationRegion (ECDL, SystemIO, 0x62, 0x06)
            Field (ECDL, ByteAcc, Lock, Preserve)
            {
                Offset (0x00), 
                ECDP,   8, 
                Offset (0x04), 
                ECCP,   8
            }

            OperationRegion (IOWT, SystemIO, 0xED, One)
            Field (IOWT, ByteAcc, NoLock, Preserve)
            {
                IODY,   8
            }

            OperationRegion (CMOS, SystemIO, 0x70, 0x04)
            Field (CMOS, ByteAcc, NoLock, Preserve)
            {
                IDX0,   7, 
                Offset (0x01), 
                DAT0,   8, 
                IDX1,   7, 
                Offset (0x03), 
                DAT1,   8
            }

            IndexField (IDX1, DAT1, ByteAcc, NoLock, Preserve)
            {
                Offset (0x40)
            }

            OperationRegion (ERM2, SystemMemory, 0xFEDD8B00, 0x0100)
            Field (ERM2, AnyAcc, NoLock, Preserve)
            {
                Offset (0x00), 
                CTP0,   8, 
                CTP1,   8, 
                CTP2,   8, 
                CTP3,   8, 
                CTP4,   8, 
                CTP5,   8, 
                CTP6,   8, 
                CTP7,   8, 
                SCT0,   8, 
                SCT1,   8, 
                SCT2,   8, 
                SCT3,   8, 
                SCT4,   8, 
                SCT5,   8, 
                SCT6,   8, 
                SCT7,   8, 
                Offset (0x10), 
                GTP0,   8, 
                GTP1,   8, 
                GTP2,   8, 
                GTP3,   8, 
                GTP4,   8, 
                GTP5,   8, 
                GTP6,   8, 
                GTP7,   8, 
                SGT0,   8, 
                SGT1,   8, 
                SGT2,   8, 
                SGT3,   8, 
                SGT4,   8, 
                SGT5,   8, 
                SGT6,   8, 
                SGT7,   8, 
                Offset (0x20), 
                HSBC,   8, 
                HSBL,   8, 
                KBSP,   8, 
                KBIX,   8, 
                Offset (0x24), 
                KBLL,   1, 
                KLMD,   1, 
                    ,   5, 
                KLON,   1, 
                Offset (0x25), 
                KCCP,   8, 
                KCC1,   8, 
                KCC2,   8, 
                Offset (0x28), 
                KBLM,   8, 
                KLDS,   8, 
                KFRI,   8, 
                Offset (0x2B), 
                KBS1,   8, 
                KBS2,   8, 
                KBS3,   8, 
                KBBS,   8, 
                KBMC,   8, 
                Offset (0x3F), 
                SBLD,   8, 
                Offset (0x40), 
                EDAD,   32, 
                Offset (0x44), 
                HBAT,   8, 
                Offset (0x45), 
                CHTF,   8, 
                Offset (0x46), 
                BAY1,   1, 
                BAY2,   1, 
                BAY3,   1, 
                BAY4,   1, 
                Offset (0x47), 
                    ,   1, 
                LRPL,   1, 
                MOLR,   1, 
                    ,   1, 
                MRMS,   1, 
                MGMS,   1, 
                C96F,   1, 
                Offset (0x48), 
                GBLD,   8, 
                Offset (0x4F), 
                WTCN,   8, 
                Offset (0x50), 
                Offset (0x51), 
                Offset (0x52), 
                Offset (0x54), 
                Offset (0x54), 
                Offset (0x55), 
                Offset (0x55), 
                Offset (0x56), 
                Offset (0x56), 
                Offset (0x57), 
                Offset (0x57), 
                Offset (0x58), 
                Offset (0x58), 
                Offset (0x59), 
                Offset (0x59), 
                Offset (0x5A), 
                Offset (0x5A), 
                Offset (0x5B), 
                Offset (0x5B), 
                BTLB,   1, 
                PDGP,   1, 
                BLLB,   1, 
                PDLB,   1, 
                PDAC,   1, 
                DCLL,   1, 
                VATP,   1, 
                DSOF,   1, 
                Offset (0x5C), 
                FNSD,   16, 
                Offset (0x5E), 
                RDFN,   8, 
                Offset (0x5F), 
                Offset (0x60), 
                Offset (0x60), 
                THSN,   120, 
                Offset (0x6F), 
                PDSB,   8, 
                Offset (0x70), 
                Offset (0x71), 
                Offset (0x72), 
                Offset (0x72), 
                THEL,   8, 
                Offset (0x73), 
                DEMT,   8, 
                DEMK,   16, 
                DEMC,   16, 
                Offset (0x78), 
                Offset (0x7C), 
                Offset (0x7C), 
                FRMS,   16, 
                Offset (0x7E), 
                FRS2,   16, 
                Offset (0x80), 
                MDTC,   8, 
                Offset (0x81), 
                GPTT,   8, 
                Offset (0x82), 
                GPSV,   8, 
                Offset (0x83), 
                MALD,   8, 
                MAPB,   8, 
                MAGT,   16, 
                MAED,   8, 
                MARM,   16, 
                Offset (0x8A), 
                PDPB,   8, 
                Offset (0x8C), 
                PDIR,   1, 
                    ,   1, 
                PBTA,   1, 
                PBTB,   1, 
                PBAA,   1, 
                    ,   1, 
                    ,   1, 
                SBPN,   1, 
                Offset (0x8D), 
                Offset (0x8E), 
                Offset (0x8E), 
                Offset (0x8F), 
                Offset (0x8F), 
                Offset (0x90), 
                Offset (0x90), 
                CBD0,   8, 
                CBD1,   8, 
                CBD2,   8, 
                CBD3,   8, 
                CBD4,   8, 
                CBD5,   8, 
                CBD6,   8, 
                CBD7,   8, 
                GBD0,   8, 
                GBD1,   8, 
                GBD2,   8, 
                GBD3,   8, 
                GBD4,   8, 
                GBD5,   8, 
                GBD6,   8, 
                GBD7,   8, 
                Offset (0xA0), 
                CMB0,   8, 
                CMB1,   8, 
                CMB2,   8, 
                CMB3,   8, 
                CMB4,   8, 
                CMB5,   8, 
                CMB6,   8, 
                CMB7,   8, 
                CMB8,   8, 
                CMB9,   8, 
                CMBA,   8, 
                CMBB,   8, 
                CMBC,   8, 
                CMBD,   8, 
                CMBE,   8, 
                CMBF,   8, 
                Offset (0xB0), 
                GMB0,   8, 
                GMB1,   8, 
                GMB2,   8, 
                GMB3,   8, 
                GMB4,   8, 
                GMB5,   8, 
                GMB6,   8, 
                GMB7,   8, 
                GMB8,   8, 
                GMB9,   8, 
                GMBA,   8, 
                GMBB,   8, 
                GMBC,   8, 
                GMBD,   8, 
                GMBE,   8, 
                GMBF,   8, 
                Offset (0xC0), 
                CSB0,   8, 
                CSB1,   8, 
                CSB2,   8, 
                CSB3,   8, 
                CSB4,   8, 
                CSB5,   8, 
                CSB6,   8, 
                CSB7,   8, 
                CSB8,   8, 
                CSB9,   8, 
                CSBA,   8, 
                CSBB,   8, 
                CSBC,   8, 
                CSBD,   8, 
                CSBE,   8, 
                CSBF,   8, 
                Offset (0xD0), 
                GSB0,   8, 
                GSB1,   8, 
                GSB2,   8, 
                GSB3,   8, 
                GSB4,   8, 
                GSB5,   8, 
                GSB6,   8, 
                GSB7,   8, 
                GSB8,   8, 
                GSB9,   8, 
                GSBA,   8, 
                GSBB,   8, 
                GSBC,   8, 
                GSBD,   8, 
                GSBE,   8, 
                GSBF,   8, 
                Offset (0xE0), 
                CTB0,   8, 
                CTB1,   8, 
                CTB2,   8, 
                CTB3,   8, 
                CTB4,   8, 
                CTB5,   8, 
                CTB6,   8, 
                CTB7,   8, 
                CTB8,   8, 
                CTB9,   8, 
                CTBA,   8, 
                CTBB,   8, 
                CTBC,   8, 
                CTBD,   8, 
                CTBE,   8, 
                CTBF,   8, 
                Offset (0xF0), 
                GTB0,   8, 
                GTB1,   8, 
                GTB2,   8, 
                GTB3,   8, 
                GTB4,   8, 
                GTB5,   8, 
                GTB6,   8, 
                GTB7,   8, 
                GTB8,   8, 
                GTB9,   8, 
                GTBA,   8, 
                GTBB,   8, 
                GTBC,   8, 
                GTBD,   8, 
                GTBE,   8, 
                GTBF,   8
            }

            OperationRegion (ERM3, SystemMemory, 0xFEDD8500, 0x0100)
            Field (ERM3, AnyAcc, NoLock, Preserve)
            {
                Offset (0x68), 
                SBD0,   8, 
                SBD1,   8, 
                SBD2,   8, 
                SBD3,   8, 
                SBD4,   8, 
                SBD5,   8, 
                SBD6,   8, 
                SBD7,   8, 
                Offset (0x70), 
                STP0,   8, 
                STP1,   8, 
                STP2,   8, 
                STP3,   8, 
                STP4,   8, 
                STP5,   8, 
                STP6,   8, 
                STP7,   8, 
                SST0,   8, 
                SST1,   8, 
                SST2,   8, 
                SST3,   8, 
                SST4,   8, 
                SST5,   8, 
                SST6,   8, 
                SST7,   8, 
                Offset (0x80), 
                SMB0,   8, 
                SMB1,   8, 
                SMB2,   8, 
                SMB3,   8, 
                SMB4,   8, 
                SMB5,   8, 
                SMB6,   8, 
                SMB7,   8, 
                SMB8,   8, 
                SMB9,   8, 
                SMBA,   8, 
                SMBB,   8, 
                SMBC,   8, 
                SMBD,   8, 
                SMBE,   8, 
                SMBF,   8, 
                Offset (0x90), 
                SSB0,   8, 
                SSB1,   8, 
                SSB2,   8, 
                SSB3,   8, 
                SSB4,   8, 
                SSB5,   8, 
                SSB6,   8, 
                SSB7,   8, 
                SSB8,   8, 
                SSB9,   8, 
                SSBA,   8, 
                SSBB,   8, 
                SSBC,   8, 
                SSBD,   8, 
                SSBE,   8, 
                SSBF,   8, 
                Offset (0xA0), 
                STB0,   8, 
                STB1,   8, 
                STB2,   8, 
                STB3,   8, 
                STB4,   8, 
                STB5,   8, 
                STB6,   8, 
                STB7,   8, 
                STB8,   8, 
                STB9,   8, 
                STBA,   8, 
                STBB,   8, 
                STBC,   8, 
                STBD,   8, 
                STBE,   8, 
                STBF,   8
            }

            OperationRegion (OEDG, SystemMemory, 0xFED81500, 0x03FF)
            Field (OEDG, AnyAcc, NoLock, Preserve)
            {
                Offset (0x1C), 
                    ,   22, 
                HRST,   1, 
                Offset (0x30), 
                    ,   22, 
                PWEB,   1, 
                Offset (0x264), 
                    ,   22, 
                PROL,   1
            }

            OperationRegion (IODC, SystemMemory, 0xFEC20000, 0xFF)
            Field (IODC, AnyAcc, NoLock, Preserve)
            {
                Offset (0x4C), 
                Offset (0x4D), 
                Offset (0x4E), 
                IOS2,   8, 
                IOS3,   8, 
                Offset (0x88), 
                IOS4,   8, 
                IOS5,   8, 
                IOS6,   8, 
                IOS7,   8
            }

            Mutex (MUT0, 0x00)
            Mutex (MUT1, 0x00)
            Name (CNT0, Zero)
            Method (IRDY, 0, NotSerialized)
            {
                CNT0 = Zero
                While ((CNT0 < 0x1770))
                {
                    Local0 = ECCP /* \_SB_.PCI0.SBRG.EC0_.ECCP */
                    If (((Local0 & 0x02) == Zero))
                    {
                        Break
                    }

                    IODY = 0xFF
                    If ((CNT0 == 0x1770))
                    {
                        Local0 = ECDP /* \_SB_.PCI0.SBRG.EC0_.ECDP */
                        IODY = 0xFF
                        CNT0 = Zero
                        While ((CNT0 < 0x03E8))
                        {
                            Local0 = ECCP /* \_SB_.PCI0.SBRG.EC0_.ECCP */
                            If (((Local0 & 0x02) == Zero))
                            {
                                Return (Zero)
                            }

                            IODY = 0xFF
                            CNT0++
                        }
                    }

                    CNT0++
                }
            }

            Method (ORDY, 0, NotSerialized)
            {
                CNT0 = Zero
                While ((CNT0 < 0x1770))
                {
                    Local0 = ECCP /* \_SB_.PCI0.SBRG.EC0_.ECCP */
                    If (((Local0 & One) != Zero))
                    {
                        Local0 = ECDP /* \_SB_.PCI0.SBRG.EC0_.ECDP */
                        Return (Local0)
                    }

                    IODY = 0xFF
                    CNT0++
                }

                Local0 = ECDP /* \_SB_.PCI0.SBRG.EC0_.ECDP */
                Return (Local0)
            }

            Method (ECMD, 1, Serialized)
            {
                Acquire (MUT0, 0x2000)
                IRDY ()
                ECCP = Arg0
                IRDY ()
                Release (MUT0)
            }

            OperationRegion (IO, SystemIO, 0x68, 0x05)
            Field (IO, ByteAcc, Lock, Preserve)
            {
                DAE1,   8, 
                Offset (0x04), 
                CMD1,   8
            }

            Field (IO, ByteAcc, Lock, Preserve)
            {
                Offset (0x04), 
                OUTS,   1, 
                INPS,   1
            }

            Method (ECM1, 3, Serialized)
            {
                Local0 = 0x03E8
                While ((INPS && Local0))
                {
                    Local0--
                    Sleep (One)
                }

                If (Local0)
                {
                    CMD1 = Arg0
                }
                Else
                {
                    Return (Zero)
                }

                If (Arg1)
                {
                    Local0 = 0x03E8
                    While ((INPS && Local0))
                    {
                        Local0--
                        Sleep (One)
                    }

                    If (Local0)
                    {
                        DAE1 = Arg2
                    }
                    Else
                    {
                        Return (Zero)
                    }
                }
            }

            Method (UPHK, 1, Serialized)
            {
                Arg0 &= 0x0F
                If (((Arg0 >= 0x03) && (Arg0 <= 0x08)))
                {
                    Sleep (One)
                    Switch (Arg0)
                    {
                        Case (0x07)
                        {
                            ECM1 (0x98, Zero, Zero)
                        }
                        Case (0x08)
                        {
                            ECM1 (0x86, Zero, Zero)
                        }
                        Default
                        {
                        }

                    }
                }
            }

            Method (BPOL, 0, NotSerialized)
            {
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
                If (OKEC)
                {
                    ECOK = One
                }
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
                ECOK = Zero
            }

            Method (_Q3E, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
            }

            Name (BATO, 0xC0)
            Name (BATN, Zero)
            Name (BATF, 0xC0)
            Method (_Q3F, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x3F
                SELE ()
                ^^^^BAT1.CHBP (BATN)
                If ((0x02 & BATF))
                {
                    Acquire (MUT0, 0x0500)
                    Local0 = NOAC /* \_SB_.PCI0.SBRG.EC0_.NOAC */
                    Local2 = TRSC /* \_SB_.PCI0.SBRG.EC0_.TRSC */
                    Release (MUT0)
                    Notify (ACAD, 0x80) // Status Change
                    Acquire (MUT0, 0x0500)
                    ECDC = One
                    Release (MUT0)
                }

                If ((0x40 & BATF))
                {
                    Notify (BAT1, 0x81) // Information Change
                }

                Notify (BAT1, 0x80) // Status Change
            }

            Method (SELE, 0, NotSerialized)
            {
                Acquire (MUT0, 0x0100)
                BATN = DBAT /* \_SB_.PCI0.SBRG.EC0_.DBAT */
                Release (MUT0)
                BATF = Zero
                If ((0xC0 & BATN))
                {
                    BATF |= One
                }

                If ((0x0C00 & BATN))
                {
                    BATF |= 0x04
                }

                Local0 = (BATN & 0x0F01)
                Local1 = (BATO & 0x0F01)
                If (~(Local0 == Local1))
                {
                    BATF |= 0x40
                }

                Local0 = (BATN & 0xC0)
                Local1 = (BATO & 0xC0)
                If (~(Local0 == Local1))
                {
                    BATF |= 0x02
                }

                If ((0x04 & BATF))
                {
                    BATF |= 0x10
                }

                BATO = BATN /* \_SB_.PCI0.SBRG.EC0_.BATN */
            }

            Method (_Q40, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x40
                Notify (\_TZ.THRM, 0x80) // Thermal Status Change
            }

            Method (_Q41, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x41
                Notify (\_TZ.THRM, 0x80) // Thermal Status Change
            }

            Method (_Q79, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x79
                ^^^^UBTC.QUCM ()
                Notify (UBTC, 0x80) // Status Change
            }

            Method (_QA4, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xA4
                Notify (ACAD, 0x80) // Status Change
            }

            Method (_QCE, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xCE
            }

            Method (_Q84, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x84
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x6E)
                }
            }

            Method (_Q8C, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x8C
                BTPN = Zero
                Notify (BAT1, 0x80) // Status Change
            }

            Method (_QBA, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xBA
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x6E)
                }
            }

            Method (_QB9, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xB9
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x6E)
                }
            }

            Method (_Q85, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x85
                Notify (BAT1, 0x81) // Information Change
            }

            Method (_QAE, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xAE
                ^^^^ATKD.IANE (0xE5)
            }

            Method (_Q2E, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x2E
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x4F)
                }
            }

            Method (_QA6, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xA6
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x4F)
                }
            }

            Method (_QD0, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xD0
                ^^^^ATKD.IANE (0xB8)
            }

            Method (_QD1, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xD1
                ^^^^ATKD.IANE (0xB8)
            }

            Method (_QD7, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xD7
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0xCF)
                }
            }

            Method (_Q0D, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x0D
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x4E)
                }
            }

            Method (_Q21, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0x21
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x7C)
                }
            }

            Method (_QD8, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xD8
                PDAC = Zero
                If (ATKP)
                {
                    Sleep (0xC8)
                    If ((PDAI == One))
                    {
                        ^^^^ATKD.IANE (0x58)
                        ^^^^ATKD.IANE (0xCF)
                    }
                    ElseIf ((UPDI == One))
                    {
                        ^^^^ATKD.IANE (0xCF)
                    }
                    Else
                    {
                        ^^^^ATKD.IANE (0x57)
                        ^^^^ATKD.IANE (0xCF)
                    }

                    ^^^^ATKD.IANE (0x7B)
                }
            }

            Method (_QDB, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xDA
                If (ATKP)
                {
                    BHCH = 0x50
                    ^^^^ATKD.IANE (0xE5)
                }
            }

            Method (_QDC, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xDC
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x68)
                }
            }

            Method (_QDE, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xDE
                FNSF = Zero
                \_TZ.FAN.SFST ()
            }

            Method (_QE0, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xE0
                Notify (\_TZ.THRM, 0x81) // Thermal Trip Point Change
            }

            Method (_QE1, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                DBG8 = 0xE1
                Notify (\_TZ.THRM, 0x80) // Thermal Status Change
            }

            Method (_QE7, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
                Notify (PWRB, 0x80) // Status Change
                Sleep (0x01F4)
                DBG8 = 0xE7
                If (ATKP)
                {
                    ^^^^ATKD.IANE (0x66)
                }
            }

            Method (KBLS, 0, NotSerialized)
            {
                Name (DUBF, Buffer (0x10)
                {
                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
                })
                DUBF [Zero] = One
                DUBF [One] = KBLM /* \_SB_.PCI0.SBRG.EC0_.KBLM */
                DUBF [0x02] = KBS1 /* \_SB_.PCI0.SBRG.EC0_.KBS1 */
                DUBF [0x03] = KBS2 /* \_SB_.PCI0.SBRG.EC0_.KBS2 */
                DUBF [0x04] = KBS3 /* \_SB_.PCI0.SBRG.EC0_.KBS3 */
                DUBF [0x05] = KBSP /* \_SB_.PCI0.SBRG.EC0_.KBSP */
                DUBF [0x06] = KBBS /* \_SB_.PCI0.SBRG.EC0_.KBBS */
                DUBF [0x07] = Zero
                Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.KBLS.DUBF */
            }
        }
    }

    Scope (_SB)
    {
        Device (ATKD)
        {
            Name (_HID, "PNP0C14" /* Windows Management Instrumentation Device */)  // _HID: Hardware ID
            Name (_UID, "ATK")  // _UID: Unique ID
            Name (ATKQ, Package (0x10)
            {
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF, 
                0xFFFFFFFF
            })
            Name (AQHI, Zero)
            Name (AQTI, 0x0F)
            Name (AQNO, Zero)
            Name (WAPF, Zero)
            Name (PCDV, Zero)
            Name (SWKP, Zero)
            Method (IANQ, 1, Serialized)
            {
                P8XH (Zero, 0xD3)
                If ((AQNO >= 0x10))
                {
                    Local0 = 0x64
                    While ((Local0 && (AQNO >= 0x10)))
                    {
                        Local0--
                        Sleep (0x0A)
                    }

                    If ((Local0 && (AQNO >= 0x10)))
                    {
                        Return (Zero)
                    }
                }

                AQTI++
                AQTI &= 0x0F
                ATKQ [AQTI] = Arg0
                AQNO++
                Return (One)
            }

            Method (GANQ, 0, Serialized)
            {
                P8XH (Zero, 0xF2)
                If (AQNO)
                {
                    AQNO--
                    Local0 = DerefOf (ATKQ [AQHI])
                    AQHI++
                    AQHI &= 0x0F
                    Return (Local0)
                }

                Return (Ones)
            }

            Method (IANE, 1, Serialized)
            {
                P8XH (Zero, 0xF1)
                IANQ (Arg0)
                Notify (ATKD, 0xFF) // Hardware-Specific
            }

            Name (_WDG, Buffer (0x3C)
            {
                /* 0000 */  0xD0, 0x5E, 0x84, 0x97, 0x6D, 0x4E, 0xDE, 0x11,  // .^..mN..
                /* 0008 */  0x8A, 0x39, 0x08, 0x00, 0x20, 0x0C, 0x9A, 0x66,  // .9.. ..f
                /* 0010 */  0x4E, 0x42, 0x01, 0x02, 0x35, 0xBB, 0x3C, 0x0B,  // NB..5.<.
                /* 0018 */  0xC2, 0xE3, 0xED, 0x45, 0x91, 0xC2, 0x4C, 0x5A,  // ...E..LZ
                /* 0020 */  0x6D, 0x19, 0x5D, 0x1C, 0xFF, 0x00, 0x01, 0x08,  // m.].....
                /* 0028 */  0x21, 0x12, 0x90, 0x05, 0x66, 0xD5, 0xD1, 0x11,  // !...f...
                /* 0030 */  0xB2, 0xF0, 0x00, 0xA0, 0xC9, 0x06, 0x29, 0x10,  // ......).
                /* 0038 */  0x4D, 0x4F, 0x01, 0x00                           // MO..
            })
            Method (_WED, 1, NotSerialized)  // _Wxx: Wake Event, xx=0x00-0xFF
            {
                If ((Arg0 == 0xFF))
                {
                    Return (GANQ ())
                }

                Return (One)
            }

            Method (INIT, 1, NotSerialized)
            {
                ATKP = One
            }

            Method (SFUN, 0, NotSerialized)
            {
                Local0 = 0x21
                Return (Local0)
            }

            Method (OSVR, 1, NotSerialized)
            {
                OSFG = Arg0
                Return (One)
            }

            Method (SPLV, 1, Serialized)
            {
                Local0 = Arg0
                Switch (Local0)
                {
                    Case (Zero)
                    {
                        Local1 = 0x33
                    }
                    Case (One)
                    {
                        Local1 = 0x40
                    }
                    Case (0x02)
                    {
                        Local1 = 0x4D
                    }
                    Case (0x03)
                    {
                        Local1 = 0x59
                    }
                    Case (0x04)
                    {
                        Local1 = 0x66
                    }
                    Case (0x05)
                    {
                        Local1 = 0x73
                    }
                    Case (0x06)
                    {
                        Local1 = 0x80
                    }
                    Case (0x07)
                    {
                        Local1 = 0x8C
                    }
                    Case (0x08)
                    {
                        Local1 = 0xA6
                    }
                    Case (0x09)
                    {
                        Local1 = 0xCC
                    }
                    Case (0x0A)
                    {
                        Local1 = 0xFF
                    }

                }

                LBTN = Local0
                Return (Local1)
            }

            Method (ANVI, 1, Serialized)
            {
                Return (0xFFFFFFFE)
                FSMI = 0x04
                Return (ASMI (Arg0))
            }
        }
    }

    Scope (_SB.ATKD)
    {
        Method (WMNB, 3, Serialized)
        {
            P8XH (Zero, 0x11)
            CreateDWordField (Arg2, Zero, IIA0)
            CreateDWordField (Arg2, 0x04, IIA1)
            CreateDWordField (Arg2, 0x08, IIA2)
            CreateDWordField (Arg2, 0x0C, IIA3)
            CreateDWordField (Arg2, 0x10, IIA4)
            Local0 = (Arg1 & 0xFFFFFFFF)
            If ((Local0 == 0x54494E49))
            {
                INIT (IIA0)
                Return (One)
            }

            If ((Local0 == 0x53545342))
            {
                Return (BSTS ())
            }

            If ((Local0 == 0x4E554653))
            {
                Return (SFUN ())
            }

            If ((Local0 == 0x47444353))
            {
                Return (SCDG (IIA0, IIA1))
            }

            If ((Local0 == 0x53524556))
            {
                Return (VERS (IIA0, IIA1))
            }

            If ((Local0 == 0x4647574D))
            {
                Return (MWGF (IIA0, IIA1, Local0))
            }

            If ((Local0 == 0x44434C47))
            {
                Return (GLCD ())
            }

            If ((Local0 == 0x474F4457))
            {
                Return (WDOG (IIA0))
            }

            If ((Local0 == 0x5256534F))
            {
                Return (OSVR (IIA0))
            }

            If ((Local0 == 0x49564E41))
            {
                Return (ANVI (IIA0))
            }

            If ((Local0 == 0x53545344))
            {
                If ((IIA0 == 0x00100023))
                {
                    If ((^^PCI0.SBRG.EC0.XKTM == Zero))
                    {
                        Return (0x00010002)
                    }
                    Else
                    {
                        Return (0x00010003)
                    }
                }

                If ((IIA0 == 0x000600C4))
                {
                    WNVA = 0x9605
                    WNVB = 0x000600C4
                    WNVC = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    WNVD = Arg1
                    VBUF [Zero] = W15H ()
                    VBUF [Zero] = WNVA /* \WNVA */
                    Local2 = Zero
                    Local3 = One
                    Local1 = UMAS /* \UMAS */
                    While ((Local3 < 0x0A))
                    {
                        VBUF [Local3] = RMEM ((Local1 + Local2))
                        Local2 += 0x04
                        Local3 += One
                        If (((WNVA == 0x05) && (Local3 == 0x04)))
                        {
                            Local3 = 0x0A
                        }

                        If (((WNVA == 0x07) && (Local3 == 0x05)))
                        {
                            Local3 = 0x0A
                        }
                    }

                    VBUF [One] = UMAU /* \UMAU */
                    Return (VBUF) /* \_SB_.ATKD.VBUF */
                }

                If ((IIA0 == 0x00130031))
                {
                    WNVA = 0x9601
                    WNVB = 0x00130031
                    WNVC = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    WNVD = Zero
                    Return (W15H ())
                }

                If ((IIA0 == 0x001200D2))
                {
                    Return (APEC) /* \APEC */
                }

                If ((IIA0 == 0x001200D3))
                {
                    Return (APEM) /* \APEM */
                }

                If ((IIA0 == 0x001200D4))
                {
                    Return (APEN) /* \APEN */
                }

                If ((IIA0 == 0x000600B1))
                {
                    WNVA = 0x9605
                    WNVB = 0x000600B1
                    WNVC = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    WNVD = Arg1
                    BUFF [Zero] = W15H ()
                    Local2 = Zero
                    Local3 = One
                    Local1 = CALX /* \CALX */
                    While ((Local3 < 0x81))
                    {
                        BUFF [Local3] = RMEM ((Local1 + Local2))
                        Local2 += 0x04
                        Local3 += One
                    }

                    Return (BUFF) /* \_SB_.ATKD.BUFF */
                }

                If ((IIA0 == 0x000600B2))
                {
                    WNVA = 0x9605
                    WNVB = 0x000600B2
                    WNVC = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    WNVD = Arg1
                    BUFF [Zero] = W15H ()
                    Local2 = Zero
                    Local3 = One
                    Local1 = CALX /* \CALX */
                    While ((Local3 < 0x81))
                    {
                        BUFF [Local3] = RMEM ((Local1 + Local2))
                        Local2 += 0x04
                        Local3 += One
                    }

                    Return (BUFF) /* \_SB_.ATKD.BUFF */
                }

                If ((IIA0 == 0x00060024))
                {
                    Return (Package (0x03)
                    {
                        0x8C318086, 
                        One, 
                        0xFFFFFFFF
                    })
                }

                If ((IIA0 == 0x00060025))
                {
                    Return (0xFFFFFFFE)
                    Return (Package (0x03)
                    {
                        0x04, 
                        0x1D00, 
                        0xFFFFFFFF
                    })
                }

                If ((IIA0 == 0x00060094))
                {
                    Local0 = 0x00010000
                    Local0 |= Zero
                    Return (Local0)
                }

                If ((IIA0 == 0x00100051))
                {
                    Return (0x00010001)
                }

                If ((IIA0 == 0x00130015))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00130021))
                {
                    Local0 = 0x00030000
                    Local0 |= 0x02
                    Return (Local0)
                }

                If ((IIA0 == 0x00130022))
                {
                    WNVA = 0x9601
                    WNVB = 0x00130022
                    WNVC = Zero
                    WNVD = Zero
                    Return (W15H ())
                }

                If ((IIA0 == 0x00040017))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00040019))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0004001A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050001))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050013))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050031))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050032))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050033))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050035))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050043))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050051))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060023))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060026))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060059))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060095))
                {
                    Return (0x00010001)
                }

                If ((IIA0 == 0x00080041))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00080042))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00080043))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0009001D))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100053))
                {
                    Return (0xFFFFFFFE)
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100071))
                {
                    Local0 = ^^PCI0.SBRG.EC0.CPKA /* \_SB_.PCI0.SBRG.EC0_.CPKA */
                    Local1 = ^^PCI0.SBRG.EC0.CPKP /* \_SB_.PCI0.SBRG.EC0_.CPKP */
                    Local1 <<= 0x06
                    Local0 |= Local1
                    Local0 |= 0x00010000
                    Return (Local0)
                }

                If ((IIA0 == 0x00100072))
                {
                    Local0 = ^^PCI0.SBRG.EC0.ICCG /* \_SB_.PCI0.SBRG.EC0_.ICCG */
                    Local0 |= 0x00010000
                    Return (Local0)
                }

                If ((IIA0 == 0x0011001E))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120058))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120061))
                {
                    Local0 = ^^PCI0.SBRG.EC0.ACIN /* \_SB_.PCI0.SBRG.EC0_.ACIN */
                    Local1 = ^^PCI0.SBRG.EC0.ACIO /* \_SB_.PCI0.SBRG.EC0_.ACIO */
                    If ((Local0 == One))
                    {
                        If ((Local1 == One))
                        {
                            Return (0x00070002)
                        }
                        Else
                        {
                            Return (0x00070001)
                        }
                    }
                    Else
                    {
                        Return (0x00070000)
                    }
                }

                If ((IIA0 == 0x00120063))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120065))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120082))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120083))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120087))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120088))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200F1))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x00010031))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001F))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050024))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050025))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050026))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00030022))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050036))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005003A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005003B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0006005B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060064))
                {
                    Return (0xFFFFFFFE)
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0006006A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0006006B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060091))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060093))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0009001A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090050))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090051))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090052))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090053))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090054))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100052))
                {
                    Return (0xFFFFFFFE)
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100054))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0010005A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0010005B))
                {
                    Return (^^PCI0.SBRG.EC0.KBLS ())
                }

                If ((IIA0 == 0x0010005C))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100066))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110013))
                {
                    If (^^PCI0.SBRG.EC0.ECOK)
                    {
                        Acquire (^^PCI0.SBRG.EC0.MUT0, 0x1000)
                        Local0 = ^^PCI0.SBRG.EC0.FRMS /* \_SB_.PCI0.SBRG.EC0_.FRMS */
                        Release (^^PCI0.SBRG.EC0.MUT0)
                        If ((Local0 != Zero))
                        {
                            Divide (Local0, 0x64, Local1, Local0)
                        }

                        Local0 |= 0x00010000
                        Return (Local0)
                    }
                }

                If ((IIA0 == 0x00110014))
                {
                    If (^^PCI0.SBRG.EC0.ECOK)
                    {
                        Acquire (^^PCI0.SBRG.EC0.MUT0, 0x1000)
                        Local0 = ^^PCI0.SBRG.EC0.FRS2 /* \_SB_.PCI0.SBRG.EC0_.FRS2 */
                        Release (^^PCI0.SBRG.EC0.MUT0)
                        If ((Local0 != Zero))
                        {
                            Divide (Local0, 0x64, Local1, Local0)
                        }

                        Local0 |= 0x00010000
                        Return (Local0)
                    }
                }

                If ((IIA0 == 0x00110031))
                {
                    If (^^PCI0.SBRG.EC0.ECOK)
                    {
                        Acquire (^^PCI0.SBRG.EC0.MUT0, 0x1000)
                        Local0 = ^^PCI0.SBRG.EC0.FNSD /* \_SB_.PCI0.SBRG.EC0_.FNSD */
                        Release (^^PCI0.SBRG.EC0.MUT0)
                        If ((Local0 != Zero))
                        {
                            Divide (Local0, 0x64, Local1, Local0)
                        }

                        Local0 |= 0x00010000
                        Return (Local0)
                    }
                }

                If ((IIA0 == 0x00110015))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110016))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120058))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120067))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120089))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120090))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001C))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001D))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001E))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005002A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005002E))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050071))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060077))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060095))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C3))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600D2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090017))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090018))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090019))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0009001C))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090021))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090029))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090030))
                {
                    Local1 = 0x00010000
                    If (((M009 (DPDT) == One) & (M009 (HDDT) == One)))
                    {
                        Local1 = 0x00010055
                        Return (Local1)
                    }
                    ElseIf (((M009 (DPDT) == One) & (M009 (HDDT) == Zero)))
                    {
                        Local1 = 0x00010054
                        Return (Local1)
                    }
                    ElseIf (((M009 (DPDT) == Zero) & (M009 (HDDT) == One)))
                    {
                        Local1 = 0x00010051
                        Return (Local1)
                    }
                    Else
                    {
                        Local1 = 0x00010050
                        Return (Local1)
                    }
                }

                If ((IIA0 == 0x00090031))
                {
                    Local0 = ^^PCI0.SBRG.EC0.GPUM /* \_SB_.PCI0.SBRG.EC0_.GPUM */
                    Local1 = ^^PCI0.SBRG.EC0.OPMS /* \_SB_.PCI0.SBRG.EC0_.OPMS */
                    Local1 <<= 0x08
                    Local0 |= Local1
                    Local0 |= 0x00010000
                    Return (Local0)
                }

                If ((IIA0 == 0x00090032))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x00100012))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0010005B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0011001D))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110013))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110014))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0011001B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110024))
                {
                    If ((IIA1 == Zero))
                    {
                        Return (^^PCI0.SBRG.EC0.CFCV ())
                    }

                    If ((IIA1 == One))
                    {
                        Return (^^PCI0.SBRG.EC0.CSFV ())
                    }

                    If ((IIA1 == 0x02))
                    {
                        Return (^^PCI0.SBRG.EC0.CTFV ())
                    }

                    Return (Zero)
                }

                If ((IIA0 == 0x00110025))
                {
                    If ((IIA1 == Zero))
                    {
                        Return (^^PCI0.SBRG.EC0.GFCV ())
                    }

                    If ((IIA1 == One))
                    {
                        Return (^^PCI0.SBRG.EC0.GSCV ())
                    }

                    If ((IIA1 == 0x02))
                    {
                        Return (^^PCI0.SBRG.EC0.GTCV ())
                    }

                    Return (Zero)
                }

                If ((IIA0 == 0x00110026))
                {
                    Return (^^PCI0.SBRG.EC0.CFLB ())
                }

                If ((IIA0 == 0x00110027))
                {
                    Return (^^PCI0.SBRG.EC0.GFLB ())
                }

                If ((IIA0 == 0x00110028))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110029))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110032))
                {
                    If ((IIA1 == Zero))
                    {
                        Return (^^PCI0.SBRG.EC0.SFCV ())
                    }

                    If ((IIA1 == One))
                    {
                        Return (^^PCI0.SBRG.EC0.SSFV ())
                    }

                    If ((IIA1 == 0x02))
                    {
                        Return (^^PCI0.SBRG.EC0.STFV ())
                    }

                    Return (Zero)
                }

                If ((IIA0 == 0x00110033))
                {
                    Return (^^PCI0.SBRG.EC0.SFLB ())
                }

                If ((IIA0 == 0x0012005A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0012005B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0012006C))
                {
                    Local0 = 0x00010000
                    If ((^^PCI0.SBRG.EC0.PDAI == One))
                    {
                        Local0 |= One
                    }

                    If ((^^PCI0.SBRG.EC0.UPDI == One))
                    {
                        Local0 |= 0x02
                    }

                    If ((^^PCI0.SBRG.EC0.UPEN == One))
                    {
                        Local0 |= 0x08
                    }

                    Return (Local0)
                }

                If ((IIA0 == 0x0012006D))
                {
                    Local1 = Zero
                    Local1 |= 0x00010000
                    Local2 = ^^PCI0.SBRG.EC0.TCOT /* \_SB_.PCI0.SBRG.EC0_.TCOT */
                    Local3 = ^^PCI0.SBRG.EC0.TCO1 /* \_SB_.PCI0.SBRG.EC0_.TCO1 */
                    If ((Local2 == One))
                    {
                        Local1 |= Local2
                    }
                    ElseIf ((Local3 == One))
                    {
                        Local1 |= Local3
                    }

                    Return (Local1)
                }

                If ((IIA0 == 0x0012006E))
                {
                    Return (0x00010001)
                }

                If ((IIA0 == 0x00120070))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x00120076))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120077))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120079))
                {
                    Local0 = GSRV (0x00890014)
                    Local0 >>= 0x06
                    Local0 &= 0x01FF
                    If ((Local0 == Zero))
                    {
                        Local2 = Zero
                    }
                    Else
                    {
                        Local0 -= One
                        Local0 *= 0x05
                        Local2 = (Local0 + 0xFA)
                    }

                    Local2 |= 0x00010000
                    Return (Local2)
                }

                If ((IIA0 == 0x0012007B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120080))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120091))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120092))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120093))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120094))
                {
                    Local0 = ^^PCI0.SBRG.EC0.CTMP /* \_SB_.PCI0.SBRG.EC0_.CTMP */
                    Local1 = 0x00010000
                    Local0 |= Local1
                    Return (Local0)
                }

                If ((IIA0 == 0x00120095))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120096))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120098))
                {
                    Local0 = (^^NPCF.ACBT / 0x08)
                    Local0 |= 0x00010000
                    Return (Local0)
                }

                If ((IIA0 == 0x00120099))
                {
                    Local0 = 0x37
                    Local0 |= 0x00010000
                    Return (Local0)
                }

                If ((IIA0 == 0x001200A0))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x001200A1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200A2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200A3))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x001200A4))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200A5))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200B0))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200B1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200C0))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x001200C1))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x001200C2))
                {
                    Return (0x00010000)
                }

                If ((IIA0 == 0x001200C3))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200D1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200E1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200E2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200E4))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00130023))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00130024))
                {
                    Return (Zero)
                }

                If ((IIA0 == 0x00130029))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0013002A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090020))
                {
                    If ((^^PCI0.SBRG.EC0.G40C == Zero))
                    {
                        If ((CUMA == One))
                        {
                            Return (0x00010001)
                        }
                        ElseIf ((CUMA == Zero))
                        {
                            Return (0x00010000)
                        }
                        Else
                        {
                            Return (Zero)
                        }
                    }
                    Else
                    {
                        Return (0x00010000)
                    }
                }

                If ((IIA0 == 0x00090016))
                {
                    Return (DGPM) /* \DGPM */
                }

                If ((IIA0 == 0x00130026))
                {
                    Local0 = 0x00010000
                    Local0 |= One
                    Return (Local0)
                }

                If (WCHK (Zero, IIA0))
                {
                    WNVA = 0x9603
                    WNVB = 0x02
                    WNVC = IIA0 /* \_SB_.ATKD.WMNB.IIA0 */
                    AII0 = IIA0 /* \_SB_.ATKD.WMNB.IIA0 */
                    AII1 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    AII2 = IIA2 /* \_SB_.ATKD.WMNB.IIA2 */
                    AII3 = IIA3 /* \_SB_.ATKD.WMNB.IIA3 */
                    AII4 = IIA4 /* \_SB_.ATKD.WMNB.IIA4 */
                    Return (W15H ())
                }

                Return (0xFFFFFFFE)
            }

            If ((Local0 == 0x53564544))
            {
                If ((IIA0 == 0x00100023))
                {
                    Return (One)
                }

                If ((IIA0 == 0x00050011))
                {
                    If ((IIA1 == 0x02))
                    {
                        BLCT = One
                    }
                    Else
                    {
                        BLCT = Zero
                    }
                }

                If ((IIA0 == 0x00100021))
                {
                    Return (^^PCI0.SBRG.EC0.SKEY (IIA1))
                }

                If ((IIA0 == 0x00130022))
                {
                    WNVA = 0x9602
                    WNVB = 0x00130022
                    WNVC = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    WNVD = Zero
                    Return (W15H ())
                }

                If ((IIA0 == 0x00040017))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00040019))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050001))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050013))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050031))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050032))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050035))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060023))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060026))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0009001D))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100021))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100066))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100071))
                {
                    Local0 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    Local0 &= 0x3F
                    If ((Local0 == Zero))
                    {
                        Return (Zero)
                    }

                    ^^PCI0.SBRG.EC0.CPKA = Local0
                    Return (One)
                }

                If ((IIA0 == 0x00100072))
                {
                    Local0 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    Local0 &= 0xFFFF
                    If ((Local0 == Zero))
                    {
                        Return (Zero)
                    }

                    ^^PCI0.SBRG.EC0.ICCA = Local0
                    Return (One)
                }

                If ((IIA0 == 0x0011001E))
                {
                    Return (Zero)
                }

                If ((IIA0 == 0x00120058))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200F1))
                {
                    Local0 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    Local0 &= One
                    If ((Local0 == Zero))
                    {
                        ^^PCI0.SBRG.EC0.LICL = Zero
                    }
                    Else
                    {
                        ^^PCI0.SBRG.EC0.LICL = One
                    }

                    Return (One)
                }

                If ((IIA0 == 0x00010031))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050024))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050025))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050026))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00030022))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050036))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060064))
                {
                    Return (0xFFFFFFFE)
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060091))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0009001A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090040))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090050))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090051))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090052))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090053))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090054))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100052))
                {
                    Return (0xFFFFFFFE)
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100054))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110013))
                {
                    If (^^PCI0.SBRG.EC0.ECOK)
                    {
                        Acquire (^^PCI0.SBRG.EC0.MUT0, 0x1000)
                        Local0 = ^^PCI0.SBRG.EC0.FTBL /* \_SB_.PCI0.SBRG.EC0_.FTBL */
                        Release (^^PCI0.SBRG.EC0.MUT0)
                        If ((Local0 == Zero))
                        {
                            Arg1 = Zero
                        }

                        Arg1 = One
                    }

                    Return (One)
                }

                If ((IIA0 == 0x00110015))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110016))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110041))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120074))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120000))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120089))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00130025))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0xC0400000))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0xC0400001))
                {
                    Return (0xFFFFFFFE)
                }

                Name (UTDP, Buffer (0x08){})
                CreateWordField (UTDP, Zero, M254)
                CreateByteField (UTDP, 0x02, M255)
                CreateDWordField (UTDP, 0x03, M256)
                M254 = 0x07
                If ((IIA0 == 0x0005001C))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001D))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005001E))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005002A))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0005002E))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00050071))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00060097))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600C3))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x000600D2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090019))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090029))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00090031))
                {
                    Local0 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    Local1 = (Local0 & 0xFFFF)
                    Local2 = (Local0 & One)
                    ^^PCI0.SBRG.EC0.GPUM = Local2
                    Local3 = (Local0 & 0xFF00)
                    Local3 >>= 0x08
                    ^^PCI0.SBRG.EC0.OPMS = Local3
                    Return (One)
                }

                If ((IIA0 == 0x00090032))
                {
                    If ((IIA1 == One))
                    {
                        ^^PCI0.SBRG.EC0.UMPF = One
                    }
                    Else
                    {
                        ^^PCI0.SBRG.EC0.UMPF = Zero
                    }

                    Return (One)
                }

                If ((IIA0 == 0x00090041))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00100012))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110024))
                {
                    ^^PCI0.SBRG.EC0.FMAE = One
                    ^^PCI0.SBRG.EC0.SFTC (IIA1, IIA2, IIA3, IIA4)
                    ^^PCI0.SBRG.EC0.SMSM ()
                    Notify (NPCF, 0xC0) // Hardware-Specific
                    Return (One)
                }

                If ((IIA0 == 0x00110025))
                {
                    ^^PCI0.SBRG.EC0.SFTG (IIA1, IIA2, IIA3, IIA4)
                    Return (One)
                }

                If ((IIA0 == 0x00110028))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00110032))
                {
                    ^^PCI0.SBRG.EC0.SFTS (IIA1, IIA2, IIA3, IIA4)
                    Return (One)
                }

                If ((IIA0 == 0x0012005B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120070))
                {
                    Local0 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    Local0 &= One
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0500)
                    ^^PCI0.SBRG.EC0.MSPB = Local0
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    Return (One)
                }

                If ((IIA0 == 0x00120076))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120080))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120092))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120095))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00120098))
                {
                    Local0 = (IIA1 * 0x08)
                    ^^NPCF.ACBT = Local0
                    Notify (NPCF, 0xC0) // Hardware-Specific
                    Return (One)
                }

                If ((IIA0 == 0x001200A0))
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0500)
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    M255 = 0x07
                    M256 = (IIA1 * 0x03E8)
                    ALIB (0x0C, UTDP)
                    Sleep (0x14)
                    Return (One)
                }

                If ((IIA0 == 0x001200A1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200A2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200A3))
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0500)
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    M255 = 0x05
                    M256 = (IIA1 * 0x03E8)
                    ALIB (0x0C, UTDP)
                    Sleep (0x14)
                    Return (One)
                }

                If ((IIA0 == 0x001200B0))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200B1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200C0))
                {
                    NBFM = One
                    If ((IIA1 < 0x05))
                    {
                        ^^NPCF.DBAC = One
                        ^^NPCF.DBDC = One
                        ^^NPCF.AMAT = Zero
                    }
                    Else
                    {
                        ^^NPCF.DBAC = Zero
                        ^^NPCF.DBDC = Zero
                        Local0 = (IIA1 << 0x03)
                        If ((Local0 != ^^NPCF.AMAT))
                        {
                            ^^NPCF.AMAT = Local0
                        }
                    }

                    Notify (NPCF, 0xC0) // Hardware-Specific
                    Return (One)
                }

                If ((IIA0 == 0x001200C1))
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0500)
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    M255 = 0x06
                    M256 = (IIA1 * 0x03E8)
                    ALIB (0x0C, UTDP)
                    Sleep (0x14)
                    Return (One)
                }

                If ((IIA0 == 0x001200C2))
                {
                    NBFM = One
                    GTPM = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    ^^PCI0.GPP9.PEGP.NLIM = One
                    ^^PCI0.GPP9.PEGP.TGPU = GTPM /* \GTPM */
                    Notify (^^PCI0.GPP9.PEGP, 0xC0) // Hardware-Specific
                    Return (One)
                }

                If ((IIA0 == 0x00130024))
                {
                    Return (Zero)
                }

                If ((IIA0 == 0x00060095))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x0012007B))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200E1))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x001200E2))
                {
                    Return (0xFFFFFFFE)
                }

                If ((IIA0 == 0x00130014))
                {
                    Return (Zero)
                }

                If ((IIA0 == 0x00090020))
                {
                    CUMA = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    If ((IIA1 == One))
                    {
                        ^^PCI0.SBRG.EC0.PREC = One
                        WOSR = One
                        GPCE = One
                        Notify (^^PCI0.GPP9.PEGP, 0x81) // Information Change
                        ^^PCI0.SBRG.EC0.UMAF = One
                        Notify (^^PCI0.GPP9.PEGP, 0x03) // Eject Request
                        If ((^^PCI0.SBRG.EC0.WAT1 () == One))
                        {
                            GPCE = Zero
                            Return (Zero)
                        }

                        GPCE = Zero
                        ^^PCI0.SBRG.EC0.PWMD = Zero
                    }

                    If ((IIA1 == Zero))
                    {
                        ^^PCI0.SBRG.EC0.PREC = Zero
                        ^^PCI0.SBRG.EC0.UMAF = Zero
                        UMFG = Zero
                        GPCE = 0x02
                        Notify (^^PCI0.GPP9.PEGP, Zero) // Bus Check
                        ^^PCI0.SBRG.EC0.FGA9 = One
                        If ((^^PCI0.SBRG.EC0.WAT2 () == One))
                        {
                            GPCE = Zero
                            Return (Zero)
                        }

                        GPCE = Zero
                        Sleep (0x07D0)
                        While ((^^PCI0.SBRG.EC0.NVPS == One))
                        {
                            Sleep (0x64)
                        }

                        ^^PCI0.SBRG.EC0.PWMD = One
                    }

                    Return (One)
                }

                If (WCHK (One, IIA0))
                {
                    WNVA = 0x9603
                    WNVB = 0x03
                    WNVC = IIA0 /* \_SB_.ATKD.WMNB.IIA0 */
                    AII0 = IIA0 /* \_SB_.ATKD.WMNB.IIA0 */
                    AII1 = IIA1 /* \_SB_.ATKD.WMNB.IIA1 */
                    AII2 = IIA2 /* \_SB_.ATKD.WMNB.IIA2 */
                    AII3 = IIA3 /* \_SB_.ATKD.WMNB.IIA3 */
                    AII4 = IIA4 /* \_SB_.ATKD.WMNB.IIA4 */
                    Return (W15H ())
                }

                Return (0xFFFFFFFE)
            }

            Return (0xFFFFFFFE)
        }
    }

    Scope (_SB)
    {
        Mutex (MSMI, 0x00)
        Method (W15H, 0, NotSerialized)
        {
            Acquire (MSMI, 0xFFFF)
            WSCP = 0xAA
            Release (MSMI)
            Return (WNVA) /* \WNVA */
        }
    }

    Scope (_SB.ATKD)
    {
        Name (VBUF, Package (0x0A)
        {
            0x0B, 
            0xFFFFFFFF, 
            Zero, 
            Zero, 
            Zero, 
            Zero, 
            Zero, 
            Zero, 
            Zero, 
            Zero
        })
    }

    Scope (_SB)
    {
        Name (ATKP, Zero)
        Name (AITM, Zero)
        Name (PLMD, Zero)
        Name (MUTX, One)
        Name (LEDS, Zero)
        Name (PWKY, Zero)
        Name (BLCT, Zero)
        OperationRegion (WSMI, SystemIO, 0xB2, 0x02)
        Field (WSMI, ByteAcc, NoLock, Preserve)
        {
            WSCP,   8, 
            WSSP,   8
        }

        Mutex (MMTX, 0x00)
        Method (WISM, 1, NotSerialized)
        {
            Acquire (MMTX, 0xFFFF)
            WSCP = Arg0
            Release (MMTX)
        }

        Method (ASMI, 1, Serialized)
        {
            ALPR = Arg0
            WSCP = EXSI /* \EXSI */
            Return (ALPR) /* \ALPR */
        }
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (QLIB, 1, Serialized)
        {
            Switch (Arg0)
            {
                Case (0x15)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x7C)
                    }
                }
                Case (0x24)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x99)
                    }
                }
                Case (0x25)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xAE)
                    }
                }
                Case (One)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        S2SC (0xE0)
                        S2SC (0x20)
                        S2SC (0xE0)
                        S2SC (0xA0)
                    }
                }
                Case (0x02)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        S2SC (0xE0)
                        S2SC (0x2E)
                        S2SC (0xE0)
                        S2SC (0xAE)
                    }
                }
                Case (0x03)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        S2SC (0xE0)
                        S2SC (0x30)
                        S2SC (0xE0)
                        S2SC (0xB0)
                    }
                }
                Case (0x09)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x40)
                    }
                }
                Case (0x0A)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x0A)
                    }
                }
                Case (0x0B)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x43)
                    }
                }
                Case (0x0C)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x45)
                    }
                }
                Case (0x22)
                {
                    Notify (SLPB, 0x80) // Status Change
                }
                Case (0x17)
                {
                    If (ATKP)
                    {
                        Local1 = (KBLC & 0x80)
                        If (Local1)
                        {
                            ^^^^ATKD.IANE (0xC4)
                        }
                    }
                }
                Case (0x16)
                {
                    If (ATKP)
                    {
                        Local1 = (KBLC & 0x80)
                        If (Local1)
                        {
                            ^^^^ATKD.IANE (0xC5)
                        }
                    }
                }
                Case (0x1A)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x1A)
                    }
                }
                Case (0x19)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xB3)
                    }
                }
                Case (0x27)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        BRTN (0x86)
                    }
                }
                Case (0x26)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        BRTN (0x87)
                    }
                }
                Case (0x28)
                {
                    If ((BLCT == Zero)){}
                    ElseIf ((BLCT == One)){}
                }
                Case (0x29)
                {
                    If ((OSYS >= 0x07DC))
                    {
                        If ((F8FG == Zero))
                        {
                            F8FG = One
                            S2SC (0xE0)
                            S2SC (0x5B)
                        }

                        S2SC (0x19)
                        S2SC (0x99)
                        Return (One)
                    }

                    If ((OSYS == 0x07D9))
                    {
                        If ((^^^^ATKD.SWKP == One))
                        {
                            S2SC (0xE0)
                            S2SC (0x5B)
                            S2SC (0x19)
                            S2SC (0x99)
                            Return (One)
                        }
                    }
                }
                Case (0x2A)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x6B)
                    }
                }
                Case (0x2B)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x88)
                    }
                }
                Case (0x2C)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x8A)
                    }
                }
                Case (0x2D)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x82)
                    }
                }
                Case (0x2E)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xB5)
                    }
                }
                Case (0x33)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x7A)
                    }
                }
                Case (0x30)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x9E)
                    }
                }
                Case (0x32)
                {
                }
                Case (0x34)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x9D)
                    }
                }
                Case (0x35)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xCA)
                    }
                }
                Case (0x36)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xCB)
                    }
                }
                Case (0x37)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x86)
                    }
                }
                Case (0xCF)
                {
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xCF)
                    }
                }

            }
        }
    }

    Name (FNF8, Zero)
    Scope (_SB.PCI0.SBRG.EC0)
    {
        Name (HDMI, Zero)
        Name (F8FG, Zero)
        Method (_Q2F, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            Notify (LID0, 0x80) // Status Change
        }

        Method (_Q65, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            If (ATKP)
            {
                ^^^^ATKD.IANE (0x67)
            }
        }
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (_Q76, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x77
            If (ATKP)
            {
                Local1 = (KBLC & 0x80)
                If (Local1)
                {
                    ^^^^ATKD.IANE (0xC5)
                }
            }
        }

        Method (_Q77, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x76
            If (ATKP)
            {
                Local1 = (KBLC & 0x80)
                If (Local1)
                {
                    ^^^^ATKD.IANE (0xC4)
                }
            }
        }

        Method (_QD6, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0xD6
            If (ATKP)
            {
                ^^^^ATKD.IANE (0xB3)
            }
        }

        Method (_QB5, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x15
            QLIB (0x25)
        }

        Method (_Q18, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x17
            QLIB (0x26)
        }

        Method (_Q17, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x18
            QLIB (0x27)
        }

        Method (_Q22, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x22
            Acquire (MUT0, 0x0500)
            TPFG = One
            Release (MUT0)
            QLIB (0x2A)
        }

        Method (_Q31, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x1B
            QLIB (0x22)
        }

        Method (_QAF, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x1C
            QLIB (0x2B)
        }

        Method (_QB8, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x20
            QLIB (0x2E)
        }
    }

    Method (_QDA, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
    {
        \_SB.PCI0.SBRG.EC0.QLIB (0xCF)
    }

    Scope (_SB.ATKD)
    {
        Method (RMEM, 1, NotSerialized)
        {
            OperationRegion (VMEM, SystemMemory, Arg0, 0x04)
            Field (VMEM, ByteAcc, NoLock, Preserve)
            {
                MEMI,   32
            }

            Local0 = MEMI /* \_SB_.ATKD.RMEM.MEMI */
            Return (Local0)
        }

        Name (BUFF, Package (0x81)
        {
            0x0200, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF, 
            0xFFFFFFFF
        })
        Method (SCDG, 2, Serialized)
        {
            WNVA = 0x9605
            WNVB = 0x47444353
            WNVC = Arg0
            WNVD = Arg1
            BUFF [Zero] = W15H ()
            Local2 = Zero
            Local3 = One
            Local1 = CALX /* \CALX */
            While ((Local3 < 0x81))
            {
                BUFF [Local3] = RMEM ((Local1 + Local2))
                Local2 += 0x04
                Local3 += One
            }

            Return (BUFF) /* \_SB_.ATKD.BUFF */
        }
    }

    Scope (_SB.ATKD)
    {
        Method (VERS, 2, Serialized)
        {
            Local0 = 0x0200
            Local0 += 0x11
            Return (Local0)
        }
    }

    Scope (_SB.ATKD)
    {
        Method (OFBD, 1, NotSerialized)
        {
            Name (FBDT, Package (0x53)
            {
                0x88, 
                0x89, 
                0x8A, 
                0x8B, 
                0x8C, 
                0x8D, 
                0x8E, 
                0x8F, 
                0x70, 
                0x71, 
                0x72, 
                0x73, 
                0x74, 
                0x75, 
                0x76, 
                0x77, 
                0x78, 
                0x79, 
                0x7A, 
                0x7B, 
                0x7C, 
                0x7D, 
                0x7E, 
                0x7F, 
                0x60, 
                0x61, 
                0x62, 
                0x63, 
                0x64, 
                0x65, 
                0x66, 
                0x67, 
                0x91, 
                0x92, 
                0x93, 
                0x96, 
                0xE0, 
                0xE1, 
                0xE2, 
                0xE3, 
                0xE4, 
                0xE5, 
                0xE6, 
                0xE7, 
                0xE8, 
                0xE9, 
                0xEA, 
                0xEB, 
                0xEC, 
                0xED, 
                0xEE, 
                0xEF, 
                0xD0, 
                0xD1, 
                0xD2, 
                0xD3, 
                0xD4, 
                0xD5, 
                0xD6, 
                0xD7, 
                0xD8, 
                0xD9, 
                0xDA, 
                0xDB, 
                0xDC, 
                0xDD, 
                0xDE, 
                0xDF, 
                0xC0, 
                0xC1, 
                0xC2, 
                0xC3, 
                0xC4, 
                0xC5, 
                0xC6, 
                0xC7, 
                0xF0, 
                0xF1, 
                0xF2, 
                0xF3, 
                0xF6, 
                0xF7, 
                0xFA
            })
            Local0 = Match (FBDT, MEQ, Arg0, MTR, Zero, Zero)
            Local0++
            Return (Local0)
        }

        Method (MWGF, 3, Serialized)
        {
            If ((Arg0 == 0x00010016))
            {
                Arg2 = OFBD (Arg1)
                If (Arg2)
                {
                    FSMI = One
                    Return (ASMI (Arg1))
                }
                Else
                {
                    Return (Zero)
                }
            }

            If ((Arg0 == 0x0006001F))
            {
                FSMI = 0x02
                Return (ASMI (One))
            }
        }
    }

    Scope (_SB.ATKD)
    {
        Method (GLCD, 0, NotSerialized)
        {
            Return (EDID) /* \EDID */
        }
    }

    Scope (_SB.ATKD)
    {
        Name (WQMO, Buffer (0x0A40)
        {
            /* 0000 */  0x46, 0x4F, 0x4D, 0x42, 0x01, 0x00, 0x00, 0x00,  // FOMB....
            /* 0008 */  0x30, 0x0A, 0x00, 0x00, 0xCE, 0x35, 0x00, 0x00,  // 0....5..
            /* 0010 */  0x44, 0x53, 0x00, 0x01, 0x1A, 0x7D, 0xDA, 0x54,  // DS...}.T
            /* 0018 */  0xA8, 0xD4, 0x99, 0x00, 0x01, 0x06, 0x18, 0x42,  // .......B
            /* 0020 */  0x10, 0x05, 0x10, 0xCA, 0xE7, 0x8B, 0x42, 0x04,  // ......B.
            /* 0028 */  0x0A, 0x0D, 0xA1, 0x38, 0x44, 0x86, 0xA1, 0x12,  // ...8D...
            /* 0030 */  0x20, 0x24, 0x09, 0x42, 0x2E, 0x98, 0x98, 0x00,  //  $.B....
            /* 0038 */  0x21, 0x10, 0x92, 0x28, 0xC0, 0xBC, 0x00, 0xDD,  // !..(....
            /* 0040 */  0x02, 0x0C, 0x0B, 0xB0, 0x2D, 0xC0, 0xB4, 0x00,  // ....-...
            /* 0048 */  0xC7, 0x40, 0xEA, 0xDF, 0x1F, 0xA2, 0x34, 0x10,  // .@....4.
            /* 0050 */  0x89, 0x80, 0xA4, 0x52, 0x20, 0x24, 0x54, 0x80,  // ...R $T.
            /* 0058 */  0x72, 0x01, 0xBE, 0x05, 0x68, 0x47, 0x94, 0x64,  // r...hG.d
            /* 0060 */  0x01, 0x96, 0x61, 0x44, 0x60, 0xAF, 0xC8, 0x04,  // ..aD`...
            /* 0068 */  0x8D, 0x13, 0x94, 0x33, 0x0C, 0x14, 0xBC, 0x01,  // ...3....
            /* 0070 */  0xDB, 0x14, 0x60, 0x72, 0x10, 0x54, 0xF6, 0x20,  // ..`r.T. 
            /* 0078 */  0x50, 0x32, 0x20, 0xE4, 0x51, 0x80, 0x55, 0x38,  // P2 .Q.U8
            /* 0080 */  0x4D, 0x27, 0x81, 0xDD, 0x0B, 0x30, 0x27, 0xC0,  // M'...0'.
            /* 0088 */  0x9B, 0x00, 0x71, 0xA3, 0x91, 0x35, 0x01, 0x16,  // ..q..5..
            /* 0090 */  0xA1, 0x24, 0x4C, 0x80, 0x2D, 0x18, 0xA1, 0xD4,  // .$L.-...
            /* 0098 */  0x06, 0x23, 0x94, 0xC6, 0x10, 0x04, 0x12, 0x27,  // .#.....'
            /* 00A0 */  0x4A, 0xC4, 0x06, 0x05, 0xEC, 0x34, 0x6C, 0x94,  // J....4l.
            /* 00A8 */  0x88, 0x61, 0x42, 0x44, 0xA8, 0x0C, 0x83, 0x38,  // .aBD...8
            /* 00B0 */  0x84, 0x12, 0x5A, 0xDC, 0x08, 0xED, 0x0F, 0x82,  // ..Z.....
            /* 00B8 */  0x44, 0x5B, 0xB1, 0x86, 0xEA, 0x48, 0xA3, 0x41,  // D[...H.A
            /* 00C0 */  0x8D, 0x28, 0xC1, 0x81, 0x79, 0x34, 0xA7, 0xDA,  // .(..y4..
            /* 00C8 */  0xB9, 0x00, 0xE9, 0x73, 0x15, 0xC8, 0xB1, 0x9E,  // ...s....
            /* 00D0 */  0x62, 0x9D, 0xC3, 0x25, 0x20, 0x09, 0x8C, 0x95,  // b..% ...
            /* 00D8 */  0xA0, 0x83, 0x21, 0x42, 0x71, 0x0D, 0xA8, 0x89,  // ..!Bq...
            /* 00E0 */  0x1F, 0x22, 0x13, 0x04, 0x87, 0x1A, 0xA2, 0xC7,  // ."......
            /* 00E8 */  0x1B, 0xEE, 0x04, 0x8E, 0xFA, 0x48, 0x18, 0xC4,  // .....H..
            /* 00F0 */  0x39, 0x1D, 0x0D, 0xE6, 0x1C, 0xE0, 0x71, 0x9D,  // 9.....q.
            /* 00F8 */  0xCC, 0x19, 0x97, 0x2A, 0xC0, 0xEC, 0xD0, 0x35,  // ...*...5
            /* 0100 */  0xC2, 0x04, 0xC7, 0x63, 0xE8, 0xB3, 0x3F, 0x9F,  // ...c..?.
            /* 0108 */  0x9E, 0x21, 0x89, 0xFC, 0x41, 0xA0, 0x46, 0x66,  // .!..A.Ff
            /* 0110 */  0x68, 0x8F, 0xF1, 0xB4, 0x62, 0x86, 0x7C, 0x0A,  // h...b.|.
            /* 0118 */  0x38, 0x2C, 0x26, 0xF6, 0x94, 0x40, 0xC7, 0x03,  // 8,&..@..
            /* 0120 */  0xEF, 0xFF, 0x3F, 0x1E, 0xF0, 0x28, 0x3E, 0x1A,  // ..?..(>.
            /* 0128 */  0x08, 0xE1, 0x95, 0x20, 0xB6, 0x07, 0xF4, 0xB8,  // ... ....
            /* 0130 */  0x60, 0x60, 0xEC, 0x80, 0xEC, 0x57, 0x00, 0x42,  // ``...W.B
            /* 0138 */  0xF0, 0x32, 0x47, 0x24, 0xA7, 0x08, 0x1A, 0x93,  // .2G$....
            /* 0140 */  0x27, 0xD7, 0x3A, 0x84, 0x40, 0x4E, 0xEA, 0x90,  // '.:.@N..
            /* 0148 */  0x5F, 0x16, 0x18, 0xE2, 0x6B, 0x82, 0xA7, 0x5F,  // _...k.._
            /* 0150 */  0x21, 0xA0, 0x44, 0x8E, 0x00, 0x25, 0x66, 0x04,  // !.D..%f.
            /* 0158 */  0x28, 0xBC, 0xC8, 0x21, 0xCF, 0xE6, 0x08, 0x8E,  // (..!....
            /* 0160 */  0x27, 0xCA, 0x49, 0x1C, 0x90, 0x8F, 0x0E, 0x46,  // '.I....F
            /* 0168 */  0x38, 0x84, 0x72, 0x4F, 0x10, 0x44, 0xF3, 0x8C,  // 8.rO.D..
            /* 0170 */  0x34, 0x8D, 0x73, 0x7A, 0x1B, 0x30, 0x41, 0x1D,  // 4.sz.0A.
            /* 0178 */  0xAF, 0x84, 0x02, 0x94, 0x40, 0x7A, 0xA9, 0xB2,  // ....@z..
            /* 0180 */  0xB1, 0x54, 0x8F, 0x94, 0xE6, 0x3F, 0x23, 0x68,  // .T...?#h
            /* 0188 */  0x86, 0xE7, 0x10, 0xE2, 0x10, 0x13, 0x38, 0x39,  // ......89
            /* 0190 */  0x90, 0x4E, 0x1A, 0x3C, 0x33, 0x89, 0x52, 0x8F,  // .N.<3.R.
            /* 0198 */  0x86, 0xC2, 0x39, 0xE7, 0x81, 0x83, 0x82, 0x18,  // ..9.....
            /* 01A0 */  0xD0, 0x21, 0x20, 0xE4, 0xE4, 0x1C, 0x80, 0x1A,  // .! .....
            /* 01A8 */  0x84, 0x07, 0xF5, 0xBC, 0x60, 0x88, 0xD7, 0x00,  // ....`...
            /* 01B0 */  0x8B, 0x3E, 0x2C, 0xD0, 0xE1, 0xF9, 0x18, 0xC0,  // .>,.....
            /* 01B8 */  0x35, 0x40, 0xE8, 0x5E, 0x60, 0x64, 0xAB, 0x01,  // 5@.^`d..
            /* 01C0 */  0xA4, 0x60, 0xFC, 0x70, 0xC1, 0x09, 0xEA, 0xBA,  // .`.p....
            /* 01C8 */  0x0A, 0x40, 0x1F, 0xE6, 0x11, 0x78, 0x26, 0xEF,  // .@...x&.
            /* 01D0 */  0x16, 0x2F, 0x16, 0x09, 0xEA, 0x3B, 0x0A, 0x80,  // ./...;..
            /* 01D8 */  0x02, 0xC8, 0x53, 0xB7, 0xD2, 0xE1, 0xD3, 0x31,  // ..S....1
            /* 01E0 */  0x84, 0x08, 0x13, 0xCD, 0xE8, 0x3C, 0xFC, 0x54,  // .....<.T
            /* 01E8 */  0x51, 0x71, 0xA7, 0x4A, 0x41, 0x3C, 0xD5, 0xFF,  // Qq.JA<..
            /* 01F0 */  0x7F, 0x82, 0x51, 0xA6, 0x8A, 0x9E, 0x89, 0xA7,  // ..Q.....
            /* 01F8 */  0xCA, 0xEF, 0x07, 0x26, 0xB0, 0xF0, 0x7B, 0x06,  // ...&..{.
            /* 0200 */  0xB4, 0x4B, 0x41, 0xC4, 0x27, 0x02, 0x4F, 0xC3,  // .KA.'.O.
            /* 0208 */  0x70, 0x9E, 0x2C, 0x87, 0xF3, 0x64, 0xF9, 0x58,  // p.,..d.X
            /* 0210 */  0x7C, 0x8F, 0x80, 0x3F, 0x5A, 0x2C, 0x41, 0x81,  // |..?Z,A.
            /* 0218 */  0xB3, 0x05, 0x39, 0x3C, 0x46, 0xF0, 0x48, 0xA9,  // ..9<F.H.
            /* 0220 */  0xAC, 0x71, 0xA1, 0x2E, 0x07, 0x3E, 0x53, 0x30,  // .q...>S0
            /* 0228 */  0xEC, 0x57, 0x84, 0xA3, 0x79, 0x45, 0x38, 0xC3,  // .W..yE8.
            /* 0230 */  0xA7, 0x88, 0x83, 0x7A, 0xE6, 0xB0, 0x49, 0x9D,  // ...z..I.
            /* 0238 */  0x26, 0xA5, 0xC2, 0x7A, 0xA4, 0x1C, 0xD6, 0x68,  // &..z...h
            /* 0240 */  0x61, 0x0F, 0xF8, 0x75, 0xC3, 0x67, 0x15, 0xCF,  // a..u.g..
            /* 0248 */  0xCC, 0x18, 0x61, 0x3D, 0x5A, 0x07, 0x5A, 0xA7,  // ..a=Z.Z.
            /* 0250 */  0x2E, 0x13, 0x38, 0x59, 0x40, 0xBA, 0x66, 0x1C,  // ..8Y@.f.
            /* 0258 */  0xD1, 0x31, 0x1D, 0x12, 0x13, 0x74, 0x99, 0xA0,  // .1...t..
            /* 0260 */  0x10, 0x96, 0x42, 0x21, 0x21, 0x10, 0x3A, 0x12,  // ..B!!.:.
            /* 0268 */  0xF0, 0xE8, 0x60, 0x14, 0xC4, 0x23, 0x73, 0xAC,  // ..`..#s.
            /* 0270 */  0x23, 0x01, 0x5A, 0xD4, 0x1D, 0x82, 0x5E, 0x66,  // #.Z...^f
            /* 0278 */  0x70, 0x93, 0x7D, 0x88, 0x61, 0x20, 0xB1, 0xD8,  // p.}.a ..
            /* 0280 */  0xC5, 0x80, 0x1F, 0x0C, 0xC0, 0xFC, 0xFF, 0x27,  // .......'
            /* 0288 */  0x60, 0x07, 0x03, 0xC0, 0x93, 0x42, 0xA7, 0x52,  // `....B.R
            /* 0290 */  0x9D, 0x1E, 0x0C, 0xC0, 0x15, 0xF2, 0x60, 0x80,  // ......`.
            /* 0298 */  0x96, 0x0A, 0xA4, 0x09, 0xD5, 0x78, 0x80, 0xD2,  // .....x..
            /* 02A0 */  0xAD, 0x25, 0x81, 0x45, 0x1E, 0x0C, 0x50, 0xF2,  // .%.E..P.
            /* 02A8 */  0x28, 0x24, 0xEE, 0x60, 0x80, 0x92, 0x03, 0x47,  // ($.`...G
            /* 02B0 */  0x41, 0x3C, 0x32, 0x47, 0x3D, 0x18, 0xA0, 0xC7,  // A<2G=...
            /* 02B8 */  0x99, 0xE0, 0x20, 0x8F, 0xE5, 0x78, 0x0E, 0xEC,  // .. ..x..
            /* 02C0 */  0xBD, 0xE6, 0x6C, 0x9E, 0x0A, 0x3C, 0xF4, 0x38,  // ..l..<.8
            /* 02C8 */  0x81, 0xF8, 0x8C, 0x0C, 0xF5, 0x6A, 0x13, 0xEA,  // .....j..
            /* 02D0 */  0xF9, 0xC0, 0xA7, 0x22, 0x83, 0xBD, 0x23, 0x18,  // ..."..#.
            /* 02D8 */  0xEA, 0xF1, 0x20, 0xA6, 0x27, 0xF7, 0xF2, 0xE5,  // .. .'...
            /* 02E0 */  0x13, 0x82, 0xD1, 0xF8, 0x11, 0x01, 0x38, 0xFF,  // ......8.
            /* 02E8 */  0xFF, 0x8F, 0x08, 0xC0, 0xDA, 0xA9, 0x46, 0xAB,  // ......F.
            /* 02F0 */  0x3A, 0x8F, 0x08, 0xE0, 0x8A, 0x74, 0x4D, 0x42,  // :....tMB
            /* 02F8 */  0x0B, 0x03, 0xD2, 0x38, 0x0E, 0xB7, 0xCF, 0x33,  // ...8...3
            /* 0300 */  0x9B, 0x08, 0x2C, 0x09, 0x48, 0xD7, 0x24, 0x2E,  // ..,.H.$.
            /* 0308 */  0x86, 0x42, 0x32, 0x8E, 0x08, 0xA8, 0xE0, 0x07,  // .B2.....
            /* 0310 */  0x05, 0x0A, 0x62, 0x40, 0xA7, 0x3A, 0x22, 0xA0,  // ..b@.:".
            /* 0318 */  0x0F, 0x45, 0xF6, 0x7E, 0x24, 0x20, 0x77, 0x82,  // .E.~$ w.
            /* 0320 */  0x23, 0x3B, 0x99, 0x33, 0x7B, 0x0F, 0x3B, 0xD9,  // #;.3{.;.
            /* 0328 */  0xB7, 0x02, 0x0F, 0xC9, 0x57, 0x84, 0x30, 0xC1,  // ....W.0.
            /* 0330 */  0x1E, 0x0C, 0x7C, 0x1E, 0xF3, 0x85, 0xCB, 0xE7,  // ..|.....
            /* 0338 */  0x25, 0xC0, 0x97, 0x88, 0x31, 0xA3, 0x62, 0x8F,  // %...1.b.
            /* 0340 */  0x99, 0x82, 0x78, 0xCC, 0xBE, 0xE9, 0xFD, 0xFF,  // ..x.....
            /* 0348 */  0x8F, 0x19, 0xFB, 0x11, 0xF0, 0x74, 0x71, 0x57,  // .....tqW
            /* 0350 */  0x0C, 0x9F, 0x65, 0x80, 0xCB, 0x99, 0x09, 0x70,  // ..e....p
            /* 0358 */  0xE5, 0x55, 0xA2, 0x4F, 0x8F, 0x27, 0x0B, 0x70,  // .U.O.'.p
            /* 0360 */  0x85, 0x3B, 0xCB, 0xA0, 0x25, 0x02, 0xC9, 0xE5,  // .;..%...
            /* 0368 */  0x9D, 0x49, 0x07, 0x3A, 0x13, 0xF8, 0x1C, 0xE3,  // .I.:....
            /* 0370 */  0xB3, 0x0C, 0x3F, 0x3A, 0x59, 0xD4, 0xB1, 0x00,  // ..?:Y...
            /* 0378 */  0x75, 0xB8, 0x30, 0x98, 0x41, 0x3C, 0x32, 0x47,  // u.0.A<2G
            /* 0380 */  0x3C, 0x16, 0xA0, 0x47, 0xEC, 0xF3, 0xC0, 0x63,  // <..G...c
            /* 0388 */  0x81, 0x6F, 0x7B, 0x3E, 0xD1, 0xB1, 0x7B, 0x8C,  // .o{>..{.
            /* 0390 */  0xEF, 0x4C, 0xEC, 0x5C, 0x68, 0xA8, 0x57, 0x83,  // .L.\h.W.
            /* 0398 */  0x48, 0x1E, 0xD5, 0x9B, 0x9F, 0x51, 0x1F, 0x67,  // H....Q.g
            /* 03A0 */  0xDE, 0x63, 0xB0, 0xC7, 0x03, 0x78, 0xFF, 0xFF,  // .c...x..
            /* 03A8 */  0x73, 0x0C, 0x60, 0xD4, 0xA5, 0xC2, 0x17, 0xDA,  // s.`.....
            /* 03B0 */  0xE3, 0x01, 0xB8, 0x44, 0xAD, 0x42, 0xC7, 0x03,  // ...D.B..
            /* 03B8 */  0x5C, 0xB4, 0xB5, 0x68, 0x42, 0x67, 0x76, 0xBA,  // \..hBgv.
            /* 03C0 */  0xCF, 0x31, 0x2C, 0xD4, 0x39, 0x06, 0x75, 0xE7,  // .1,.9.u.
            /* 03C8 */  0x75, 0xA4, 0xE3, 0x01, 0x2A, 0xC4, 0xF1, 0x80,  // u...*...
            /* 03D0 */  0x82, 0x78, 0x5C, 0x0E, 0x77, 0x3C, 0x40, 0xCB,  // .x\.w<@.
            /* 03D8 */  0xBB, 0xDB, 0x92, 0x89, 0xF9, 0x06, 0xE2, 0x09,  // ........
            /* 03E0 */  0x45, 0x79, 0x2A, 0x78, 0x2E, 0xE0, 0xC7, 0x18,  // Ey*x....
            /* 03E8 */  0x1F, 0x0C, 0xDE, 0x98, 0x7C, 0x40, 0x78, 0x3E,  // ....|@x>
            /* 03F0 */  0x78, 0x35, 0xC0, 0x80, 0x9D, 0x56, 0x1C, 0x43,  // x5...V.C
            /* 03F8 */  0xBC, 0xCA, 0x00, 0xC7, 0xFF, 0xFF, 0xDD, 0x80,  // ........
            /* 0400 */  0xA5, 0x18, 0x1E, 0x5A, 0xC7, 0xB1, 0x81, 0x0C,  // ...Z....
            /* 0408 */  0x2D, 0xC2, 0xD9, 0x9D, 0x9F, 0xA7, 0x04, 0xDE,  // -.......
            /* 0410 */  0x71, 0xFB, 0xB4, 0x03, 0x9C, 0x4F, 0x81, 0x3E,  // q....O.>
            /* 0418 */  0x19, 0xF0, 0xB0, 0x43, 0xA2, 0x20, 0x3E, 0x21,  // ...C. >!
            /* 0420 */  0x38, 0xC8, 0x35, 0x15, 0xCA, 0x65, 0x00, 0x73,  // 8.5..e.s
            /* 0428 */  0xF4, 0x00, 0xFB, 0x40, 0x7C, 0x22, 0x03, 0x44,  // ...@|".D
            /* 0430 */  0x39, 0x94, 0x78, 0xD0, 0xD1, 0xFF, 0xFF, 0xE8,  // 9.x.....
            /* 0438 */  0x01, 0xA6, 0x4C, 0x27, 0x32, 0xB4, 0xB2, 0xA3,  // ..L'2...
            /* 0440 */  0x07, 0x19, 0xA5, 0xA7, 0x96, 0xC0, 0x9A, 0x8E,  // ........
            /* 0448 */  0x1E, 0x28, 0x35, 0x14, 0xD2, 0x73, 0xF4, 0x40,  // .(5..s.@
            /* 0450 */  0x29, 0xB8, 0x0E, 0xF3, 0x83, 0x0E, 0x8D, 0x77,  // )......w
            /* 0458 */  0xD0, 0x81, 0x72, 0xF4, 0x80, 0x77, 0xED, 0xC0,  // ..r..w..
            /* 0460 */  0x1D, 0xAA, 0xD8, 0xB8, 0xCE, 0xD0, 0x90, 0x87,  // ........
            /* 0468 */  0xF6, 0x68, 0xE6, 0x03, 0x4F, 0x60, 0x5F, 0x8A,  // .h..O`_.
            /* 0470 */  0x01, 0xBF, 0x87, 0x73, 0x1F, 0x24, 0x7D, 0xDA,  // ...s.$}.
            /* 0478 */  0xE6, 0x37, 0x32, 0xE0, 0xF1, 0xFF, 0xBF, 0x59,  // .72....Y
            /* 0480 */  0x00, 0x82, 0x84, 0x5A, 0x74, 0x78, 0x75, 0x04,  // ...Ztxu.
            /* 0488 */  0xFF, 0xCD, 0xF1, 0x88, 0x6A, 0x9D, 0x92, 0xAE,  // ....j...
            /* 0490 */  0x8E, 0x70, 0xEE, 0xA9, 0x3E, 0x12, 0x70, 0x32,  // .p..>.p2
            /* 0498 */  0xC3, 0x99, 0xC2, 0x80, 0x4E, 0x77, 0x24, 0x40,  // ....Nw$@
            /* 04A0 */  0x5F, 0x17, 0x3C, 0x9E, 0x83, 0x79, 0xAC, 0x78,  // _.<..y.x
            /* 04A8 */  0xA4, 0xF0, 0x78, 0xCE, 0xF5, 0x3D, 0x2D, 0xD0,  // ..x..=-.
            /* 04B0 */  0x79, 0xF8, 0x8C, 0xE4, 0xC9, 0x87, 0x7A, 0x33,  // y.....z3
            /* 04B8 */  0xF0, 0xA0, 0x0C, 0x14, 0x8B, 0x69, 0x3F, 0x02,  // .....i?.
            /* 04C0 */  0x92, 0xEB, 0x99, 0x4F, 0x64, 0xEC, 0x64, 0x01,  // ...Od.d.
            /* 04C8 */  0x18, 0xF9, 0xFF, 0xDF, 0xDE, 0x01, 0x0E, 0xF9,  // ........
            /* 04D0 */  0x74, 0xAA, 0x55, 0xE9, 0xC9, 0x02, 0x5C, 0x8A,  // t.U...\.
            /* 04D8 */  0x2F, 0x73, 0xE8, 0xDC, 0x6B, 0xD1, 0xC1, 0xE2,  // /s..k...
            /* 04E0 */  0x90, 0x30, 0x89, 0x4F, 0x16, 0xA8, 0xAC, 0x14,  // .0.O....
            /* 04E8 */  0x4A, 0x76, 0xB2, 0x40, 0x65, 0x39, 0x59, 0x50,  // Jv.@e9YP
            /* 04F0 */  0x10, 0x8F, 0xCB, 0xB7, 0x77, 0xFC, 0xE8, 0x7D,  // ....w..}
            /* 04F8 */  0xC0, 0x7D, 0x05, 0x62, 0x87, 0x47, 0x8F, 0x08,  // .}.b.G..
            /* 0500 */  0xC6, 0xAD, 0x02, 0xFB, 0xFF, 0xBF, 0x55, 0x00,  // ......U.
            /* 0508 */  0xD7, 0xBB, 0x2C, 0xFE, 0xA2, 0xEF, 0x1B, 0xC1,  // ..,.....
            /* 0510 */  0x33, 0x37, 0x9C, 0x91, 0x01, 0x8F, 0x03, 0x1D,  // 37......
            /* 0518 */  0xF0, 0x16, 0x74, 0x39, 0x40, 0x49, 0xB8, 0x1C,  // ..t9@I..
            /* 0520 */  0x50, 0x10, 0x9F, 0xB7, 0xE0, 0x88, 0x9B, 0x21,  // P......!
            /* 0528 */  0xB9, 0x1A, 0x80, 0xE3, 0x92, 0x60, 0x0C, 0xDF,  // .....`..
            /* 0530 */  0x66, 0xF8, 0xD9, 0x0E, 0x38, 0xFC, 0xFF, 0x2F,  // f...8../
            /* 0538 */  0x22, 0x80, 0x25, 0xAD, 0x16, 0x95, 0x3A, 0xBD,  // ".%...:.
            /* 0540 */  0x88, 0x80, 0x2B, 0xCC, 0x8D, 0x09, 0x7D, 0x5B,  // ..+...}[
            /* 0548 */  0xF2, 0xD9, 0xCE, 0xD3, 0x3F, 0xB4, 0x03, 0x20,  // ....?.. 
            /* 0550 */  0x17, 0x11, 0x94, 0x0C, 0x0A, 0x09, 0x39, 0x1C,  // ......9.
            /* 0558 */  0xA0, 0xCE, 0x8F, 0x86, 0x33, 0x88, 0x01, 0x9D,  // ....3...
            /* 0560 */  0xEB, 0x70, 0x80, 0x9E, 0xB2, 0x87, 0x72, 0x66,  // .p....rf
            /* 0568 */  0x8F, 0x76, 0x3E, 0x13, 0xFB, 0x40, 0x77, 0xB0,  // .v>..@w.
            /* 0570 */  0x2F, 0xA8, 0x46, 0x7A, 0x1C, 0x39, 0xBA, 0x33,  // /.Fz.9.3
            /* 0578 */  0x3A, 0xA5, 0x57, 0x33, 0x23, 0xC4, 0x3A, 0x2E,  // :.W3#.:.
            /* 0580 */  0x5F, 0x10, 0x7C, 0x7A, 0x07, 0xDC, 0xFC, 0xFF,  // _.|z....
            /* 0588 */  0xEF, 0x75, 0x00, 0x7F, 0x14, 0xCA, 0x3C, 0x56,  // .u....<V
            /* 0590 */  0x80, 0x2B, 0xC0, 0xB1, 0x02, 0x7D, 0x9E, 0xF0,  // .+...}..
            /* 0598 */  0x84, 0x0E, 0xF7, 0xB9, 0xC2, 0xAF, 0x12, 0x7E,  // .......~
            /* 05A0 */  0xAC, 0xE0, 0xD1, 0x49, 0x74, 0x24, 0x80, 0x9B,  // ...It$..
            /* 05A8 */  0xE5, 0x48, 0x80, 0xBE, 0x40, 0xF8, 0x58, 0x81,  // .H..@.X.
            /* 05B0 */  0xBF, 0x7A, 0xF2, 0x03, 0x05, 0xCC, 0xFF, 0xFF,  // .z......
            /* 05B8 */  0x75, 0x0E, 0x60, 0xAF, 0x53, 0x89, 0x17, 0x8A,  // u.`.S...
            /* 05C0 */  0x07, 0x0A, 0x70, 0x85, 0x38, 0x50, 0xA0, 0xA5,  // ..p.8P..
            /* 05C8 */  0x28, 0xF8, 0xFF, 0x1F, 0x87, 0x7D, 0xA0, 0xC0,  // (....}..
            /* 05D0 */  0x88, 0x38, 0x50, 0xA0, 0xE2, 0x93, 0xF8, 0xD8,  // .8P.....
            /* 05D8 */  0x83, 0x8A, 0x3C, 0x6E, 0x0A, 0x62, 0x40, 0xE7,  // ..<n.b@.
            /* 05E0 */  0x39, 0x12, 0xA0, 0x15, 0x5D, 0xE7, 0x50, 0x47,  // 9...].PG
            /* 05E8 */  0x0A, 0x80, 0xA9, 0xFF, 0xFF, 0x23, 0x05, 0xB0,  // .....#..
            /* 05F0 */  0xF0, 0x78, 0xA4, 0x00, 0x5D, 0x9C, 0x75, 0xEA,  // .x..].u.
            /* 05F8 */  0x48, 0x81, 0x13, 0x05, 0xA4, 0x23, 0xC5, 0x91,  // H....#..
            /* 0600 */  0x1D, 0xDA, 0xF1, 0xB2, 0x5B, 0xB1, 0xFF, 0x13,  // ....[...
            /* 0608 */  0xF4, 0x5C, 0x46, 0x64, 0x1C, 0x29, 0x50, 0xC1,  // .\Fd.)P.
            /* 0610 */  0xC1, 0x28, 0x88, 0x47, 0xE6, 0x50, 0x47, 0x02,  // .(.G.PG.
            /* 0618 */  0xB4, 0xA4, 0x43, 0x15, 0xBD, 0x11, 0x18, 0xE4,  // ..C.....
            /* 0620 */  0xE1, 0xCF, 0x33, 0x7A, 0x2A, 0x78, 0x2B, 0xF3,  // ..3z*x+.
            /* 0628 */  0xE1, 0xDD, 0x63, 0x3D, 0x91, 0x17, 0x01, 0x76,  // ..c=...v
            /* 0630 */  0x2E, 0x00, 0x37, 0x81, 0xCF, 0x05, 0x80, 0x28,  // ..7....(
            /* 0638 */  0x99, 0x0E, 0x25, 0x9E, 0x0B, 0x60, 0xFE, 0xFF,  // ..%..`..
            /* 0640 */  0xCF, 0x05, 0x30, 0xC4, 0x9F, 0x5C, 0xD0, 0x12,  // ..0..\..
            /* 0648 */  0x80, 0x34, 0xA7, 0x3A, 0x2F, 0xB6, 0xC2, 0x7E,  // .4.:/..~
            /* 0650 */  0xEA, 0x20, 0xE7, 0x02, 0x3A, 0x22, 0xC7, 0x26,  // . ..:".&
            /* 0658 */  0xD1, 0x91, 0xC0, 0xE7, 0x02, 0x1E, 0xF5, 0x5C,  // .......\
            /* 0660 */  0x40, 0x41, 0x0C, 0xE8, 0x1C, 0xE7, 0x02, 0xB4,  // @A......
            /* 0668 */  0x92, 0x93, 0x07, 0x19, 0xEC, 0x91, 0x3E, 0xB5,  // ......>.
            /* 0670 */  0x00, 0xA6, 0xCF, 0x7D, 0x80, 0x9D, 0xFF, 0xFF,  // ...}....
            /* 0678 */  0x71, 0x02, 0x98, 0x19, 0xD4, 0xA9, 0xD5, 0xE4,  // q.......
            /* 0680 */  0x71, 0x02, 0x5C, 0x79, 0x8E, 0x13, 0x68, 0x55,  // q.\y..hU
            /* 0688 */  0x40, 0x1A, 0xD9, 0xB3, 0xAE, 0x35, 0x42, 0x11,  // @....5B.
            /* 0690 */  0x3D, 0xE7, 0x2A, 0x94, 0x12, 0x0A, 0x69, 0x39,  // =.*...i9
            /* 0698 */  0xB5, 0xA0, 0xD2, 0x8F, 0x9B, 0x82, 0x18, 0xD0,  // ........
            /* 06A0 */  0xD1, 0x4E, 0xC2, 0x50, 0xC6, 0xF0, 0x04, 0xEC,  // .N.P....
            /* 06A8 */  0xC9, 0x3C, 0x14, 0x04, 0x79, 0x65, 0xF1, 0x0D,  // .<..ye..
            /* 06B0 */  0x98, 0xDF, 0x82, 0xD9, 0x94, 0x7C, 0x77, 0xF1,  // .....|w.
            /* 06B8 */  0xD5, 0x25, 0x9C, 0x35, 0x5F, 0xAF, 0xC8, 0x1D,  // .%.5_...
            /* 06C0 */  0xEB, 0x0D, 0xC9, 0xF7, 0x0A, 0xC0, 0xEE, 0xFF,  // ........
            /* 06C8 */  0xFF, 0x72, 0x05, 0x78, 0x77, 0xA8, 0xD0, 0xA4,  // .r.xw...
            /* 06D0 */  0xC6, 0x7B, 0x05, 0xB8, 0x84, 0xAC, 0x42, 0xF7,  // .{....B.
            /* 06D8 */  0x0A, 0x5C, 0x9C, 0xB5, 0x68, 0x16, 0xE7, 0xF1,  // .\..h...
            /* 06E0 */  0x76, 0xF5, 0x5E, 0xC1, 0x82, 0xDC, 0x2B, 0x50,  // v.^...+P
            /* 06E8 */  0x11, 0x28, 0x14, 0xE2, 0x5E, 0x81, 0x92, 0x7D,  // .(..^..}
            /* 06F0 */  0xF9, 0xA1, 0x20, 0x1E, 0x97, 0x83, 0x1C, 0x09,  // .. .....
            /* 06F8 */  0xD0, 0x52, 0x40, 0x74, 0x01, 0x78, 0x76, 0xF6,  // .R@t.xv.
            /* 0700 */  0x8D, 0xDF, 0x20, 0xE7, 0xFA, 0x12, 0xC0, 0xAE,  // .. .....
            /* 0708 */  0x13, 0xC0, 0xF1, 0xFF, 0x7F, 0x23, 0xF0, 0x15,  // .....#..
            /* 0710 */  0x16, 0xCE, 0xDD, 0x03, 0x3F, 0xD3, 0x97, 0x0E,  // ....?...
            /* 0718 */  0x36, 0x2B, 0xF0, 0x0E, 0xD8, 0x77, 0x23, 0xC0,  // 6+...w#.
            /* 0720 */  0xF7, 0x48, 0x7C, 0xE8, 0x00, 0xFC, 0xFC, 0xFF,  // .H|.....
            /* 0728 */  0x0F, 0x1D, 0xDC, 0xA6, 0x57, 0x8F, 0x87, 0x0E,  // ....W...
            /* 0730 */  0x90, 0x65, 0xB8, 0x1B, 0xA1, 0x2F, 0x45, 0x3E,  // .e.../E>
            /* 0738 */  0xC2, 0x7A, 0x4C, 0x87, 0xC4, 0x34, 0x1C, 0x3A,  // .zL..4.:
            /* 0740 */  0x50, 0xE9, 0x49, 0x94, 0xFC, 0x48, 0x80, 0xCA,  // P.I..H..
            /* 0748 */  0x7A, 0x24, 0xA0, 0x20, 0x06, 0xF4, 0xA1, 0x03,  // z$. ....
            /* 0750 */  0xF0, 0x71, 0x9D, 0x00, 0x16, 0x12, 0x2E, 0x2C,  // .q.....,
            /* 0758 */  0xA8, 0xD0, 0x93, 0xA5, 0x20, 0x9E, 0xAC, 0x03,  // .... ...
            /* 0760 */  0x4D, 0x16, 0x7D, 0x81, 0xF0, 0x99, 0xCF, 0x93,  // M.}.....
            /* 0768 */  0xC5, 0x9C, 0x28, 0x1E, 0x8B, 0x70, 0xB7, 0x22,  // ..(..p."
            /* 0770 */  0x60, 0xF6, 0xFF, 0xBF, 0x51, 0x00, 0x36, 0x7E,  // `...Q.6~
            /* 0778 */  0xB0, 0xA5, 0x3A, 0xBD, 0x51, 0x80, 0x4B, 0xCA,  // ..:.Q.K.
            /* 0780 */  0xAD, 0x08, 0x1D, 0xE8, 0x46, 0x41, 0x86, 0xF4,  // ....FA..
            /* 0788 */  0x6C, 0x79, 0x48, 0x2C, 0xCA, 0x8D, 0x02, 0x75,  // lyH,...u
            /* 0790 */  0xDE, 0x76, 0x8C, 0x53, 0x01, 0x4A, 0xF8, 0xAD,  // .v.S.J..
            /* 0798 */  0x88, 0x82, 0xF8, 0x56, 0x04, 0x38, 0x49, 0x33,  // ...V.8I3
            /* 07A0 */  0x28, 0xB4, 0x9E, 0x5B, 0x11, 0x94, 0x9B, 0x03,  // (..[....
            /* 07A8 */  0x76, 0x5A, 0xE0, 0xFC, 0xFF, 0x5F, 0x8B, 0x00,  // vZ..._..
            /* 07B0 */  0x86, 0x4A, 0xB4, 0xA8, 0xF5, 0xD4, 0x01, 0xB2,  // .J......
            /* 07B8 */  0x00, 0xAB, 0xA0, 0x67, 0x19, 0x4B, 0x86, 0x41,  // ...g.K.A
            /* 07C0 */  0x49, 0x80, 0xD0, 0xB9, 0xDB, 0x43, 0xE0, 0x23,  // I....C.#
            /* 07C8 */  0xF4, 0x9C, 0xFF, 0xFF, 0xCD, 0x9F, 0x36, 0xC9,  // ......6.
            /* 07D0 */  0x74, 0x7C, 0xD2, 0x38, 0x00, 0x26, 0x6D, 0x6C,  // t|.8.&ml
            /* 07D8 */  0xA8, 0x13, 0x87, 0x07, 0xF9, 0x2E, 0xE1, 0x1B,  // ........
            /* 07E0 */  0x87, 0x2F, 0x36, 0x86, 0x49, 0xE0, 0xB1, 0x31,  // ./6.I..1
            /* 07E8 */  0x34, 0x7E, 0x22, 0x80, 0x01, 0x78, 0x88, 0xEF,  // 4~"..x..
            /* 07F0 */  0xCE, 0x1E, 0x84, 0x67, 0x76, 0x10, 0x98, 0x93,  // ...gv...
            /* 07F8 */  0x89, 0x2F, 0x7F, 0xAD, 0x1E, 0x09, 0x10, 0xEE,  // ./......
            /* 0800 */  0x6F, 0x04, 0x3A, 0x92, 0xBE, 0x08, 0x3C, 0xAA,  // o.:...<.
            /* 0808 */  0x1A, 0xC4, 0xD6, 0x04, 0xD8, 0x9A, 0xBC, 0x80,  // ........
            /* 0810 */  0x7C, 0x1A, 0x88, 0x72, 0x4A, 0x81, 0x1E, 0xCE,  // |..rJ...
            /* 0818 */  0x8D, 0xD2, 0x9C, 0x00, 0x63, 0x50, 0x08, 0x90,  // ....cP..
            /* 0820 */  0x58, 0xEF, 0x01, 0xB5, 0x81, 0x09, 0x2A, 0x58,  // X.....*X
            /* 0828 */  0x98, 0x20, 0x86, 0x6A, 0x7F, 0x10, 0x44, 0xFE,  // . .j..D.
            /* 0830 */  0x33, 0x40, 0xD7, 0x0C, 0x47, 0x1A, 0x0D, 0xEA,  // 3@..G...
            /* 0838 */  0x20, 0xC4, 0x47, 0x73, 0xAA, 0x0F, 0x1F, 0x0C,  //  .Gs....
            /* 0840 */  0xE4, 0x21, 0xC5, 0x97, 0xEC, 0xC3, 0xF5, 0x81,  // .!......
            /* 0848 */  0xDA, 0x04, 0x0F, 0x0F, 0x3E, 0x43, 0xC0, 0x71,  // ....>C.q
            /* 0850 */  0x0D, 0xA8, 0x89, 0x1F, 0x22, 0xFB, 0xC9, 0x18,  // ...."...
            /* 0858 */  0x8E, 0x0F, 0xD1, 0x87, 0x0A, 0x4F, 0xE0, 0x6D,  // .....O.m
            /* 0860 */  0xC0, 0x80, 0xEC, 0x10, 0x01, 0x7F, 0x3C, 0x86,  // ......<.
            /* 0868 */  0x7E, 0x8A, 0xF0, 0x0D, 0xD0, 0x63, 0xD3, 0x20,  // ~....c. 
            /* 0870 */  0x50, 0x27, 0x0D, 0x3E, 0xCC, 0xD3, 0x8A, 0x19,  // P'.>....
            /* 0878 */  0xF2, 0x29, 0xE0, 0xB0, 0x98, 0xD8, 0xB3, 0x03,  // .)......
            /* 0880 */  0x1D, 0x0F, 0xF8, 0x15, 0x1F, 0x0D, 0x74, 0x79,  // ......ty
            /* 0888 */  0x31, 0xB6, 0xCF, 0x2C, 0x8E, 0x70, 0x10, 0x41,  // 1..,.p.A
            /* 0890 */  0xFC, 0xFF, 0xC7, 0x83, 0x01, 0x3D, 0x1B, 0x9F,  // .....=..
            /* 0898 */  0x21, 0x7C, 0x2F, 0x60, 0x47, 0x0B, 0x2E, 0xEA,  // !|/`G...
            /* 08A0 */  0x68, 0x81, 0x3A, 0x34, 0xF8, 0xBC, 0xC0, 0x10,  // h.:4....
            /* 08A8 */  0x1F, 0x67, 0x0C, 0xF1, 0x64, 0xC1, 0x4E, 0x52,  // .g..d.NR
            /* 08B0 */  0xE0, 0x1C, 0x89, 0x0F, 0x21, 0xF0, 0x41, 0x5E,  // ....!.A^
            /* 08B8 */  0x56, 0x0C, 0x11, 0x24, 0xF8, 0x33, 0xC1, 0xE9,  // V..$.3..
            /* 08C0 */  0xB0, 0xA1, 0x61, 0x08, 0x8A, 0x1C, 0x01, 0xEA,  // ..a.....
            /* 08C8 */  0xD8, 0xE1, 0x11, 0xF0, 0x73, 0xC2, 0x03, 0x09,  // ....s...
            /* 08D0 */  0x1B, 0xC1, 0x3B, 0x89, 0x27, 0x71, 0x40, 0x3E,  // ..;.'q@>
            /* 08D8 */  0x5B, 0x18, 0x21, 0x76, 0xB9, 0x47, 0x0C, 0x72,  // [.!v.G.r
            /* 08E0 */  0x51, 0x3E, 0xBE, 0x67, 0x18, 0xCC, 0x98, 0x70,  // Q>.g...p
            /* 08E8 */  0x27, 0x06, 0x0F, 0x81, 0x0F, 0xE0, 0xD9, 0xE2,  // '.......
            /* 08F0 */  0xFC, 0x7C, 0x42, 0x39, 0x2B, 0xDC, 0x88, 0xF9,  // .|B9+...
            /* 08F8 */  0x94, 0x70, 0x03, 0xC0, 0x28, 0xB4, 0xE9, 0x53,  // .p..(..S
            /* 0900 */  0xA3, 0x51, 0xAB, 0x06, 0x65, 0x6A, 0x94, 0x69,  // .Q..ej.i
            /* 0908 */  0x50, 0xAB, 0x4F, 0xA5, 0xC6, 0x8C, 0x0D, 0xE9,  // P.O.....
            /* 0910 */  0x71, 0x8A, 0x9D, 0x00, 0x2C, 0xE2, 0x11, 0x20,  // q...,.. 
            /* 0918 */  0x10, 0x8B, 0xA5, 0x90, 0x91, 0x51, 0x19, 0x44,  // .....Q.D
            /* 0920 */  0x40, 0x56, 0xF9, 0x2E, 0x11, 0x90, 0x35, 0x83,  // @V....5.
            /* 0928 */  0x08, 0xC8, 0xA9, 0x2D, 0x00, 0x31, 0x0D, 0x6F,  // ...-.1.o
            /* 0930 */  0x0C, 0x01, 0x39, 0x99, 0x07, 0x20, 0x96, 0x13,  // ..9.. ..
            /* 0938 */  0x44, 0x40, 0x96, 0x6A, 0x02, 0x88, 0xE9, 0x06,  // D@.j....
            /* 0940 */  0x11, 0x90, 0xB5, 0xAA, 0x18, 0x04, 0x05, 0x11,  // ........
            /* 0948 */  0x90, 0x75, 0xBC, 0x1C, 0x04, 0x64, 0x55, 0x20,  // .u...dU 
            /* 0950 */  0x02, 0x72, 0x3E, 0x1B, 0x40, 0x2C, 0x2C, 0x88,  // .r>.@,,.
            /* 0958 */  0x80, 0x2C, 0x52, 0x07, 0x10, 0x53, 0xAC, 0xE3,  // .,R..S..
            /* 0960 */  0xFF, 0x0F, 0xC4, 0xB4, 0xF9, 0x00, 0x62, 0x4A,  // ......bJ
            /* 0968 */  0x41, 0x34, 0x20, 0xF2, 0x28, 0x10, 0x90, 0x25,  // A4 .(..%
            /* 0970 */  0x50, 0x08, 0xC8, 0x71, 0x41, 0x04, 0xE4, 0xF0,  // P..qA...
            /* 0978 */  0x40, 0x34, 0xC7, 0xFB, 0x41, 0x40, 0x0E, 0x05,  // @4..A@..
            /* 0980 */  0x22, 0x20, 0x07, 0x78, 0x36, 0x08, 0xC8, 0x71,  // " .x6..q
            /* 0988 */  0x40, 0x04, 0x64, 0x49, 0x5A, 0x80, 0x98, 0x3E,  // @.dIZ..>
            /* 0990 */  0x10, 0x01, 0x39, 0x24, 0x10, 0x4D, 0x0C, 0x44,  // ..9$.M.D
            /* 0998 */  0x13, 0x7B, 0x01, 0x62, 0xF9, 0x41, 0x04, 0xE4,  // .{.b.A..
            /* 09A0 */  0x10, 0x66, 0x80, 0x58, 0x22, 0x10, 0x01, 0x59,  // .f.X"..Y
            /* 09A8 */  0xFD, 0xD7, 0x4A, 0x40, 0xCE, 0x02, 0xA2, 0xE1,  // ..J@....
            /* 09B0 */  0x93, 0x57, 0x81, 0x80, 0xAC, 0x08, 0x44, 0x40,  // .W....D@
            /* 09B8 */  0x4E, 0x0F, 0x44, 0xB5, 0xD8, 0x39, 0x9F, 0xD1,  // N.D..9..
            /* 09C0 */  0x77, 0x97, 0x80, 0x9C, 0x0A, 0x44, 0x40, 0x4E,  // w....D@N
            /* 09C8 */  0xE0, 0x07, 0x88, 0xE5, 0x01, 0x11, 0x90, 0xF5,  // ........
            /* 09D0 */  0x18, 0x02, 0x62, 0xEA, 0x40, 0x04, 0xE4, 0x48,  // ..b.@..H
            /* 09D8 */  0x8A, 0x80, 0x58, 0x3E, 0x10, 0x01, 0x39, 0x8B,  // ..X>..9.
            /* 09E0 */  0x23, 0x20, 0x96, 0x0C, 0x44, 0x40, 0x56, 0x68,  // # ..D@Vh
            /* 09E8 */  0x09, 0x88, 0xC9, 0x05, 0x11, 0x90, 0xA5, 0x69,  // .......i
            /* 09F0 */  0x02, 0x62, 0x42, 0x41, 0x04, 0xE4, 0x78, 0x9E,  // .bBA..x.
            /* 09F8 */  0x80, 0x58, 0x56, 0x10, 0x01, 0x59, 0xE9, 0xCB,  // .XV..Y..
            /* 0A00 */  0x43, 0x40, 0x96, 0x0D, 0x22, 0x20, 0x4B, 0x34,  // C@.." K4
            /* 0A08 */  0x05, 0xC4, 0x04, 0x83, 0x08, 0xC8, 0x31, 0x55,  // ......1U
            /* 0A10 */  0x01, 0xB1, 0xCC, 0x20, 0x02, 0x72, 0x4A, 0x57,  // ... .rJW
            /* 0A18 */  0x40, 0x14, 0x44, 0x03, 0x20, 0xCF, 0x9C, 0x03,  // @.D. ...
            /* 0A20 */  0x60, 0x20, 0x02, 0x72, 0x6C, 0x20, 0xAA, 0xE1,  // ` .rl ..
            /* 0A28 */  0x59, 0x26, 0x20, 0xE7, 0x05, 0x11, 0x90, 0xD3,  // Y& .....
            /* 0A30 */  0x03, 0x51, 0x95, 0x9F, 0x9D, 0x20, 0x24, 0x23,  // .Q... $#
            /* 0A38 */  0x08, 0x55, 0xF9, 0x09, 0x11, 0x88, 0xFF, 0xFF   // .U......
        })
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (_QD5, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x61
            If (ATKP)
            {
                ^^^^ATKD.IANE (0x38)
            }
        }
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (SKEY, 1, Serialized)
        {
            Switch (Arg0)
            {
                Case (0x86)
                {
                    ^^^^ATKD.MAKY ()
                }
                Case (0xC5)
                {
                    DBG8 = 0xC5
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xC5)
                    }
                }
                Case (0xC4)
                {
                    DBG8 = 0xC4
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xC4)
                    }
                }
                Case (0xB3)
                {
                    DBG8 = 0xB3
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xB3)
                    }
                }
                Case (0xAE)
                {
                    DBG8 = 0xAE
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xAE)
                    }
                }
                Case (0x10)
                {
                    DBG8 = 0x10
                    If ((OSYS >= 0x07DC))
                    {
                        BRTN (0x87)
                    }
                }
                Case (0x20)
                {
                    DBG8 = 0x20
                    If ((OSYS >= 0x07DC))
                    {
                        BRTN (0x86)
                    }
                }
                Case (0x6B)
                {
                    DBG8 = 0x6B
                    Acquire (MUT0, 0x0500)
                    TPFG = One
                    Release (MUT0)
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x6B)
                    }
                }
                Case (0x6C)
                {
                    Notify (SLPB, 0x80) // Status Change
                }
                Case (0x8A)
                {
                    DBG8 = 0x8A
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x8A)
                    }
                }
                Case (0x9E)
                {
                    DBG8 = 0x9E
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x9E)
                    }
                }
                Case (0x7C)
                {
                    DBG8 = 0x7C
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x7C)
                    }
                }
                Case (0x38)
                {
                    DBG8 = 0x38
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x38)
                    }
                }
                Case (0xB5)
                {
                    DBG8 = 0xB5
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0xB5)
                    }
                }
                Case (0x35)
                {
                    DBG8 = 0x35
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x35)
                    }
                }
                Case (0x4E)
                {
                    DBG8 = 0x4E
                    If (ATKP)
                    {
                        ^^^^ATKD.IANE (0x4E)
                    }
                }
                Default
                {
                    Return (Zero)
                }

            }

            Return (One)
        }
    }

    Name (OSYS, 0x07DF)
    Scope (_SB)
    {
        Device (SLPB)
        {
            Name (_HID, EisaId ("PNP0C0E") /* Sleep Button Device */)  // _HID: Hardware ID
            Name (_STA, 0x0B)  // _STA: Status
        }
    }

    Scope (_SB)
    {
        Method (BRTN, 1, Serialized)
        {
            Notify (^PCI0.GPPA.VGA.LCD, Arg0)
            Notify (^PCI0.GPP9.PEGP.EDP1, Arg0)
        }
    }

    Scope (_SB)
    {
        Method (P8XH, 2, Serialized)
        {
        }
    }

    Scope (_SB)
    {
        Method (PSTC, 1, Serialized)
        {
            Return (Zero)
        }
    }

    Scope (_SB.ATKD)
    {
        Method (CRFC, 0, NotSerialized)
        {
            Return (Ones)
        }
    }

    Scope (_SB.ATKD)
    {
        Method (SRSC, 1, NotSerialized)
        {
            Return (One)
        }
    }

    Scope (_SB.ATKD)
    {
        Method (FANL, 1, Serialized)
        {
            Return (One)
        }

        Method (GQFS, 0, NotSerialized)
        {
            Return (0x00020000)
        }
    }

    Scope (_SB.ATKD)
    {
        Method (MAKY, 0, NotSerialized)
        {
            Return (Zero)
        }

        Method (BSTS, 0, NotSerialized)
        {
            If (ACPF)
            {
                Local0 = Zero
            }
            Else
            {
                Local0 = Zero
            }

            Return (Local0)
        }

        Method (WDOG, 1, NotSerialized)
        {
            Return (Zero)
        }

        Method (WLED, 1, NotSerialized)
        {
            Return (Zero)
        }

        Method (BLED, 1, NotSerialized)
        {
            Return (Zero)
        }

        Method (WMXC, 1, NotSerialized)
        {
            Return (Zero)
        }

        Method (OWGD, 1, Serialized)
        {
        }
    }

    Scope (_SB.ATKD)
    {
        Method (WCHK, 2, Serialized)
        {
            WNVA = 0x9603
            WNVB = One
            WNVC = Arg1
            WNVD = Arg0
            Return (W15H ())
        }
    }

    Scope (_SB)
    {
        Device (ARL2)
        {
            Name (_HID, "ASUS9001")  // _HID: Hardware ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((AACI == One))
                {
                    Return (0x0F)
                }

                Return (Zero)
            }
        }
    }

    Scope (_SB)
    {
        Device (ASUP)
        {
            Name (_HID, "ASUS2018")  // _HID: Hardware ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }
        }
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (_QB4, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0xB4
            If (ATKP)
            {
                ^^^^ATKD.IANE (0xE5)
            }
        }
    }

    Scope (_SB)
    {
        Device (ACAD)
        {
            Name (_HID, "ACPI0003" /* Power Source Device */)  // _HID: Hardware ID
            Name (_PCL, Package (0x01)  // _PCL: Power Consumer List
            {
                _SB, 
            })
            Name (XX00, Buffer (0x03){})
            Name (ACSB, One)
            Name (ACDC, 0xFF)
            Name (ACP, Ones)
            Method (_PSR, 0, NotSerialized)  // _PSR: Power Source
            {
                If (^^PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0500)
                    Local0 = ^^PCI0.SBRG.EC0.ACIN /* \_SB_.PCI0.SBRG.EC0_.ACIN */
                    Local1 = ^^PCI0.SBRG.EC0.NOAC /* \_SB_.PCI0.SBRG.EC0_.NOAC */
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    If ((Local1 == One))
                    {
                        Return (Zero)
                    }

                    If (((Local0 != ACDC) || (ACDC == 0xFF)))
                    {
                        CreateWordField (XX00, Zero, SSZE)
                        CreateByteField (XX00, 0x02, ACST)
                        SSZE = 0x03
                        If (Local0)
                        {
                            AFN4 (One)
                            ACST = Zero
                        }
                        Else
                        {
                            AFN4 (0x02)
                            ACST = One
                        }

                        ALIB (One, XX00)
                        ACDC = Local0
                    }

                    ACSB = Local0
                    Return (Local0)
                }

                Return (One)
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }
        }
    }

    Scope (_TZ)
    {
        Name (CUTR, Zero)
        Name (TCRT, 0x7C)
        Name (TAC0, 0x3C)
        Name (TPSV, 0x6E)
        Name (TPTM, 0x0CA0)
        Name (TTMP, 0x0C82)
        Name (TBSE, 0x0AAC)
        Name (FANP, Zero)
        PowerResource (QFAN, 0x00, 0x0000)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (FANP) /* \_TZ_.FANP */
            }

            Method (_ON, 0, NotSerialized)  // _ON_: Power On
            {
                FANP = One
            }

            Method (_OFF, 0, NotSerialized)  // _OFF: Power Off
            {
                FANP = Zero
            }
        }

        Device (FAN)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
            {
                QFAN, 
            })
        }

        ThermalZone (THRM)
        {
            Name (_AL0, Package (0x01)  // _ALx: Active List, x=0-9
            {
                FAN, 
            })
            Method (_PSL, 0, Serialized)  // _PSL: Passive List
            {
                Return (Package (0x18)
                {
                    \_SB.PLTF.C000, , 
                    \_SB.PLTF.C001, , 
                    \_SB.PLTF.C002, , 
                    \_SB.PLTF.C003, , 
                    \_SB.PLTF.C004, , 
                    \_SB.PLTF.C005, , 
                    \_SB.PLTF.C006, , 
                    \_SB.PLTF.C007, , 
                    \_SB.PLTF.C008, , 
                    \_SB.PLTF.C009, , 
                    \_SB.PLTF.C00A, , 
                    \_SB.PLTF.C00B, , 
                    \_SB.PLTF.C00C, , 
                    \_SB.PLTF.C00D, , 
                    \_SB.PLTF.C00E, , 
                    \_SB.PLTF.C00F, , 
                    \_SB.PLTF.C010, , 
                    \_SB.PLTF.C011, , 
                    \_SB.PLTF.C012, , 
                    \_SB.PLTF.C013, , 
                    \_SB.PLTF.C014, , 
                    \_SB.PLTF.C015, , 
                    \_SB.PLTF.C016, , 
                    \_SB.PLTF.C017, 
                })
            }

            Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
            {
                Return (KELV (TAC0))
            }

            Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
            {
                Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1000)
                Local0 = \_SB.PCI0.SBRG.EC0.HBAT
                Release (\_SB.PCI0.SBRG.EC0.MUT0)
                Return (KELV (Local0))
            }

            Name (FIST, One)
            Method (_TMP, 0, NotSerialized)  // _TMP: Temperature
            {
                If (FIST)
                {
                    FIST = Zero
                    Return (TPTM) /* \_TZ_.TPTM */
                }

                If (\_SB.PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1000)
                    If ((\_SB.PCI0.SBRG.EC0.HBHT == One))
                    {
                        Local1 = \_SB.PCI0.SBRG.EC0.CLOT
                    }
                    Else
                    {
                        Local1 = \_SB.PCI0.SBRG.EC0.CTMP
                    }

                    TTMP = ((Local1 * 0x0A) + TBSE) /* \_TZ_.TBSE */
                    If ((TTMP == Zero))
                    {
                        TTMP = TPTM /* \_TZ_.TPTM */
                    }

                    If ((TTMP > 0x0E94))
                    {
                        If ((CUTR < 0x03))
                        {
                            TTMP = 0x0E80
                        }

                        CUTR += One /* \_TZ_.CUTR */
                    }
                    Else
                    {
                        CUTR = Zero
                    }

                    Release (\_SB.PCI0.SBRG.EC0.MUT0)
                    Return (TTMP) /* \_TZ_.TTMP */
                }
                Else
                {
                    Return (TPTM) /* \_TZ_.TPTM */
                }
            }

            Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
            {
                Return (KELV (TPSV))
            }

            Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
            {
                Return (KELV (TCRT))
            }

            Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
            {
                If ((Arg0 == Zero))
                {
                    Debug = "THERM: _SCP(Active)"
                }
                Else
                {
                    Debug = "THERM: _SCP(Passive)"
                }
            }

            Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
            Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
            Name (_TSP, 0x64)  // _TSP: Thermal Sampling Period
        }

        Method (KELV, 1, NotSerialized)
        {
            If ((Arg0 & 0x80))
            {
                Local1 = 0xFFFFFF00
            }
            Else
            {
                Local1 = Zero
            }

            Local1 |= Arg0
            Local1 = ((Local1 * 0x0A) + 0x0AAC)
            Return (Local1)
        }
    }

    Scope (_SB)
    {
        Method (VTOB, 1, NotSerialized)
        {
            Local0 = One
            Local0 <<= Arg0
            Return (Local0)
        }

        Method (BTOV, 1, NotSerialized)
        {
            Local0 = (Arg0 >> One)
            Local1 = Zero
            While (Local0)
            {
                Local1++
                Local0 >>= One
            }

            Return (Local1)
        }

        Method (MKWD, 2, NotSerialized)
        {
            If ((Arg1 & 0x80))
            {
                Local0 = 0xFFFF0000
            }
            Else
            {
                Local0 = Zero
            }

            Local0 |= Arg0
            Local0 |= (Arg1 << 0x08)
            Return (Local0)
        }

        Method (GBFE, 3, NotSerialized)
        {
            CreateByteField (Arg0, Arg1, TIDX)
            Arg2 = TIDX /* \_SB_.GBFE.TIDX */
        }

        Method (PBFE, 3, NotSerialized)
        {
            CreateByteField (Arg0, Arg1, TIDX)
            TIDX = Arg2
        }

        Method (ITOS, 1, NotSerialized)
        {
            Local0 = Buffer (0x09)
                {
                    "        "
                }
            Local7 = Buffer (0x11)
                {
                    "0123456789ABCDEF"
                }
            Local1 = 0x08
            Local2 = Zero
            Local3 = Zero
            While (Local1)
            {
                Local1--
                Local4 = ((Arg0 >> (Local1 << 0x02)) & 0x0F)
                If (Local4)
                {
                    Local3 = Ones
                }

                If (Local3)
                {
                    GBFE (Local7, Local4, RefOf (Local5))
                    PBFE (Local0, Local2, Local5)
                    Local2++
                }
            }

            Return (Local0)
        }

        Mutex (MUT1, 0x00)
        Name (SEL0, 0xF0)
        Device (BAT1)
        {
            Name (_HID, EisaId ("PNP0C0A") /* Control Method Battery */)  // _HID: Hardware ID
            Name (_UID, One)  // _UID: Unique ID
            Name (_PCL, Package (0x01)  // _PCL: Power Consumer List
            {
                _SB, 
            })
            Name (PBIF, Package (0x0D)
            {
                One, 
                0x05, 
                0x05, 
                One, 
                0x05, 
                0x64, 
                0x32, 
                0x40, 
                0x40, 
                "BAT1", 
                " ", 
                " ", 
                " "
            })
            Name (PBST, Package (0x04)
            {
                Zero, 
                0x05, 
                0x05, 
                0x2710
            })
            Name (BP, One)
            Name (TMPB, Zero)
            Name (TBAT, Zero)
            Name (MBSN, Zero)
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If (BP)
                {
                    Return (0x1F)
                }
                Else
                {
                    Return (0x0F)
                }
            }

            Method (_BIF, 0, NotSerialized)  // _BIF: Battery Information
            {
                If (^^PCI0.SBRG.EC0.ECOK)
                {
                    If (BP)
                    {
                        UPBI ()
                    }
                    Else
                    {
                        IVBI ()
                    }
                }

                Return (PBIF) /* \_SB_.BAT1.PBIF */
            }

            Method (_BST, 0, NotSerialized)  // _BST: Battery Status
            {
                If (^^PCI0.SBRG.EC0.ECOK)
                {
                    If (BP)
                    {
                        UPBS ()
                    }
                    Else
                    {
                        IVBS ()
                    }
                }

                Return (PBST) /* \_SB_.BAT1.PBST */
            }

            Method (_BTP, 1, NotSerialized)  // _BTP: Battery Trip Point
            {
                ALIB (0x18, Zero)
                If (^^PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x5000)
                    If ((Arg0 == Zero))
                    {
                        Local0 = Zero
                        Local1 = Zero
                    }
                    Else
                    {
                        Local0 = (Arg0 & 0xFF)
                        Local1 = (Arg0 >> 0x08)
                        Local1 &= 0xFF
                    }

                    ^^PCI0.SBRG.EC0.BTPL = Local0
                    ^^PCI0.SBRG.EC0.BTPH = Local1
                    Release (^^PCI0.SBRG.EC0.MUT0)
                }

                ALIB (0x18, One)
            }

            Method (UPBI, 0, NotSerialized)
            {
                Local0 = Zero
                Local1 = 0x0C
                ALIB (0x18, Zero)
                Sleep (0x05)
                Acquire (^^PCI0.SBRG.EC0.MUT0, 0x5000)
                Local2 = ^^PCI0.SBRG.EC0.MDCP /* \_SB_.PCI0.SBRG.EC0_.MDCP */
                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MDCP /* \_SB_.PCI0.SBRG.EC0_.MDCP */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MDCP /* \_SB_.PCI0.SBRG.EC0_.MDCP */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MDCP /* \_SB_.PCI0.SBRG.EC0_.MDCP */
                }

                Local2 &= 0xFFFF
                PBIF [One] = Local2
                Local2 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                }

                Local2 &= 0xFFFF
                PBIF [0x02] = Local2
                Local2 = ^^PCI0.SBRG.EC0.MBDV /* \_SB_.PCI0.SBRG.EC0_.MBDV */
                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x14)
                    Local2 = ^^PCI0.SBRG.EC0.MBDV /* \_SB_.PCI0.SBRG.EC0_.MBDV */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x14)
                    Local2 = ^^PCI0.SBRG.EC0.MBDV /* \_SB_.PCI0.SBRG.EC0_.MBDV */
                }

                If ((Local2 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local2 = ^^PCI0.SBRG.EC0.MBDV /* \_SB_.PCI0.SBRG.EC0_.MBDV */
                }

                Local2 &= 0xFFFF
                PBIF [0x04] = Local2
                Local2 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                Local3 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                Local3 *= 0x0A
                Divide (Local3, 0x64, Local4, Local3)
                PBIF [0x05] = Local3
                Local3 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                Local3 *= One
                Divide (Local3, 0x64, Local4, Local3)
                PBIF [0x06] = Local3
                PBIF [0x09] = "A32-K55"
                PBIF [0x0A] = " "
                PBIF [0x0B] = "LiON"
                PBIF [0x0C] = "ASUS "
                Local0 = Ones
                Release (^^PCI0.SBRG.EC0.MUT0)
                ALIB (0x18, One)
                Return (Local0)
            }

            Method (UPBS, 0, NotSerialized)
            {
                Local0 = Zero
                ALIB (0x18, Zero)
                Sleep (0x05)
                Acquire (^^PCI0.SBRG.EC0.MUT0, 0x5000)
                Local2 = ^^PCI0.SBRG.EC0.MBCT /* \_SB_.PCI0.SBRG.EC0_.MBCT */
                If ((Local2 & 0x8000))
                {
                    Local2 |= 0xFFFF0000
                    Local2 = (~Local2 + One)
                }

                Local3 = ^^PCI0.SBRG.EC0.MBVT /* \_SB_.PCI0.SBRG.EC0_.MBVT */
                If ((Local3 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local3 = ^^PCI0.SBRG.EC0.MBVT /* \_SB_.PCI0.SBRG.EC0_.MBVT */
                }

                If ((Local3 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local3 = ^^PCI0.SBRG.EC0.MBVT /* \_SB_.PCI0.SBRG.EC0_.MBVT */
                }

                If ((Local3 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local3 = ^^PCI0.SBRG.EC0.MBVT /* \_SB_.PCI0.SBRG.EC0_.MBVT */
                }

                Local5 = ^^PCI0.SBRG.EC0.RCAP /* \_SB_.PCI0.SBRG.EC0_.RCAP */
                If ((Local5 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local5 = ^^PCI0.SBRG.EC0.RCAP /* \_SB_.PCI0.SBRG.EC0_.RCAP */
                }

                If ((Local5 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local5 = ^^PCI0.SBRG.EC0.RCAP /* \_SB_.PCI0.SBRG.EC0_.RCAP */
                }

                If ((Local5 == 0xFFFF))
                {
                    Sleep (0x0A)
                    Local5 = ^^PCI0.SBRG.EC0.RCAP /* \_SB_.PCI0.SBRG.EC0_.RCAP */
                }

                Local5 &= 0xFFFF
                If ((Local2 != DerefOf (PBST [One])))
                {
                    PBST [One] = Local2
                    Local0 = Ones
                }

                If ((Local3 != DerefOf (PBST [0x03])))
                {
                    PBST [0x03] = Local3
                    Local0 = Ones
                }

                If ((Local5 != DerefOf (PBST [0x02])))
                {
                    PBST [0x02] = Local5
                    Local0 = Ones
                    Local6 = ^^PCI0.SBRG.EC0.MBCP /* \_SB_.PCI0.SBRG.EC0_.MBCP */
                    Local6 *= 0x05
                    Divide (Local6, 0x64, Local7, Local6)
                    If ((Local5 <= Local6))
                    {
                        Local7 = (Local5 & 0xFF)
                        ^^PCI0.SBRG.EC0.DBEA = Local7
                        Local7 = ((Local5 & 0xFF00) >> 0x08)
                        ^^PCI0.SBRG.EC0.DBEB = Local7
                    }
                }

                Local4 = Zero
                If ((0x0C00 & TBAT))
                {
                    Sleep (0x05)
                    If ((^^PCI0.SBRG.EC0.BHCH == 0x50))
                    {
                        If (^^PCI0.SBRG.EC0.BHPE)
                        {
                            Local4 &= 0xFFF7
                        }
                        Else
                        {
                            Local4 |= 0x08
                        }
                    }
                    Else
                    {
                        Local4 &= 0xFFF7
                    }

                    Local4 |= 0x02
                }
                Else
                {
                    If ((0x0100 & TBAT))
                    {
                        Local4 &= 0xFFF7
                        Local4 |= One
                    }

                    If ((^^PCI0.SBRG.EC0.BHCH == 0x50))
                    {
                        If (^^PCI0.SBRG.EC0.BHPE)
                        {
                            Local4 &= 0xFFF7
                        }
                        Else
                        {
                            Local4 |= 0x08
                        }
                    }
                    Else
                    {
                        Local4 &= 0xFFF7
                    }
                }

                If ((Local4 != DerefOf (PBST [Zero])))
                {
                    If ((^^PCI0.SBRG.EC0.BHCH == 0x50))
                    {
                        If (^^PCI0.SBRG.EC0.BHPE)
                        {
                            Local4 &= 0xFFF7
                        }
                        Else
                        {
                            Local4 |= 0x08
                        }
                    }
                    Else
                    {
                        Local4 &= 0xFFF7
                    }

                    PBST [Zero] = Local4
                    Local0 = Ones
                }

                ALIB (0x18, One)
                Release (^^PCI0.SBRG.EC0.MUT0)
                Return (Local0)
            }

            Method (IVBI, 0, NotSerialized)
            {
                PBIF [One] = 0x05
                PBIF [0x02] = 0x05
                PBIF [0x04] = 0x05
                PBIF [0x09] = "Bad"
                PBIF [0x0A] = "Bad"
                PBIF [0x0B] = "Bad"
                PBIF [0x0C] = "Bad"
            }

            Method (IVBS, 0, NotSerialized)
            {
                PBST [Zero] = Zero
                PBST [One] = 0x05
                PBST [0x02] = 0x05
                PBST [0x03] = 0x2710
            }

            Method (CHBP, 1, NotSerialized)
            {
                Local0 = Zero
                Local1 = VTOB ((_UID - One))
                TBAT = Arg0
                If ((Arg0 & Local1))
                {
                    If (BP){}
                    Else
                    {
                        Sleep (0x03E8)
                        BP = One
                    }
                }
                ElseIf (BP)
                {
                    BP = Zero
                }
            }
        }
    }

    Scope (_SB.I2CA)
    {
        Device (TPD1)
        {
            Method (_HID, 0, Serialized)  // _HID: Hardware ID
            {
                If ((TPID == One))
                {
                    Return ("ASUF1208")
                }

                If ((TPID == 0x02))
                {
                    Return ("ASCE1206")
                }

                If ((TPID == 0x03))
                {
                    Return ("ASUP1208")
                }

                Return ("ASUP1208")
            }

            Name (_CID, "PNP0C50" /* HID Protocol Device (I2C bus) */)  // _CID: Compatible ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0015, ControllerInitiated, 0x00061A80,
                        AddressingMode7Bit, "\\_SB.I2CA",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioInt (Level, ActiveLow, ExclusiveAndWake, PullUp, 0x0000,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0008
                        }
                })
                Return (RBUF) /* \_SB_.I2CA.TPD1._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }

            Method (_DSW, 3, NotSerialized)  // _DSW: Device Sleep Wake
            {
                If (Arg0){}
                Else
                {
                }
            }

            Method (_PS0, 0, NotSerialized)  // _PS0: Power State 0
            {
            }

            Method (_PS3, 0, NotSerialized)  // _PS3: Power State 3
            {
            }

            Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
            {
                If ((Arg0 == ToUUID ("3cdff6f7-4267-4555-ad05-b30a3d8938de") /* HID I2C Device */))
                {
                    Switch (ToInteger (Arg2))
                    {
                        Case (Zero)
                        {
                            Switch (ToInteger (Arg1))
                            {
                                Case (One)
                                {
                                    Return (Buffer (One)
                                    {
                                         0x03                                             // .
                                    })
                                }
                                Default
                                {
                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                }

                            }
                        }
                        Case (One)
                        {
                            Return (One)
                        }
                        Default
                        {
                            Return (Zero)
                        }

                    }
                }
                Else
                {
                    Return (Buffer (One)
                    {
                         0x00                                             // .
                    })
                }
            }
        }
    }

    Scope (_SB.I2CB)
    {
        Device (SPKR)
        {
            Name (_HID, "CSC3556")  // _HID: Hardware ID
            Name (_SUB, "10431024")  // _SUB: Subsystem ID
            Name (_UID, One)  // _UID: Unique ID
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Name (RBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0030, ControllerInitiated, 0x000F4240,
                        AddressingMode7Bit, "\\_SB.I2CB",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    I2cSerialBusV2 (0x0031, ControllerInitiated, 0x000F4240,
                        AddressingMode7Bit, "\\_SB.I2CB",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    I2cSerialBusV2 (0x003A, ControllerInitiated, 0x000F4240,
                        AddressingMode7Bit, "\\_SB.I2CB",
                        0x00, ResourceConsumer, , Exclusive,
                        )
                    GpioIo (Exclusive, PullDown, 0x0000, 0x0000, IoRestrictionOutputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0018
                        }
                    GpioIo (Exclusive, PullUp, 0x0000, 0x0000, IoRestrictionInputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0068
                        }
                    GpioIo (Shared, PullUp, 0x0064, 0x0000, IoRestrictionInputOnly,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0012
                        }
                    GpioInt (Edge, ActiveBoth, Shared, PullUp, 0x0064,
                        "\\_SB.GPIO", 0x00, ResourceConsumer, ,
                        )
                        {   // Pin list
                            0x0012
                        }
                })
                Return (RBUF) /* \_SB_.I2CB.SPKR._CRS.RBUF */
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }

            Method (_DIS, 0, NotSerialized)  // _DIS: Disable Device
            {
            }

            Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x04)
                {
                    Package (0x02)
                    {
                        "cirrus,dev-index", 
                        Package (0x02)
                        {
                            0x30, 
                            0x31
                        }
                    }, 

                    Package (0x02)
                    {
                        "cirrus,boost-type", 
                        Package (0x02)
                        {
                            Zero, 
                            Zero
                        }
                    }, 

                    Package (0x02)
                    {
                        "reset-gpios", 
                        Package (0x08)
                        {
                            SPKR, , 
                            Zero, 
                            Zero, 
                            Zero, 
                            SPKR, , 
                            Zero, 
                            Zero, 
                            Zero
                        }
                    }, 

                    Package (0x02)
                    {
                        "spk-id-gpios", 
                        Package (0x08)
                        {
                            SPKR, , 
                            One, 
                            Zero, 
                            Zero, 
                            SPKR, , 
                            One, 
                            Zero, 
                            Zero
                        }
                    }
                }
            })
        }
    }

    Scope (_SB.PCI0.GPPC.XHC0)
    {
        Device (RHUB)
        {
            Name (_ADR, Zero)  // _ADR: Address
            Device (PRT1)
            {
                Name (_ADR, One)  // _ADR: Address
                Name (UPC1, Package (0x04)
                {
                    0xFF, 
                    0x03, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC1) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT1.UPC1 */
                }

                Name (PLD1, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x0D, 0x00, 0x07, 0x00,  // ........
                        /* 0008 */  0x51, 0x09, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00,  // Q.......
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD1) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT1.PLD1 */
                }
            }

            Device (PRT2)
            {
                Name (_ADR, 0x02)  // _ADR: Address
                Name (UPC2, Package (0x04)
                {
                    0xFF, 
                    0x03, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC2) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT2.UPC2 */
                }

                Name (PLD2, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x0D, 0x00, 0x07, 0x00,  // ........
                        /* 0008 */  0x51, 0x09, 0x08, 0x00, 0x01, 0x00, 0x00, 0x00,  // Q.......
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD2) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT2.PLD2 */
                }
            }

            Device (PRT3)
            {
                Name (_ADR, 0x03)  // _ADR: Address
                Name (UPC3, Package (0x04)
                {
                    Zero, 
                    0xFF, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC3) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT3.UPC3 */
                }

                Name (PLD3, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x11, 0x1C, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD3) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT3.PLD3 */
                }
            }

            Device (PRT4)
            {
                Name (_ADR, 0x04)  // _ADR: Address
                Name (UPC4, Package (0x04)
                {
                    Zero, 
                    0xFF, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC4) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT4.UPC4 */
                }

                Name (PLD4, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x91, 0x1C, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD4) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT4.PLD4 */
                }
            }

            Device (PRT5)
            {
                Name (_ADR, 0x05)  // _ADR: Address
                Name (UPC5, Package (0x04)
                {
                    Zero, 
                    0xFF, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC5) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT5.UPC5 */
                }

                Name (PLD5, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x11, 0x1C, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD5) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT5.PLD5 */
                }
            }

            Device (PRT6)
            {
                Name (_ADR, 0x06)  // _ADR: Address
                Name (UPC6, Package (0x04)
                {
                    0xFF, 
                    0x03, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC6) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT6.UPC6 */
                }

                Name (PLD6, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x0D, 0x00, 0x07, 0x00,  // ........
                        /* 0008 */  0x51, 0x09, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00,  // Q.......
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD6) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT6.PLD6 */
                }
            }

            Device (PRT7)
            {
                Name (_ADR, 0x07)  // _ADR: Address
                Name (UPC7, Package (0x04)
                {
                    0xFF, 
                    0x03, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC7) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT7.UPC7 */
                }

                Name (PLD7, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x0D, 0x00, 0x07, 0x00,  // ........
                        /* 0008 */  0x51, 0x09, 0x08, 0x00, 0x01, 0x00, 0x00, 0x00,  // Q.......
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD7) /* \_SB_.PCI0.GPPC.XHC0.RHUB.PRT7.PLD7 */
                }
            }
        }
    }

    Scope (_SB.PCI0.GPPA.XHC1)
    {
        Device (RHUB)
        {
            Name (_ADR, Zero)  // _ADR: Address
            Device (PRT1)
            {
                Name (_ADR, One)  // _ADR: Address
                Name (UPC1, Package (0x04)
                {
                    Zero, 
                    0xFF, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC1) /* \_SB_.PCI0.GPPA.XHC1.RHUB.PRT1.UPC1 */
                }
            }

            Device (PRT2)
            {
                Name (_ADR, 0x02)  // _ADR: Address
                Name (UPC2, Package (0x04)
                {
                    Zero, 
                    0xFF, 
                    Zero, 
                    Zero
                })
                Method (_UPC, 0, Serialized)  // _UPC: USB Port Capabilities
                {
                    Return (UPC2) /* \_SB_.PCI0.GPPA.XHC1.RHUB.PRT2.UPC2 */
                }

                Name (PLD2, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x91, 0x1C, 0x80, 0x01, 0x01, 0x00, 0x00, 0x00,  // ........
                        /* 0010 */  0xFF, 0xFF, 0xFF, 0xFF                           // ....
                    }
                })
                Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
                {
                    Return (PLD2) /* \_SB_.PCI0.GPPA.XHC1.RHUB.PRT2.PLD2 */
                }
            }
        }
    }

    Scope (_SB)
    {
        Method (GBTR, 0, NotSerialized)
        {
            Sleep (0x32)
            Acquire (^PCI0.SBRG.EC0.MUT0, 0x0500)
            Local0 = ^PCI0.SBRG.EC0.BTCN /* \_SB_.PCI0.SBRG.EC0_.BTCN */
            Release (^PCI0.SBRG.EC0.MUT0)
            Return (Local0)
        }

        Method (BTRK, 1, NotSerialized)
        {
            Acquire (^PCI0.SBRG.EC0.MUT0, 0x1000)
            ^PCI0.SBRG.EC0.BTCN = Arg0
            Release (^PCI0.SBRG.EC0.MUT0)
        }

        PowerResource (DBTP, 0x00, 0x0000)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                If ((GBTR () == One))
                {
                    Return (One)
                }
                Else
                {
                    Return (Zero)
                }
            }

            Method (_ON, 0, NotSerialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, NotSerialized)  // _OFF: Power Off
            {
            }
        }
    }

    Scope (_SB.PCI0.GPPC.XHC0.RHUB.PRT3)
    {
        Method (_PRR, 0, NotSerialized)  // _PRR: Power Resource for Reset
        {
            Return (Package (0x01)
            {
                BTRT, 
            })
        }

        PowerResource (BTRT, 0x05, 0x0000)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (One)
            }

            Method (_ON, 0, NotSerialized)  // _ON_: Power On
            {
            }

            Method (_OFF, 0, NotSerialized)  // _OFF: Power Off
            {
            }

            Method (_RST, 0, NotSerialized)  // _RST: Device Reset
            {
                BTRK (Zero)
                Sleep (0xC8)
                BTRK (One)
            }
        }

        Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
        {
            DBTP, 
        })
        Name (_PR2, Package (0x01)  // _PR2: Power Resources for D2
        {
            DBTP, 
        })
        Name (_PR3, Package (0x01)  // _PR3: Power Resources for D3hot
        {
            DBTP, 
        })
        Name (_S0W, 0x02)  // _S0W: S0 Device Wake State
    }

    Scope (_SB.PCI0.GPP9)
    {
        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            Name (M432, Zero)
            Name (M433, Zero)
            If ((Arg0 == ToUUID ("e5c937d0-3553-4d7a-9117-ea4d19c3434d") /* Device Labeling Interface */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Name (M435, Buffer (0x02)
                        {
                             0x00, 0x00                                       // ..
                        })
                        CreateBitField (M435, Zero, M436)
                        CreateBitField (M435, 0x05, M445)
                        CreateBitField (M435, 0x0A, M437)
                        CreateBitField (M435, 0x0B, M438)
                        If ((Arg1 >= 0x04))
                        {
                            M436 = One
                            M445 = One
                            M437 = One
                            M438 = One
                        }
                        Else
                        {
                            M436 = One
                            M445 = One
                        }

                        Return (M435) /* \_SB_.PCI0.GPP9._DSM.M435 */
                    }
                    Case (0x05)
                    {
                        Return (Zero)
                    }
                    Case (0x0A)
                    {
                        Return (One)
                    }
                    Case (0x0B)
                    {
                        Local0 = ToInteger (Arg3)
                        If ((Local0 <= 0x2710))
                        {
                            Return (Local0)
                        }
                    }
                    Default
                    {
                        Return (Zero)
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB)
    {
        Method (GSRV, 1, Serialized)
        {
            Return (M249 (Zero, Zero, Zero, Arg0))
        }
    }

    Scope (\)
    {
        Name (DPDT, 0x05)
        Name (HDDT, 0x10)
    }

    Scope (_SB)
    {
        Device (LID0)
        {
            Name (_HID, EisaId ("PNP0C0D") /* Lid Device */)  // _HID: Hardware ID
            Method (_LID, 0, NotSerialized)  // _LID: Lid Status
            {
                If (^^PCI0.SBRG.EC0.ECOK)
                {
                    Acquire (^^PCI0.SBRG.EC0.MUT0, 0x0200)
                    Local1 = ^^PCI0.SBRG.EC0.LIDS /* \_SB_.PCI0.SBRG.EC0_.LIDS */
                    Release (^^PCI0.SBRG.EC0.MUT0)
                    If (Local1)
                    {
                        Return (Zero)
                    }
                    Else
                    {
                        Return (One)
                    }
                }
                Else
                {
                    Return (One)
                }
            }
        }
    }

    Scope (_SB.PCI0.GPPA.XHC1.RHUB.PRT1)
    {
        Device (WCAM)
        {
            Name (_ADR, One)  // _ADR: Address
            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
            {
                Name (PLDP, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x24, 0x1D, 0x80, 0x03, 0x00, 0x00, 0x00, 0x00,  // $.......
                        /* 0010 */  0x10, 0x01, 0xC0, 0x00                           // ....
                    }
                })
                Return (PLDP) /* \_SB_.PCI0.GPPA.XHC1.RHUB.PRT1.WCAM._PLD.PLDP */
            }
        }

        Device (CAM2)
        {
            Name (_ADR, 0x03)  // _ADR: Address
            Method (_PLD, 0, Serialized)  // _PLD: Physical Location of Device
            {
                Name (PLDP, Package (0x01)
                {
                    Buffer (0x14)
                    {
                        /* 0000 */  0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                        /* 0008 */  0x24, 0x1D, 0x80, 0x03, 0x00, 0x00, 0x00, 0x00,  // $.......
                        /* 0010 */  0x10, 0x01, 0xC0, 0x00                           // ....
                    }
                })
                Return (PLDP) /* \_SB_.PCI0.GPPA.XHC1.RHUB.PRT1.CAM2._PLD.PLDP */
            }
        }
    }

    Scope (_SB.PCI0.GPP5.WLAN)
    {
        Name (_S0W, 0x03)  // _S0W: S0 Device Wake State
        Name (WPLS, One)
        PowerResource (WRST, 0x05, 0x0000)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (WPLS) /* \_SB_.PCI0.GPP5.WLAN.WPLS */
            }

            Method (_ON, 0, NotSerialized)  // _ON_: Power On
            {
                WPLS = One
            }

            Method (_OFF, 0, NotSerialized)  // _OFF: Power Off
            {
                WPLS = Zero
            }

            Method (_RST, 0, NotSerialized)  // _RST: Device Reset
            {
                Acquire (^^^^SBRG.EC0.MUT0, 0x0500)
                ^^^^SBRG.EC0.WLRY = Zero
                Release (^^^^SBRG.EC0.MUT0)
                Sleep (0xC8)
                Acquire (^^^^SBRG.EC0.MUT0, 0x0500)
                ^^^^SBRG.EC0.WLRY = One
                Release (^^^^SBRG.EC0.MUT0)
            }
        }

        Name (_PRR, Package (0x01)  // _PRR: Power Resource for Reset
        {
            WRST, 
        })
        Method (MTDS, 0, Serialized)
        {
            Name (MDSB, Package (0x1F)
            {
                0x4D, 
                0x54, 
                0x44, 
                0x53, 
                0x02, 
                Zero, 
                0x02, 
                One, 
                0x1F, 
                0x1C, 
                0x1C, 
                0x1C, 
                0x1C, 
                0x21, 
                0x21, 
                0x1F, 
                0x1D, 
                0x1D, 
                0x1D, 
                0x02, 
                0x1F, 
                0x1C, 
                0x1C, 
                0x1C, 
                0x1C, 
                0x21, 
                0x21, 
                0x1F, 
                0x1D, 
                0x1D, 
                0x1D
            })
            Return (MDSB) /* \_SB_.PCI0.GPP5.WLAN.MTDS.MDSB */
        }

        Method (MTGS, 0, Serialized)
        {
            Name (MGSB, Package (0x31)
            {
                0x4D, 
                0x54, 
                0x47, 
                0x53, 
                0x04, 
                Zero, 
                0x06, 
                One, 
                0x3B, 
                Zero, 
                0x3B, 
                Zero, 
                0x3B, 
                Zero, 
                0x02, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x03, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x04, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x05, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x06, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B, 
                0x3B
            })
            Return (MGSB) /* \_SB_.PCI0.GPP5.WLAN.MTGS.MGSB */
        }

        Method (MTCL, 0, Serialized)
        {
            Name (MLSB, Package (0x1A)
            {
                0x4D, 
                0x54, 
                0x43, 
                0x4C, 
                0x03, 
                One, 
                0xF9, 
                0xCF, 
                0xC7, 
                0xD8, 
                Zero, 
                Zero, 
                One, 
                Zero, 
                0x80, 
                Zero, 
                0x08, 
                Zero, 
                Zero, 
                One, 
                Zero, 
                0x20, 
                0xFD, 
                0xC0, 
                Zero, 
                Zero
            })
            Return (MLSB) /* \_SB_.PCI0.GPP5.WLAN.MTCL.MLSB */
        }

        Method (MTAS, 0, Serialized)
        {
            Name (MTAB, Package (0x0C)
            {
                0x4D, 
                0x54, 
                0x41, 
                0x53, 
                One, 
                Zero, 
                0x60, 
                Zero, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            })
            Return (MTAB) /* \_SB_.PCI0.GPP5.WLAN.MTAS.MTAB */
        }

        Method (MTSP, 0, Serialized)
        {
            Name (MTSB, Package (0x0C)
            {
                0x4D, 
                0x54, 
                0x53, 
                0x50, 
                One, 
                One, 
                0x60, 
                Zero, 
                Zero, 
                Zero, 
                Zero, 
                Zero
            })
            Return (MTSB) /* \_SB_.PCI0.GPP5.WLAN.MTSP.MTSB */
        }
    }

    Scope (_SB.PCI0)
    {
        Device (AWMI)
        {
            Name (_HID, "PNP0C14" /* Windows Management Instrumentation Device */)  // _HID: Hardware ID
            Name (_UID, "0x00")  // _UID: Unique ID
            Name (_WDG, Buffer (0x28)
            {
                /* 0000 */  0x13, 0x96, 0x3E, 0x60, 0x25, 0xEF, 0x38, 0x43,  // ..>`%.8C
                /* 0008 */  0xA3, 0xD0, 0xC4, 0x61, 0x77, 0x51, 0x6D, 0xB7,  // ...awQm.
                /* 0010 */  0x41, 0x41, 0x01, 0x02, 0x21, 0x12, 0x90, 0x05,  // AA..!...
                /* 0018 */  0x66, 0xD5, 0xD1, 0x11, 0xB2, 0xF0, 0x00, 0xA0,  // f.......
                /* 0020 */  0xC9, 0x06, 0x29, 0x10, 0x30, 0x30, 0x01, 0x00   // ..).00..
            })
            Method (WMAA, 3, Serialized)
            {
                CreateByteField (Arg2, Zero, MODF)
                CreateDWordField (Arg2, 0x04, LEDB)
                Switch (Arg1)
                {
                    Case (One)
                    {
                        If ((MODF == Zero))
                        {
                            LEDB = ^^SBRG.EC0.GBLD /* \_SB_.PCI0.SBRG.EC0_.GBLD */
                            Return (LEDB) /* \_SB_.PCI0.AWMI.WMAA.LEDB */
                        }
                        ElseIf ((MODF == One))
                        {
                            ^^SBRG.EC0.SBLD = LEDB /* \_SB_.PCI0.AWMI.WMAA.LEDB */
                            Return (Zero)
                        }
                        ElseIf ((MODF == 0x02))
                        {
                            Return (0xC8)
                        }
                        Else
                        {
                            Return (One)
                        }
                    }
                    Case (0x02)
                    {
                        If ((MODF == Zero))
                        {
                            If ((^^SBRG.EC0.G40C == One))
                            {
                                Return (0x03)
                            }
                            Else
                            {
                                Return (0x03)
                            }
                        }
                        ElseIf ((MODF == One))
                        {
                            If ((LEDB < 0x03))
                            {
                                Return (Zero)
                            }

                            Return (One)
                        }
                        Else
                        {
                            Return (One)
                        }
                    }
                    Default
                    {
                        Return (One)
                    }

                }
            }
        }
    }

    Scope (_TZ.FAN)
    {
        Name (LRPM, Zero)
        Name (URPM, Zero)
        Name (CFST, Package (0x03)
        {
            Zero, 
            Zero, 
            Zero
        })
        Name (GRAN, 0x01F4)
        Name (FOPR, Package (0x04)
        {
            One, 
            0x08FC, 
            0x0A28, 
            0x0BB8
        })
        Method (CRNF, 0, NotSerialized)
        {
            Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1000)
            \_SB.PCI0.SBRG.EC0.LRP1 = LRPM /* \_TZ_.FAN_.LRPM */
            Release (\_SB.PCI0.SBRG.EC0.MUT0)
            Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1000)
            \_SB.PCI0.SBRG.EC0.URP1 = URPM /* \_TZ_.FAN_.URPM */
            Release (\_SB.PCI0.SBRG.EC0.MUT0)
        }

        Method (GCFR, 0, NotSerialized)
        {
            Acquire (\_SB.PCI0.SBRG.EC0.MUT0, 0x1000)
            Local0 = \_SB.PCI0.SBRG.EC0.FRMS
            Release (\_SB.PCI0.SBRG.EC0.MUT0)
            Return (Local0)
        }

        Method (_FST, 0, NotSerialized)  // _FST: Fan Status
        {
            Local0 = GCFR ()
            CFST [0x02] = Local0
            If ((Local0 > DerefOf (FOPR [0x02])))
            {
                CFST [One] = 0x04
            }
            ElseIf ((Local0 > DerefOf (FOPR [One])))
            {
                CFST [One] = 0x03
            }
            ElseIf ((Local0 > DerefOf (FOPR [Zero])))
            {
                CFST [One] = 0x02
            }
            ElseIf ((Local0 <= DerefOf (FOPR [Zero])))
            {
                CFST [One] = One
            }

            Return (CFST) /* \_TZ_.FAN_.CFST */
        }

        Method (SFST, 0, NotSerialized)
        {
            Notify (FAN, 0x80) // Status Change
        }

        Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
        {
            If ((Arg0 == ToUUID ("a7611840-99fe-41ae-a488-35c75926c8eb") /* Fan Trip Points */))
            {
                Switch (ToInteger (Arg2))
                {
                    Case (Zero)
                    {
                        Return (Buffer (One)
                        {
                             0x0F                                             // .
                        })
                    }
                    Case (One)
                    {
                        Return (GRAN) /* \_TZ_.FAN_.GRAN */
                    }
                    Case (0x02)
                    {
                        LRPM = DerefOf (Arg3 [Zero])
                        URPM = DerefOf (Arg3 [One])
                        CRNF ()
                        Return (Zero)
                    }
                    Case (0x03)
                    {
                        Return (FOPR) /* \_TZ_.FAN_.FOPR */
                    }
                    Default
                    {
                        Return (Buffer (One)
                        {
                             0x00                                             // .
                        })
                    }

                }
            }
            Else
            {
                Return (Buffer (One)
                {
                     0x00                                             // .
                })
            }
        }
    }

    Scope (_SB.PCI0.SBRG.EC0)
    {
        Method (_Q7A, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0x7A
            If ((VIUF == One))
            {
                Notify (^^^GPP9.PEGP, 0x81) // Information Change
            }
        }

        Method (_QA8, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0xA8
            If ((DB2F == Zero))
            {
                ^^^^NPCF.DBAC = One
                ^^^^NPCF.DBDC = One
            }

            If ((DB2F == One))
            {
                ^^^^NPCF.DBAC = Zero
                ^^^^NPCF.DBDC = Zero
            }

            Notify (NPCF, 0xC0) // Hardware-Specific
        }

        Method (_QA9, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            DBG8 = 0xA9
            FGA9 = Zero
            Sleep (0x1770)
            Notify (^^^GPP9.PEGP, Zero) // Bus Check
        }

        Method (_QBC, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            If ((UMFG != One))
            {
                DNOT (NVDX)
            }
        }

        Method (_QB6, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            Sleep (0x64)
            STPL ()
        }

        Method (_QD4, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            QD4F = Zero
            If ((TGSF == One))
            {
                TGSF = Zero
                If ((MNMS == Zero))
                {
                    If ((FTBL == 0x02))
                    {
                        CPUP (0xC8)
                        DNOT (0x02)
                        SSDM ()
                    }
                    ElseIf ((FTBL == Zero))
                    {
                        CPUP (0xF0)
                        SPDM ()
                    }
                    Else
                    {
                        CPUP (0x0118)
                        STDM ()
                    }

                    Notify (NPCF, 0xC0) // Hardware-Specific
                    Sleep (0x64)
                    WMSH ()
                    Sleep (0x64)
                    STPL ()
                }
                Else
                {
                    MNMS = Zero
                }
            }
            Else
            {
                If ((FGWM == One))
                {
                    If (((^^^^NPCF.WM2M & One) == Zero))
                    {
                        ^^^^NPCF.WM2M = One
                        Acquire (MUT0, 0x1000)
                        NTWF = One
                        Release (MUT0)
                    }
                }
                ElseIf ((FGWM == Zero))
                {
                    If (((^^^^NPCF.WM2M & One) == One))
                    {
                        ^^^^NPCF.WM2M = Zero
                        Acquire (MUT0, 0x1000)
                        NTWF = One
                        Release (MUT0)
                    }
                }

                If ((NTWF == One))
                {
                    Notify (NPCF, 0xC1) // Hardware-Specific
                    Acquire (MUT0, 0x1000)
                    NTWF = Zero
                    Release (MUT0)
                }
            }
        }

        Method (_QD9, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
        {
            ^^^GPP9.PEGP.NLIM = One
            ^^^GPP9.PEGP.TGPU = GPSV /* \_SB_.PCI0.SBRG.EC0_.GPSV */
            Notify (^^^GPP9.PEGP, 0xC0) // Hardware-Specific
        }

        Method (STPL, 0, NotSerialized)
        {
            If ((FTBL == 0x02))
            {
                If ((RSOC < 0x32))
                {
                    ^^^^NPCF.TPPL = One
                    DBDI ()
                    Sleep (0x64)
                    ^^^^NPCF.TPPL = Zero
                }
                Else
                {
                    ^^^^NPCF.TPPL = 0x00013880
                    Local0 = Zero
                    Local0 = ACIN /* \_SB_.PCI0.SBRG.EC0_.ACIN */
                    If (Local0)
                    {
                        DBDI ()
                    }
                    Else
                    {
                        DBEN ()
                    }
                }
            }
            ElseIf ((FTBL == Zero))
            {
                ^^^^NPCF.TPPL = 0x0001ADB0
                SPDM ()
                ^^^^NPCF.DBDC = One
                Sleep (0x64)
                ^^^^NPCF.TPPL = Zero
            }

            Sleep (0x64)
            Notify (NPCF, 0xC2) // Hardware-Specific
            Sleep (0x64)
            Notify (NPCF, 0xC0) // Hardware-Specific
        }

        Method (WMSH, 0, NotSerialized)
        {
            TGSF = Zero
            FGWM = Zero
            NTWF = Zero
            If ((FMAE == Zero))
            {
                If ((FTBL == 0x02))
                {
                    FGWM = Zero
                    NTWF = One
                }
                ElseIf ((FTBL == Zero))
                {
                    FGWM = One
                    NTWF = One
                }
                ElseIf ((FTBL == One))
                {
                    FGWM = Zero
                    NTWF = One
                }
            }
            Else
            {
                FGWM = Zero
                NTWF = One
            }

            QCHK = 0xD4
        }

        Method (SFTC, 4, NotSerialized)
        {
            CTP0 = (Arg0 >> Zero)
            CTP1 = (Arg0 >> 0x08)
            CTP2 = (Arg0 >> 0x10)
            CTP3 = (Arg0 >> 0x18)
            CTP4 = (Arg1 >> Zero)
            CTP5 = (Arg1 >> 0x08)
            CTP6 = (Arg1 >> 0x10)
            CTP7 = (Arg1 >> 0x18)
            SCT0 = (Arg2 >> Zero)
            SCT1 = (Arg2 >> 0x08)
            SCT2 = (Arg2 >> 0x10)
            SCT3 = (Arg2 >> 0x18)
            SCT4 = (Arg3 >> Zero)
            SCT5 = (Arg3 >> 0x08)
            SCT6 = (Arg3 >> 0x10)
            SCT7 = (Arg3 >> 0x18)
        }

        Method (SFTG, 4, NotSerialized)
        {
            GTP0 = (Arg0 >> Zero)
            GTP1 = (Arg0 >> 0x08)
            GTP2 = (Arg0 >> 0x10)
            GTP3 = (Arg0 >> 0x18)
            GTP4 = (Arg1 >> Zero)
            GTP5 = (Arg1 >> 0x08)
            GTP6 = (Arg1 >> 0x10)
            GTP7 = (Arg1 >> 0x18)
            SGT0 = (Arg2 >> Zero)
            SGT1 = (Arg2 >> 0x08)
            SGT2 = (Arg2 >> 0x10)
            SGT3 = (Arg2 >> 0x18)
            SGT4 = (Arg3 >> Zero)
            SGT5 = (Arg3 >> 0x08)
            SGT6 = (Arg3 >> 0x10)
            SGT7 = (Arg3 >> 0x18)
        }

        Method (SFTS, 4, NotSerialized)
        {
            STP0 = (Arg0 >> Zero)
            STP1 = (Arg0 >> 0x08)
            STP2 = (Arg0 >> 0x10)
            STP3 = (Arg0 >> 0x18)
            STP4 = (Arg1 >> Zero)
            STP5 = (Arg1 >> 0x08)
            STP6 = (Arg1 >> 0x10)
            STP7 = (Arg1 >> 0x18)
            SST0 = (Arg2 >> Zero)
            SST1 = (Arg2 >> 0x08)
            SST2 = (Arg2 >> 0x10)
            SST3 = (Arg2 >> 0x18)
            SST4 = (Arg3 >> Zero)
            SST5 = (Arg3 >> 0x08)
            SST6 = (Arg3 >> 0x10)
            SST7 = (Arg3 >> 0x18)
        }

        Method (CFLB, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x10)
            {
                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = CBD0 /* \_SB_.PCI0.SBRG.EC0_.CBD0 */
            DUBF [One] = CBD1 /* \_SB_.PCI0.SBRG.EC0_.CBD1 */
            DUBF [0x02] = CBD2 /* \_SB_.PCI0.SBRG.EC0_.CBD2 */
            DUBF [0x03] = CBD3 /* \_SB_.PCI0.SBRG.EC0_.CBD3 */
            DUBF [0x04] = CBD4 /* \_SB_.PCI0.SBRG.EC0_.CBD4 */
            DUBF [0x05] = CBD5 /* \_SB_.PCI0.SBRG.EC0_.CBD5 */
            DUBF [0x06] = CBD6 /* \_SB_.PCI0.SBRG.EC0_.CBD6 */
            DUBF [0x07] = CBD7 /* \_SB_.PCI0.SBRG.EC0_.CBD7 */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.CFLB.DUBF */
        }

        Method (GFLB, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x10)
            {
                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = GBD0 /* \_SB_.PCI0.SBRG.EC0_.GBD0 */
            DUBF [One] = GBD1 /* \_SB_.PCI0.SBRG.EC0_.GBD1 */
            DUBF [0x02] = GBD2 /* \_SB_.PCI0.SBRG.EC0_.GBD2 */
            DUBF [0x03] = GBD3 /* \_SB_.PCI0.SBRG.EC0_.GBD3 */
            DUBF [0x04] = GBD4 /* \_SB_.PCI0.SBRG.EC0_.GBD4 */
            DUBF [0x05] = GBD5 /* \_SB_.PCI0.SBRG.EC0_.GBD5 */
            DUBF [0x06] = GBD6 /* \_SB_.PCI0.SBRG.EC0_.GBD6 */
            DUBF [0x07] = GBD7 /* \_SB_.PCI0.SBRG.EC0_.GBD7 */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.GFLB.DUBF */
        }

        Method (SFLB, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x10)
            {
                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = SBD0 /* \_SB_.PCI0.SBRG.EC0_.SBD0 */
            DUBF [One] = SBD1 /* \_SB_.PCI0.SBRG.EC0_.SBD1 */
            DUBF [0x02] = SBD2 /* \_SB_.PCI0.SBRG.EC0_.SBD2 */
            DUBF [0x03] = SBD3 /* \_SB_.PCI0.SBRG.EC0_.SBD3 */
            DUBF [0x04] = SBD4 /* \_SB_.PCI0.SBRG.EC0_.SBD4 */
            DUBF [0x05] = SBD5 /* \_SB_.PCI0.SBRG.EC0_.SBD5 */
            DUBF [0x06] = SBD6 /* \_SB_.PCI0.SBRG.EC0_.SBD6 */
            DUBF [0x07] = SBD7 /* \_SB_.PCI0.SBRG.EC0_.SBD7 */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.SFLB.DUBF */
        }

        Method (CFCV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = CMB0 /* \_SB_.PCI0.SBRG.EC0_.CMB0 */
            DUBF [One] = CMB1 /* \_SB_.PCI0.SBRG.EC0_.CMB1 */
            DUBF [0x02] = CMB2 /* \_SB_.PCI0.SBRG.EC0_.CMB2 */
            DUBF [0x03] = CMB3 /* \_SB_.PCI0.SBRG.EC0_.CMB3 */
            DUBF [0x04] = CMB4 /* \_SB_.PCI0.SBRG.EC0_.CMB4 */
            DUBF [0x05] = CMB5 /* \_SB_.PCI0.SBRG.EC0_.CMB5 */
            DUBF [0x06] = CMB6 /* \_SB_.PCI0.SBRG.EC0_.CMB6 */
            DUBF [0x07] = CMB7 /* \_SB_.PCI0.SBRG.EC0_.CMB7 */
            DUBF [0x08] = CMB8 /* \_SB_.PCI0.SBRG.EC0_.CMB8 */
            DUBF [0x09] = CMB9 /* \_SB_.PCI0.SBRG.EC0_.CMB9 */
            DUBF [0x0A] = CMBA /* \_SB_.PCI0.SBRG.EC0_.CMBA */
            DUBF [0x0B] = CMBB /* \_SB_.PCI0.SBRG.EC0_.CMBB */
            DUBF [0x0C] = CMBC /* \_SB_.PCI0.SBRG.EC0_.CMBC */
            DUBF [0x0D] = CMBD /* \_SB_.PCI0.SBRG.EC0_.CMBD */
            DUBF [0x0E] = CMBE /* \_SB_.PCI0.SBRG.EC0_.CMBE */
            DUBF [0x0F] = CMBF /* \_SB_.PCI0.SBRG.EC0_.CMBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.CFCV.DUBF */
        }

        Method (GFCV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = GMB0 /* \_SB_.PCI0.SBRG.EC0_.GMB0 */
            DUBF [One] = GMB1 /* \_SB_.PCI0.SBRG.EC0_.GMB1 */
            DUBF [0x02] = GMB2 /* \_SB_.PCI0.SBRG.EC0_.GMB2 */
            DUBF [0x03] = GMB3 /* \_SB_.PCI0.SBRG.EC0_.GMB3 */
            DUBF [0x04] = GMB4 /* \_SB_.PCI0.SBRG.EC0_.GMB4 */
            DUBF [0x05] = GMB5 /* \_SB_.PCI0.SBRG.EC0_.GMB5 */
            DUBF [0x06] = GMB6 /* \_SB_.PCI0.SBRG.EC0_.GMB6 */
            DUBF [0x07] = GMB7 /* \_SB_.PCI0.SBRG.EC0_.GMB7 */
            DUBF [0x08] = GMB8 /* \_SB_.PCI0.SBRG.EC0_.GMB8 */
            DUBF [0x09] = GMB9 /* \_SB_.PCI0.SBRG.EC0_.GMB9 */
            DUBF [0x0A] = GMBA /* \_SB_.PCI0.SBRG.EC0_.GMBA */
            DUBF [0x0B] = GMBB /* \_SB_.PCI0.SBRG.EC0_.GMBB */
            DUBF [0x0C] = GMBC /* \_SB_.PCI0.SBRG.EC0_.GMBC */
            DUBF [0x0D] = GMBD /* \_SB_.PCI0.SBRG.EC0_.GMBD */
            DUBF [0x0E] = GMBE /* \_SB_.PCI0.SBRG.EC0_.GMBE */
            DUBF [0x0F] = GMBF /* \_SB_.PCI0.SBRG.EC0_.GMBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.GFCV.DUBF */
        }

        Method (SFCV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = SMB0 /* \_SB_.PCI0.SBRG.EC0_.SMB0 */
            DUBF [One] = SMB1 /* \_SB_.PCI0.SBRG.EC0_.SMB1 */
            DUBF [0x02] = SMB2 /* \_SB_.PCI0.SBRG.EC0_.SMB2 */
            DUBF [0x03] = SMB3 /* \_SB_.PCI0.SBRG.EC0_.SMB3 */
            DUBF [0x04] = SMB4 /* \_SB_.PCI0.SBRG.EC0_.SMB4 */
            DUBF [0x05] = SMB5 /* \_SB_.PCI0.SBRG.EC0_.SMB5 */
            DUBF [0x06] = SMB6 /* \_SB_.PCI0.SBRG.EC0_.SMB6 */
            DUBF [0x07] = SMB7 /* \_SB_.PCI0.SBRG.EC0_.SMB7 */
            DUBF [0x08] = SMB8 /* \_SB_.PCI0.SBRG.EC0_.SMB8 */
            DUBF [0x09] = SMB9 /* \_SB_.PCI0.SBRG.EC0_.SMB9 */
            DUBF [0x0A] = SMBA /* \_SB_.PCI0.SBRG.EC0_.SMBA */
            DUBF [0x0B] = SMBB /* \_SB_.PCI0.SBRG.EC0_.SMBB */
            DUBF [0x0C] = SMBC /* \_SB_.PCI0.SBRG.EC0_.SMBC */
            DUBF [0x0D] = SMBD /* \_SB_.PCI0.SBRG.EC0_.SMBD */
            DUBF [0x0E] = SMBE /* \_SB_.PCI0.SBRG.EC0_.SMBE */
            DUBF [0x0F] = SMBF /* \_SB_.PCI0.SBRG.EC0_.SMBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.SFCV.DUBF */
        }

        Method (CSFV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = CSB0 /* \_SB_.PCI0.SBRG.EC0_.CSB0 */
            DUBF [One] = CSB1 /* \_SB_.PCI0.SBRG.EC0_.CSB1 */
            DUBF [0x02] = CSB2 /* \_SB_.PCI0.SBRG.EC0_.CSB2 */
            DUBF [0x03] = CSB3 /* \_SB_.PCI0.SBRG.EC0_.CSB3 */
            DUBF [0x04] = CSB4 /* \_SB_.PCI0.SBRG.EC0_.CSB4 */
            DUBF [0x05] = CSB5 /* \_SB_.PCI0.SBRG.EC0_.CSB5 */
            DUBF [0x06] = CSB6 /* \_SB_.PCI0.SBRG.EC0_.CSB6 */
            DUBF [0x07] = CSB7 /* \_SB_.PCI0.SBRG.EC0_.CSB7 */
            DUBF [0x08] = CSB8 /* \_SB_.PCI0.SBRG.EC0_.CSB8 */
            DUBF [0x09] = CSB9 /* \_SB_.PCI0.SBRG.EC0_.CSB9 */
            DUBF [0x0A] = CSBA /* \_SB_.PCI0.SBRG.EC0_.CSBA */
            DUBF [0x0B] = CSBB /* \_SB_.PCI0.SBRG.EC0_.CSBB */
            DUBF [0x0C] = CSBC /* \_SB_.PCI0.SBRG.EC0_.CSBC */
            DUBF [0x0D] = CSBD /* \_SB_.PCI0.SBRG.EC0_.CSBD */
            DUBF [0x0E] = CSBE /* \_SB_.PCI0.SBRG.EC0_.CSBE */
            DUBF [0x0F] = CSBF /* \_SB_.PCI0.SBRG.EC0_.CSBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.CSFV.DUBF */
        }

        Method (GSCV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = GSB0 /* \_SB_.PCI0.SBRG.EC0_.GSB0 */
            DUBF [One] = GSB1 /* \_SB_.PCI0.SBRG.EC0_.GSB1 */
            DUBF [0x02] = GSB2 /* \_SB_.PCI0.SBRG.EC0_.GSB2 */
            DUBF [0x03] = GSB3 /* \_SB_.PCI0.SBRG.EC0_.GSB3 */
            DUBF [0x04] = GSB4 /* \_SB_.PCI0.SBRG.EC0_.GSB4 */
            DUBF [0x05] = GSB5 /* \_SB_.PCI0.SBRG.EC0_.GSB5 */
            DUBF [0x06] = GSB6 /* \_SB_.PCI0.SBRG.EC0_.GSB6 */
            DUBF [0x07] = GSB7 /* \_SB_.PCI0.SBRG.EC0_.GSB7 */
            DUBF [0x08] = GSB8 /* \_SB_.PCI0.SBRG.EC0_.GSB8 */
            DUBF [0x09] = GSB9 /* \_SB_.PCI0.SBRG.EC0_.GSB9 */
            DUBF [0x0A] = GSBA /* \_SB_.PCI0.SBRG.EC0_.GSBA */
            DUBF [0x0B] = GSBB /* \_SB_.PCI0.SBRG.EC0_.GSBB */
            DUBF [0x0C] = GSBC /* \_SB_.PCI0.SBRG.EC0_.GSBC */
            DUBF [0x0D] = GSBD /* \_SB_.PCI0.SBRG.EC0_.GSBD */
            DUBF [0x0E] = GSBE /* \_SB_.PCI0.SBRG.EC0_.GSBE */
            DUBF [0x0F] = GSBF /* \_SB_.PCI0.SBRG.EC0_.GSBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.GSCV.DUBF */
        }

        Method (SSFV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = SSB0 /* \_SB_.PCI0.SBRG.EC0_.SSB0 */
            DUBF [One] = SSB1 /* \_SB_.PCI0.SBRG.EC0_.SSB1 */
            DUBF [0x02] = SSB2 /* \_SB_.PCI0.SBRG.EC0_.SSB2 */
            DUBF [0x03] = SSB3 /* \_SB_.PCI0.SBRG.EC0_.SSB3 */
            DUBF [0x04] = SSB4 /* \_SB_.PCI0.SBRG.EC0_.SSB4 */
            DUBF [0x05] = SSB5 /* \_SB_.PCI0.SBRG.EC0_.SSB5 */
            DUBF [0x06] = SSB6 /* \_SB_.PCI0.SBRG.EC0_.SSB6 */
            DUBF [0x07] = SSB7 /* \_SB_.PCI0.SBRG.EC0_.SSB7 */
            DUBF [0x08] = SSB8 /* \_SB_.PCI0.SBRG.EC0_.SSB8 */
            DUBF [0x09] = SSB9 /* \_SB_.PCI0.SBRG.EC0_.SSB9 */
            DUBF [0x0A] = SSBA /* \_SB_.PCI0.SBRG.EC0_.SSBA */
            DUBF [0x0B] = SSBB /* \_SB_.PCI0.SBRG.EC0_.SSBB */
            DUBF [0x0C] = SSBC /* \_SB_.PCI0.SBRG.EC0_.SSBC */
            DUBF [0x0D] = SSBD /* \_SB_.PCI0.SBRG.EC0_.SSBD */
            DUBF [0x0E] = SSBE /* \_SB_.PCI0.SBRG.EC0_.SSBE */
            DUBF [0x0F] = SSBF /* \_SB_.PCI0.SBRG.EC0_.SSBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.SSFV.DUBF */
        }

        Method (CTFV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = CTB0 /* \_SB_.PCI0.SBRG.EC0_.CTB0 */
            DUBF [One] = CTB1 /* \_SB_.PCI0.SBRG.EC0_.CTB1 */
            DUBF [0x02] = CTB2 /* \_SB_.PCI0.SBRG.EC0_.CTB2 */
            DUBF [0x03] = CTB3 /* \_SB_.PCI0.SBRG.EC0_.CTB3 */
            DUBF [0x04] = CTB4 /* \_SB_.PCI0.SBRG.EC0_.CTB4 */
            DUBF [0x05] = CTB5 /* \_SB_.PCI0.SBRG.EC0_.CTB5 */
            DUBF [0x06] = CTB6 /* \_SB_.PCI0.SBRG.EC0_.CTB6 */
            DUBF [0x07] = CTB7 /* \_SB_.PCI0.SBRG.EC0_.CTB7 */
            DUBF [0x08] = CTB8 /* \_SB_.PCI0.SBRG.EC0_.CTB8 */
            DUBF [0x09] = CTB9 /* \_SB_.PCI0.SBRG.EC0_.CTB9 */
            DUBF [0x0A] = CTBA /* \_SB_.PCI0.SBRG.EC0_.CTBA */
            DUBF [0x0B] = CTBB /* \_SB_.PCI0.SBRG.EC0_.CTBB */
            DUBF [0x0C] = CTBC /* \_SB_.PCI0.SBRG.EC0_.CTBC */
            DUBF [0x0D] = CTBD /* \_SB_.PCI0.SBRG.EC0_.CTBD */
            DUBF [0x0E] = CTBE /* \_SB_.PCI0.SBRG.EC0_.CTBE */
            DUBF [0x0F] = CTBF /* \_SB_.PCI0.SBRG.EC0_.CTBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.CTFV.DUBF */
        }

        Method (GTCV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = GTB0 /* \_SB_.PCI0.SBRG.EC0_.GTB0 */
            DUBF [One] = GTB1 /* \_SB_.PCI0.SBRG.EC0_.GTB1 */
            DUBF [0x02] = GTB2 /* \_SB_.PCI0.SBRG.EC0_.GTB2 */
            DUBF [0x03] = GTB3 /* \_SB_.PCI0.SBRG.EC0_.GTB3 */
            DUBF [0x04] = GTB4 /* \_SB_.PCI0.SBRG.EC0_.GTB4 */
            DUBF [0x05] = GTB5 /* \_SB_.PCI0.SBRG.EC0_.GTB5 */
            DUBF [0x06] = GTB6 /* \_SB_.PCI0.SBRG.EC0_.GTB6 */
            DUBF [0x07] = GTB7 /* \_SB_.PCI0.SBRG.EC0_.GTB7 */
            DUBF [0x08] = GTB8 /* \_SB_.PCI0.SBRG.EC0_.GTB8 */
            DUBF [0x09] = GTB9 /* \_SB_.PCI0.SBRG.EC0_.GTB9 */
            DUBF [0x0A] = GTBA /* \_SB_.PCI0.SBRG.EC0_.GTBA */
            DUBF [0x0B] = GTBB /* \_SB_.PCI0.SBRG.EC0_.GTBB */
            DUBF [0x0C] = GTBC /* \_SB_.PCI0.SBRG.EC0_.GTBC */
            DUBF [0x0D] = GTBD /* \_SB_.PCI0.SBRG.EC0_.GTBD */
            DUBF [0x0E] = GTBE /* \_SB_.PCI0.SBRG.EC0_.GTBE */
            DUBF [0x0F] = GTBF /* \_SB_.PCI0.SBRG.EC0_.GTBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.GTCV.DUBF */
        }

        Method (STFV, 0, NotSerialized)
        {
            Name (DUBF, Buffer (0x20)
            {
                /* 0000 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // ........
                /* 0008 */  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00   // ........
            })
            DUBF [Zero] = STB0 /* \_SB_.PCI0.SBRG.EC0_.STB0 */
            DUBF [One] = STB1 /* \_SB_.PCI0.SBRG.EC0_.STB1 */
            DUBF [0x02] = STB2 /* \_SB_.PCI0.SBRG.EC0_.STB2 */
            DUBF [0x03] = STB3 /* \_SB_.PCI0.SBRG.EC0_.STB3 */
            DUBF [0x04] = STB4 /* \_SB_.PCI0.SBRG.EC0_.STB4 */
            DUBF [0x05] = STB5 /* \_SB_.PCI0.SBRG.EC0_.STB5 */
            DUBF [0x06] = STB6 /* \_SB_.PCI0.SBRG.EC0_.STB6 */
            DUBF [0x07] = STB7 /* \_SB_.PCI0.SBRG.EC0_.STB7 */
            DUBF [0x08] = STB8 /* \_SB_.PCI0.SBRG.EC0_.STB8 */
            DUBF [0x09] = STB9 /* \_SB_.PCI0.SBRG.EC0_.STB9 */
            DUBF [0x0A] = STBA /* \_SB_.PCI0.SBRG.EC0_.STBA */
            DUBF [0x0B] = STBB /* \_SB_.PCI0.SBRG.EC0_.STBB */
            DUBF [0x0C] = STBC /* \_SB_.PCI0.SBRG.EC0_.STBC */
            DUBF [0x0D] = STBD /* \_SB_.PCI0.SBRG.EC0_.STBD */
            DUBF [0x0E] = STBE /* \_SB_.PCI0.SBRG.EC0_.STBE */
            DUBF [0x0F] = STBF /* \_SB_.PCI0.SBRG.EC0_.STBF */
            Return (DUBF) /* \_SB_.PCI0.SBRG.EC0_.STFV.DUBF */
        }

        Method (SSDM, 0, NotSerialized)
        {
            ^^^^NPCF.ATPP = 0xC8
            ^^^^NPCF.AMAT = Zero
            ^^^^NPCF.AMIT = Zero
            ^^^^NPCF.ACBT = Zero
            DBDI ()
        }

        Method (STDM, 0, NotSerialized)
        {
            ^^^^NPCF.ATPP = 0x0118
            ^^^^NPCF.AMAT = 0x78
            ^^^^NPCF.AMIT = 0xFFB0
            ^^^^NPCF.ACBT = 0xA0
            DBEN ()
        }

        Method (SPDM, 0, NotSerialized)
        {
            If ((ACIN == One))
            {
                ^^^^NPCF.ATPP = 0xF0
                ^^^^NPCF.AMAT = 0x78
                ^^^^NPCF.AMIT = 0xFFB0
                ^^^^NPCF.ACBT = Zero
                DBEN ()
            }
            Else
            {
                ^^^^NPCF.ATPP = Zero
                ^^^^NPCF.AMAT = Zero
                ^^^^NPCF.AMIT = Zero
                ^^^^NPCF.ACBT = Zero
                DBDI ()
            }
        }

        Method (SMSM, 0, NotSerialized)
        {
            ^^^^NPCF.ATPP = 0x0118
            ^^^^NPCF.AMAT = 0x78
            ^^^^NPCF.AMIT = 0xFFB0
            ^^^^NPCF.ACBT = 0xF0
            DBEN ()
        }

        Method (DBDI, 0, NotSerialized)
        {
            ^^^^NPCF.DBAC = One
            ^^^^NPCF.DBDC = One
        }

        Method (DBEN, 0, NotSerialized)
        {
            ^^^^NPCF.DBAC = Zero
            ^^^^NPCF.DBDC = Zero
        }

        Name (DFLG, 0xD1)
        Method (DNOT, 1, Serialized)
        {
            If (CondRefOf (\_SB.PCI0.GPP9.PEGP))
            {
                If ((SDNT != One))
                {
                    Return (Zero)
                }

                Local0 = Arg0
                If (((Local0 >= 0xD1) && (Local0 <= 0xD5)))
                {
                    If ((DFLG != Local0))
                    {
                        DBG8 = Local0
                        ECMD (0xAE)
                        Notify (^^^GPP9.PEGP, Local0)
                        ECMD (0xAD)
                        DFLG = Local0
                    }
                }
            }
        }

        Method (WAT1, 0, Serialized)
        {
            Local0 = Zero
            While ((WOSR == One))
            {
                Sleep (0x64)
                Local0++
                If ((Local0 == 0x96))
                {
                    WOSR = Zero
                    Return (One)
                }
            }

            Return (Zero)
        }

        Method (WAT2, 0, Serialized)
        {
            Local2 = M428 (Zero, 0x03, One, 0x19, Zero, 0x08)
            Local0 = M019 (Local2, Zero, Zero, Zero)
            Local1 = Zero
            While ((Local0 == 0xFFFFFFFF))
            {
                Sleep (0x64)
                Local0 = M019 (Local2, Zero, Zero, Zero)
                Local1 = (One + Local1)
                If ((Local1 == 0xC8))
                {
                    Return (One)
                }
            }

            Return (Zero)
        }

        Method (CPUP, 1, NotSerialized)
        {
            ^^^^NPCF.ATPP = Arg0
            ^^^^NPCF.DTPP = Arg0
        }
    }

    Method (XPTS, 1, NotSerialized)
    {
    }

    Method (XWAK, 1, NotSerialized)
    {
    }

    Scope (_SB.PCI0)
    {
        Name (NBRI, Zero)
        Name (NBAR, Zero)
        Name (NCMD, Zero)
        Name (PXDC, Zero)
        Name (PXLC, Zero)
        Name (PXD2, Zero)
        Name (BRI2, Zero)
        Name (BAR2, Zero)
        Name (CMD2, Zero)
        Name (XDC2, Zero)
        Name (XLC2, Zero)
        Name (XD22, Zero)
        Method (PXCR, 3, Serialized)
        {
            M460 ("PLA-ASL-_SB.PCI0.GPPX.PXCR\n", Zero, Zero, Zero, Zero, Zero, Zero)
            Local0 = Zero
            Local1 = M017 (Arg0, Arg1, Arg2, 0x34, Zero, 0x08)
            While ((Local1 != Zero))
            {
                Local2 = M017 (Arg0, Arg1, Arg2, Local1, Zero, 0x08)
                If (((Local2 == Zero) || (Local2 == 0xFF)))
                {
                    Break
                }

                If ((Local2 == 0x10))
                {
                    Local0 = Local1
                    Break
                }

                Local1 = M017 (Arg0, Arg1, Arg2, (Local1 + One), Zero, 0x08)
            }

            Return (Local0)
        }

        Method (SPCF, 1, Serialized)
        {
            M460 ("PLA-ASL-_SB.PCI0.GPPX.SPCF\n", Zero, Zero, Zero, Zero, Zero, Zero)
            If ((Arg0 == 0x00020001))
            {
                M460 ("PLA-ASL-_SB.PCI0.GPPX.SPCF NVMe 1\n", Zero, Zero, Zero, Zero, Zero, Zero)
                Local0 = M019 (Zero, (Arg0 >> 0x10), (Arg0 & 0xFF), 
                    0x18)
                NBRI = ((Local0 & 0xFF00) >> 0x08)
                NCMD = M019 (NBRI, Zero, Zero, 0x04)
                NBAR = M019 (NBRI, Zero, Zero, 0x10)
                Local1 = PXCR (NBRI, Zero, Zero)
                PXDC = M019 (NBRI, Zero, Zero, (Local1 + 0x08))
                PXLC = M019 (NBRI, Zero, Zero, (Local1 + 0x10))
                PXD2 = M019 (NBRI, Zero, Zero, (Local1 + 0x28))
            }
            Else
            {
                M460 ("PLA-ASL-_SB.PCI0.GPPX.SPCF NVMe 2\n", Zero, Zero, Zero, Zero, Zero, Zero)
                Local0 = M019 (Zero, (Arg0 >> 0x10), (Arg0 & 0xFF), 
                    0x18)
                BRI2 = ((Local0 & 0xFF00) >> 0x08)
                CMD2 = M019 (BRI2, Zero, Zero, 0x04)
                BAR2 = M019 (BRI2, Zero, Zero, 0x10)
                Local1 = PXCR (BRI2, Zero, Zero)
                XDC2 = M019 (BRI2, Zero, Zero, (Local1 + 0x08))
                XLC2 = M019 (BRI2, Zero, Zero, (Local1 + 0x10))
                XD22 = M019 (BRI2, Zero, Zero, (Local1 + 0x28))
            }
        }

        Method (RPCF, 1, Serialized)
        {
            M460 ("PLA-ASL-_SB.PCI0.GPPX.RPCF\n", Zero, Zero, Zero, Zero, Zero, Zero)
            If ((Arg0 == 0x00020001))
            {
                M460 ("PLA-ASL-_SB.PCI0.GPPX.RPCF NVMe 1\n", Zero, Zero, Zero, Zero, Zero, Zero)
                Local1 = PXCR (NBRI, Zero, Zero)
                M020 (NBRI, Zero, Zero, (Local1 + 0x08), PXDC)
                M020 (NBRI, Zero, Zero, (Local1 + 0x10), (PXLC & 0xFFFFFEFC))
                M020 (NBRI, Zero, Zero, (Local1 + 0x28), PXD2)
                M020 (NBRI, Zero, Zero, 0x10, NBAR)
                M020 (NBRI, Zero, Zero, 0x04, 0x06)
            }
            Else
            {
                M460 ("PLA-ASL-_SB.PCI0.GPPX.RPCF NVMe 2\n", Zero, Zero, Zero, Zero, Zero, Zero)
                Local1 = PXCR (BRI2, Zero, Zero)
                M020 (BRI2, Zero, Zero, (Local1 + 0x08), XDC2)
                M020 (BRI2, Zero, Zero, (Local1 + 0x10), (XLC2 & 0xFFFFFEFC))
                M020 (BRI2, Zero, Zero, (Local1 + 0x28), XD22)
                M020 (BRI2, Zero, Zero, 0x10, BAR2)
                M020 (BRI2, Zero, Zero, 0x04, 0x06)
            }
        }

        Method (UPWD, 0, Serialized)
        {
            M460 ("PLA-ASL-_SB.PCI0.UPWD\n", Zero, Zero, Zero, Zero, Zero, Zero)
            OperationRegion (PSMI, SystemIO, 0xB2, 0x02)
            Field (PSMI, ByteAcc, NoLock, Preserve)
            {
                SMIC,   8, 
                SMID,   8
            }
        }
    }
}

