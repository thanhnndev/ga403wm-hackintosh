/*
 * SSDT-ECRAM: read-only windows onto the embedded controller's RAM pages, for AsusWmi (debug.asuswmi.ecram / ecram2 / ecram3,
 * status ec_pdpb / ec_pdsb).
 *
 * This firmware maps the EC RAM as three SystemMemory regions under EC0: ERAM (0xFEDD8300), ERM2 (0xFEDD8B00) and ERM3
 * (0xFEDD8500), 0x100 bytes each. PDPB (ERM2 0x8A) and PDSB (ERM2 0x6F) are declared in the DSDT but its AML never reads them, so
 * the only way to see whether they hold the USB-PD power budget is to read the page. XRAM / XRM2 / XRM3 return the 256 bytes of
 * each region as a buffer; nothing is written.
 *
 * Needs no rename or patch: it only adds methods under the existing EC0 scope.
 */
DefinitionBlock ("", "SSDT", 2, "GA403W", "ECRAM", 0x00001000)
{
    External (\_SB.PCI0.SBRG.EC0, DeviceObj)
    External (\_SB.PCI0.SBRG.EC0.ERAM, OpRegionObj)
    External (\_SB.PCI0.SBRG.EC0.ERM2, OpRegionObj)
    External (\_SB.PCI0.SBRG.EC0.ERM3, OpRegionObj)

    Scope (\_SB.PCI0.SBRG.EC0)
    {
        Field (ERAM, ByteAcc, NoLock, Preserve)
        {
            XB01,   2048
        }

        Field (ERM2, ByteAcc, NoLock, Preserve)
        {
            XB02,   2048
        }

        Field (ERM3, ByteAcc, NoLock, Preserve)
        {
            XB03,   2048
        }

        Method (XRAM, 0, NotSerialized)
        {
            Return (XB01)
        }

        Method (XRM2, 0, NotSerialized)
        {
            Return (XB02)
        }

        Method (XRM3, 0, NotSerialized)
        {
            Return (XB03)
        }
    }
}
