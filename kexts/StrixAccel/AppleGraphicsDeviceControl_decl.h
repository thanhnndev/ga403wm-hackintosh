// SPDX-License-Identifier: BSD-3-Clause-Clear
// Declaration of com.apple.AppleGraphicsDeviceControl's service base class (AGDC), written from the layout observed in
// the machine's own kext (macOS 24H32, AppleGraphicsDeviceControl 8.1.10): 0x110 bytes, two vendor_doDeviceAttribute
// overloads (the IOExternalMethodArguments one is pure), eight reserved slots.  A vendor subclass is what makes
// IOPresentment (CoreDisplay's display-pipe path) find a GPU: it asks this object for vendor info, GPU capability,
// link configuration and framebuffer capabilities through the AGDC user client.
#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>

struct AGDCClientState_t;

class AppleGraphicsDeviceControl : public IOService {
    OSDeclareDefaultStructors(AppleGraphicsDeviceControl)
    uint8_t _agdcPrivate[0x110 - sizeof(IOService)];
public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual IOReturn message(UInt32 type, IOService *provider, void *argument = nullptr) APPLE_KEXT_OVERRIDE;
    virtual bool terminate(IOOptionBits options = 0) APPLE_KEXT_OVERRIDE;
    virtual IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type, OSDictionary *properties,
                                   IOUserClient **handler) APPLE_KEXT_OVERRIDE;
    virtual IOReturn vendor_doDeviceAttribute(unsigned int cmd, unsigned long *in, unsigned long inSize,
                                              unsigned long *out, unsigned long *outSize,
                                              IOExternalMethodArguments *args) = 0;
    virtual IOReturn vendor_doDeviceAttribute(unsigned int cmd, unsigned long *in, unsigned long inSize,
                                              unsigned long *out, unsigned long *outSize,
                                              AGDCClientState_t *state);
    virtual void _RESERVEDAppleGraphicsDeviceControl0();
    virtual void _RESERVEDAppleGraphicsDeviceControl1();
    virtual void _RESERVEDAppleGraphicsDeviceControl2();
    virtual void _RESERVEDAppleGraphicsDeviceControl3();
    virtual void _RESERVEDAppleGraphicsDeviceControl4();
    virtual void _RESERVEDAppleGraphicsDeviceControl5();
    virtual void _RESERVEDAppleGraphicsDeviceControl6();
    virtual void _RESERVEDAppleGraphicsDeviceControl7();
};
static_assert(sizeof(AppleGraphicsDeviceControl) == 0x110, "AppleGraphicsDeviceControl is 0x110 bytes on 24H32");
