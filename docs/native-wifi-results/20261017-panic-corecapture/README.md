# 2026-10-17 10:30 / 10:37 panics — the fault pipe was never started (`corecapture` derefs a NULL notify timer)

The boot after the IE-cap build (installed 10:18) went further than before: Wi-Fi came up, the scan list was clean (the
`scan:trim` line in the log store proves the cap engaged on an AP with 473 bytes of IEs that would have crashed the old
build), the machine joined and got a DHCP lease (`wifi.log`: `192.168.1.14`, gateway `192.168.1.1`). Then, with the
machine idle, it went down twice with a *new* signature:

```
panic(cpu 0): Kernel trap at 0xffffff80180ec678, type = 14=page fault
CR2: 0x0   RDI: 0x0   RSI: 0xffffff99ed4917b0 (a CCDataPipeBlob)
0xffffff80180ec678 com.apple.driver.corecapture : __ZN10CCDataPipe11enqueueBlobEP14CCDataPipeBlob + 0x128
0xffffff80180f16e3 com.apple.driver.corecapture : __ZN12CCDataStream8saveDataEPKcP8OSStringPFvP8OSObjectiPvES5_P13CCDataSession + 0x15f
0xffffff80180f05d0 com.apple.driver.corecapture : __ZNK13CCFaultReport18triggerCoreCaptureEP12CCDataStreamP5OSSetb + 0x1c2
0xffffff80180f27f1 com.apple.driver.corecapture : __ZN15CCFaultReporter14completeReportEP13CCFaultReport + 0x1bd
0xffffff80158d0203 mach_kernel : __ZN18IOTimerEventSource15timeoutSignaledEPvS0_ + 0x83
```

Uptime 229 s (10:30) and 77 s (10:37), both idle — i.e. a deferred fault report is being flushed to disk and the flush
itself panics. Not the scan cache, not fq_codel, not the iGPU.

## What triggers it

`IO80211LinkRecovery::triggerFaultReporter` (0xffffff800235c1f2) — the family's link-recovery path — is called from
`IO80211LinkRecovery::recordBSSBlacklistEvent` (0xffffff800235c77c): a BSS blacklist event makes the family ask for a
core capture. The capture is handed to the `CCFaultReporter` this driver created at start (`getFaultReporterFromDriver`).

## Why the flush panicked

`CCDataPipe::enqueueBlob` (0xffffff80032ec550) stores the blob into the pipe's queue and then, to arm the notify timer:

```
ffffff80032ec66d: mov rax, [rbx + 0x90]     ; pipe ivars
ffffff80032ec674: mov rdi, [rax + 0x38]     ; the notify timer - NULL for us
ffffff80032ec678: mov rax, [rdi]            ; <- fault, CR2 = 0
```

The timer does not exist because **the pipe was never started**. On 25G241 the factories only init:
`CCPipe::withOwnerNameCapacity` → `initWithOwnerNameCapacity` (0xffffff80032e52c8: stores the owner at ivars+0x10,
`IOService::attach(owner)`, allocates the queue state at +0x90) — and **`CCDataPipe::start`** (0xffffff80032ebf7a) is
what creates the timer and publishes the pipe:

```
ffffff80032ebfbe: call IOTimerEventSource::timerEventSource(this, [vptr + 0x980])  ; 0x980 = CCDataPipe::notifyTimeout
ffffff80032ebfca: mov [rcx + 0x38], rax      ; ivars->notifyTimer
ffffff80032ebffc: call [rcx + 0x140]         ; provider->getWorkLoop()->addEventSource(timer)
ffffff80032ec014: call [rax + 0x3b0]         ; set IOClass/name
ffffff80032ec01f: call IOService::publishResource("CCPipe", 0)
ffffff80032ec02f: call [rax + 0x5b0]         ; registerService (joins the CoreCapture plane)
```

Apple's own sequence ends with one more call that the factories do not make —
**`CCPipe::startPipe`** (0xffffff80032e4dfc, virtual at slot +0x868 of the pipe vtable), which re-enters the pipe's
`start(provider)` (slot +0x5c0 = `CCDataPipe::start`, or `CCLogPipe::start` for log pipes):

```
AppleBCMWLANBusInterfacePCIe::createCrashTracerLogger (0xffffff8001563cfe), at +0x1dc:
ffffff8001563ed0: mov rdi, [rax + 0xf20]     ; the data pipe it just created
ffffff8001563ed7: mov rax, [rdi]
ffffff8001563eda: call [rax + 0x868]         ; CCPipe::startPipe
```

and its `deferredStart` (0xffffff800155e7cc..0x155e88b1) only wraps the reporter around the started stream
(`CCFaultReporter::withStreamWorkloop` → `setFaultReporter` → `IO80211FaultReporter::allocWithParams` →
`registerCallbacks(9, ...)` → `addOwner(...)` ×4). So a driver that creates the pipe with the factory alone gets an
object that looks alive (mutex, queue, stream all fine — the blob even enqueues) until the first flush dereferences the
timer. `RCX = 0`-style evidence from the two panics: `RDI = 0` at `+0x128`; everything before that ran.

## Fix (driver side, `kexts/itlmt7925Native`)

`corecapture_min.h` now documents and provides the raw virtual call (the CCPipe hierarchy is far too wide to declare):

```cpp
inline bool ccPipeStartPipe(void *pipe)
{
    if (!pipe) return false;
    void **vptr = *(void ***)pipe;            // object vptr = vtable symbol + 0x10 on 25G241
    return ((bool (*)(void *))vptr[0x868 / 8])(pipe);
}
```

`itlmt7925_wifi.cpp` calls it on both pipes right after the factory creates them, exactly where Apple calls it:

- `makeLogger`: `logPipe` started after the `CCLogStream` exists;
- `makeFaultReporter`: `dataPipe` started before the `CCFaultReporter` is built around the stream;
- new trace line `ctl:faultPipe=<0|1>` at start; if a start ever fails, the boot trace says so (a null fault reporter
  would panic the family at `findAndAttachToFaultReporter`, so the reporter is still built, and the failure is loud).

## Verify after the fix

1. Boot macOS, use Wi-Fi ≥5 minutes (the panics came 77 s / 229 s in, idle); repeated `sudo wdutil scan` is welcome.
2. `ioreg -l | grep itlmt_native_trace` must show `ctl:faultPipe=1`.
3. No `corecapture` panic. A fault report may still be produced when link recovery records a BSS blacklist event — that
   is the design; with the pipe started the capture is written/published instead of crashing the kernel.
4. If a panic were to recur, keep the `.panic` file and the trace.
