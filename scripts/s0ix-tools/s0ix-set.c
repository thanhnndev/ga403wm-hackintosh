// SPDX-License-Identifier: BSD-3-Clause-Clear
// StrixS0ix runtime switches, no reboot needed (run as root):
//   s0ix-set bootcc6 on|off     boot CPU in CC6 between wake checks while asleep (0.1.3+)
//   s0ix-set d3 0..5            PCI D3hot during sleep (0 record only, 1 890M buses, 2 + other endpoints,
//                               3 + no-No_Soft_Reset functions with config save/restore (0.1.5), 4 + the 890M itself, 5 + the RTX)
//   s0ix-set ecwake 0|1|2       0.1.7: EC GPE off / wake source (default) / observe only (logs status bits, RTC wake)
//   s0ix-set gpiowake 0|1|2     0.1.8: GPIO pin 0 (lid + power button) off / wake (default) / observe
//   s0ix-set gpiocc6 on|off     0.1.8: boot CPU in CC6 (not MWAITX) while GPIO wake is armed
//   s0ix-set cst 1|2            0.1.5: CC6 entry port, _CST C2 (base+1) or C3 (base+2, default)
//   s0ix-set dsmskip MASK       0.1.9: PEP _DSM fns to leave out, bit per fn (0x18 = fn 3/4, 0x180 = fn 7/8)
//   s0ix-set halthint on|off    0.1.4: OS_HINT from the halt path (on) or from the power state change (off)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: s0ix-set bootcc6|halthint|gpiocc6 on|off, s0ix-set d3 0..5, s0ix-set ecwake|gpiowake 0..2, s0ix-set cst 1|2\n"); return 2; }
    CFStringRef key; CFTypeRef val;
    int on = !strcmp(argv[2], "on");
    if (!strcmp(argv[1], "bootcc6")) { key = CFSTR("S0ix,BootCC6"); val = on ? kCFBooleanTrue : kCFBooleanFalse; }
    else if (!strcmp(argv[1], "halthint")) { key = CFSTR("S0ix,HaltHint"); val = on ? kCFBooleanTrue : kCFBooleanFalse; }
    else if (!strcmp(argv[1], "cst")) { int n = atoi(argv[2]); key = CFSTR("S0ix,CstDepth"); val = CFNumberCreate(NULL, kCFNumberIntType, &n); }
    else if (!strcmp(argv[1], "gpiocc6")) { key = CFSTR("S0ix,GpioCc6"); val = on ? kCFBooleanTrue : kCFBooleanFalse; }
    else if (!strcmp(argv[1], "gpiowake")) { int n = atoi(argv[2]); key = CFSTR("S0ix,GpioWake"); val = CFNumberCreate(NULL, kCFNumberIntType, &n); }
    else if (!strcmp(argv[1], "ecwake")) { int n = atoi(argv[2]); key = CFSTR("S0ix,EcWake"); val = CFNumberCreate(NULL, kCFNumberIntType, &n); }
    else if (!strcmp(argv[1], "dsmskip")) { int n = (int)strtol(argv[2], NULL, 0); key = CFSTR("S0ix,DsmSkip"); val = CFNumberCreate(NULL, kCFNumberIntType, &n); }
    else if (!strcmp(argv[1], "d3")) { int n = atoi(argv[2]); key = CFSTR("S0ix,D3Mode"); val = CFNumberCreate(NULL, kCFNumberIntType, &n); }
    else { fprintf(stderr, "unknown switch %s\n", argv[1]); return 2; }
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("StrixS0ix"));
    if (!s) { fprintf(stderr, "StrixS0ix not found\n"); return 1; }
    kern_return_t r = IORegistryEntrySetCFProperty(s, key, val);
    IOObjectRelease(s);
    printf("%s %s: %#x\n", argv[1], argv[2], r);
    return r != KERN_SUCCESS;
}
