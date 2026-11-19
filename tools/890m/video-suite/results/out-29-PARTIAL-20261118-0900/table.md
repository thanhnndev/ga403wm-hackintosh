> **PARTIAL: round 1 of 3 only, aborted 2026-11-18 on main's instruction. h264-1080p30-win is DISTURBED (page hidden 49 s, owner input 51 s); av1-1080p60-max ran while a clang compile of mine was going (CPU 1677 %), its 10 drops are not the driver's. Not a baseline.**

# video-suite results: out-29-PARTIAL-20261118-0900

```
label: out-29   cases: idle vp9-1080p60-win vp9-1080p60-max vp9-1080p60-fs av1-1080p60-max h264-1080p30-win vp9-seekpause vp9-2160p60-max   rounds: 3
date: 2026-11-18 09:00:05   uptime: 6 mins   boot: Wed Nov 18 08:54:28 2026
macOS 26.7.2 (25G332); Google Chrome 157.0.8103.78 
NMXGPU: (1.0.0) 3DF88CD9-ECB7-30AB-A93E-FAE454810F27   NMXAccel: (0.1) C18FD8B4-0354-3D4C-9A4E-EDA2AB2463F6   StrixAccel: (0.1.21) AF1F2E29-231C-3964-A2D4-573CE0524E10
park_ms: 60000   plugin sha1: 3a64990eec9a NVMTLDriver 03a03cef7f55 libvulkan_radeon.dylib 
power: AC Power   64%; 
asus:  set_profile=0 profile=3 cpu_fan=23 gpu_fan=24 gpu_mux=1 dgpu_disable=0 panel_overdrive=1
dGPU gate: eco: dsm0 0 dsm1A 0 ps3 0 gsta 1->0 psc 3 vid 0xffff
EPP: 191 x10 
iOS Simulator running: yes   diagnosticd CPU: 7.8%   RTX (asus dgpu_disable): 0
Docker running: no   owner Chrome running: no
memory: wired 7.4 GB, compressor 0.0 GB, swap 0.00M
display: 1440 x 900 @ 120.00Hz   Tctl now: 62 C
top by CPU (1 s):

```

## Cases

| case | decoder | decoded | dropped | skipped | late | iv p95 ms | iv p99 | iv max | pkg W | pre-idle W | W over pre-idle | Tctl | GPU-proc % | renderer % | WS % | kernel_task % | VTDec % | Docker % | all CPU % | NMX frames/s | chunks fill/inl/free | parks/unparks | fails | hidden s | unfocused s | input s | swapins | wired GB | note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| av1-1080p60-max | VideoToolbox | 3600 | 10 | 10 | 5 | 17.5 | 17.7 | 108.4 | 23.08 | 15.01 | 8.07 | 61.2 | 15.2 | 7.7 | 21.5 | 22 | 5.7 | 0 | 453.3 | 59.7 | 217/0/0 | 127/31 | 0 | 0 | 0 | 0 | 0 | 8.5 |  |
| h264-1080p30-win | FFmpeg (SW) | 266 | 0 | 0 | 0 | 34.1 | 34.3 | 45.2 | 34.52 | 53.2 | -18.68 | 80.5 | 1.2 | 5.4 | 20.3 | 26.1 | 0 | 0 | 554.3 | 27.4 | 0/0/0 | 183/37 | 0 | 49 | 60 | 51 | 0 | 9.5 | DISTURBED |
| idle | - | - | - | - | - | - | - | - | 7.63 | - | 0 | 51.2 | - | - | 0.8 | 14.9 | - | 0 | 169.6 | 1.6 | - | - | - | - | - | - | - | - | - |
| vp9-1080p60-fs | VideoToolbox | 3600 | 4 | 4 | 2 | 17.5 | 17.7 | 50.8 | 11.95 | 13.94 | -1.99 | 52 | 12.8 | 7.7 | 17.6 | 18.1 | 5.7 | 0 | 173.1 | 59.6 | 0/0/0 | 200/0 | 0 | 0 | 0 | 0 | 0 | 9.1 |  |
| vp9-1080p60-max | VideoToolbox | 3600 | 0 | 0 | 0 | 17.4 | 17.7 | 17.9 | 10.45 | 6.92 | 3.53 | 51.3 | 13.4 | 8 | 23.5 | 16.7 | 5.7 | 0 | 171.7 | 56.1 | 56/0/0 | 50/57 | 0 | 0 | 14 | 15 | 0 | 8.3 |  |
| vp9-1080p60-win | VideoToolbox | 3598 | 4 | 3 | 5 | 17.5 | 17.7 | 59.3 | 19.98 | 19.46 | 0.52 | 62.7 | 12.8 | 7.8 | 19.2 | 21 | 5.5 | 0 | 324.4 | 59.6 | 0/0/0 | 90/22 | 0 | 0 | 0 | 0 | 0 | 8.3 |  |

