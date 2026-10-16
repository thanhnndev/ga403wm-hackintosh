# Screenshots

The only remaining `.svg` here (`itlwifi`) is a **placeholder**; the other shots are real PNGs from the reference machine (2026-10-13). Replace each with a real screenshot using the same base name
(`hero.png` and so on) and update the `<img>`/`![]()` links in [README.md](../../README.md) and
[README.vi.md](../../README.vi.md) from `.svg` to `.png`.

| File | What to capture | Notes |
|---|---|---|
| `hero` | **Done** (`hero.jpg`, 1600x900): composite of the RogControl window, popover and About This Mac shots, made with [scripts/make-hero.swift](../../scripts/make-hero.swift). JPEG because the PNG was 1.1 MB. Redo it with the ItlWiFi shot once that exists | |
| `rogcontrol-popover` | The menu bar popover (modes, Tctl, power, fans, charge limit) | light or dark, be consistent |
| `rogcontrol-window` | Window, Performance tab, Manual selected | |
| `fan-curves` | CPU and GPU firmware fan-curve chart | |
| `itlwifi` | ItlWiFi popover with the scan list; a second shot with the speed test is welcome. **Skipped for now:** the native Wi-Fi port is in progress, shoot it after it lands | **blur SSIDs, BSSIDs, IPs, MAC** |
| `about-this-mac` | About This Mac / System Information | **blur serial number and UUID** |

Rules: no serial numbers, MACs, SSIDs of other people's networks, IP addresses or account names in any image. Prefer PNG,
under 500 KB each (the repository is cloned by everyone).
