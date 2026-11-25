# RyzenHV 0.7.22 post-boot test (repo ryzen-hypervisor.framework)
1. kextstat 0.7.22 / UUID 56360452; build/rhv-info log | grep -i "tsc check" pass; no new panic
2. build/hvf-exit-bench 2: cpuid/hlt/npt print exits/s, no "failed" (PASS 2026-11-11: 3.17/3.43/3.18 us, TLB flush 0.4 %)
3. Docker compose stack up; alpine curl example.com prints an HTTP line; dmesg has no oops/segfault/bug; 5 min light load
4. build/rhv-info stats: guest TLB flushed X % well below 100, new ASID Y <= X; vmFpuMismatches 0; vmInvalidExits flat; guest+switch <= 10.67 us with postgres busy
5. Fail (panic, VM hang, vmentry error, oops, X = 100 %): restore Kexts-backup/RyzenHV.kext.0.7.21-B37AAE98
