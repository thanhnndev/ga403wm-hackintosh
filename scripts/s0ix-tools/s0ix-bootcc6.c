// SPDX-License-Identifier: BSD-3-Clause-Clear
// Step112: turn StrixS0ix's boot-CPU CC6 (between wake checks while asleep) on or off without a reboot.
//   s0ix-bootcc6 on|off      (run as root)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    if (argc != 2 || (strcmp(argv[1], "on") && strcmp(argv[1], "off"))) { fprintf(stderr, "usage: s0ix-bootcc6 on|off\n"); return 2; }
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("StrixS0ix"));
    if (!s) { fprintf(stderr, "StrixS0ix not found\n"); return 1; }
    kern_return_t r = IORegistryEntrySetCFProperty(s, CFSTR("S0ix,BootCC6"), strcmp(argv[1], "on") ? kCFBooleanFalse : kCFBooleanTrue);
    IOObjectRelease(s);
    printf("S0ix,BootCC6 %s: %#x\n", argv[1], r);
    return r != KERN_SUCCESS;
}
