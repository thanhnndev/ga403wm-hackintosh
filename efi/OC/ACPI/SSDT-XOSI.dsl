/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260930 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /Volumes/ESP/EFI/OC/ACPI/SSDT-XOSI.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x000000ED (237)
 *     Revision         0x02
 *     Checksum         0x31
 *     OEM ID           "ZPSS"
 *     OEM Table ID     "XOSI"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20241212 (539234834)
 */
DefinitionBlock ("", "SSDT", 2, "ZPSS", "XOSI", 0x00001000)
{
    Method (XOSI, 1, NotSerialized)
    {
        Local0 = Package (0x0A)
            {
                "Windows 2001", 
                "Windows 2001 SP1", 
                "Windows 2001.1", 
                "Windows 2001 SP2", 
                "Windows 2006", 
                "Windows 2006 SP1", 
                "Windows 2009", 
                "Windows 2012", 
                "Windows 2013", 
                "Windows 2015"
            }
        If (_OSI ("Darwin"))
        {
            Return ((Match (Local0, MEQ, Arg0, MTR, Zero, Zero) != Ones))
        }
        Else
        {
            Return (_OSI (Arg0))
        }
    }
}

