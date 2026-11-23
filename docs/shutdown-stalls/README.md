# NMXGPU process-exit stacks from shutdown stall reports

Extracted (verbatim process blocks) from `/Library/Logs/DiagnosticReports/shutdown_stall_*.shutdownStall`, decoded with
`spindump -i`. Symbol names from the NMXGPU build live at the time (BOOT-TIMELINE section 4).

| File | Lines | What |
|---|---|---|
| `2026-11-19-1442-VTDecoderXPCService-amdgpu_vm_fini.txt` | 1-60 (stack 22-50) | VTDecoderXPCService [19187], zombie, last ran 8062 s before the report: `NMXDrmClient::clientClose`+95 -> `nmx_close` -> `nmx_cdev_close` -> `linux_file_close` -> `drm_release` -> `drm_file_free` -> `amdgpu_driver_postclose_kms` -> `amdgpu_vm_fini` -> `dma_fence_wait` -> `dma_fence_default_wait` -> `linux_schedule_timeout` -> `sleepq_block`. NMXGPU out-37, UUID 5159A44F. Blocked shutdown 2 h 14 min. |
| `2026-11-18-1747-WebKitGPU-VTDecoder-ttm_pool_shrink.txt` | 1-199 (WebKit.GPU [77334], thread at 26), 201-359 (VTDecoderXPCService [78252], thread at 224) | Both zombies on CPU for all 101 samples: `NMXDrmClient::clientClose` -> `nmx_close` -> `drm_release` -> `drm_file_free` -> `drm_gem_release` -> `ttm_bo_put` -> `ttm_tt_unpopulate` -> `ttm_pool_free` -> `ttm_pool_shrink` -> `nmx_mtx_lock`. NMXGPU out-33. Slow teardown with pool-lock contention, not a hang. |

Original reports: `/Library/Logs/DiagnosticReports/shutdown_stall_2026-11-19-144243_*.shutdownStall` (process block at
line 1254 of the decoded text) and `shutdown_stall_2026-11-18-174716_*.shutdownStall` (lines 1540 and 4787).
