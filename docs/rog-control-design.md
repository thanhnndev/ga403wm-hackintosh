# ROG Control interaction design

ROG Control is primarily a menu bar hardware utility. Daily adjustments should be completed in its panel; the standalone window supports longer inspection and adjustment.

## Research and decisions

- [Apple Control Center](https://support.apple.com/en-ca/guide/mac-pro/apdc362a41b2/mac): immediate access to frequently used controls.
- [Apple popovers](https://developer.apple.com/design/human-interface-guidelines/popovers): limit related tasks, avoid oversized panels, and keep multiple selections possible until dismissal.
- [NN/G progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/): keep frequent actions visible, reveal secondary information on demand.
- [NN/G system status](https://www.nngroup.com/articles/visibility-system-status/): communicate actual state and action failures.
- [G-Helper](https://github.com/seerge/g-helper) and [asusctltray](https://github.com/Baldomo/asusctltray): direct profile selection and hardware controls from a resident utility.

Taste v2 targets web landing pages and redesigns. It is not the foundation for this native utility. The confirmed user requirement is frequent interaction through the menu bar. Per-feature usage frequency has not been measured.

## Primary panel

The panel retains direct performance mode selection, CPU temperature/package power, CPU/GPU RPM, charge presets, keyboard brightness, Slash settings, and software OLED dimming. These use compact rows without section cards or a page-sized scroll area. Manual exposes power sliders, fan base, and Apply directly under the modes. Slider changes remain rounded to integer watts without drawing a tick for every watt.

Hardware-confirmed mode, charge limit, keyboard brightness, and Slash controls are distinguished from saved preferences. Profile, charging, and lighting failures appear beside the relevant controls. Manual changes are marked as not applied until saved. Changing fan base updates the reference curve without claiming that the preview has been applied.

Fan curves are available in an optional disclosure. Only that detail region scrolls; its height is bounded for the screen. Open at Login, health/graphics details, and Quit live in Settings. Open app has a visible text label.

## Fan curves

The AsusWmi ABI returns 16 bytes: eight temperatures followed by eight fan duties. Read-only inspection of this GA403WM returned a 255°C endpoint in both Turbo curves and repeated 70°C points in the Turbo GPU curve. The former drawing code projected 255 outside its 20–105°C chart with no clipping or axes.

Swift Charts now uses explicit 20–105°C and 0–100% axes, linear segments, visible points, and CPU/GPU selection. A hover shows a point's temperature/duty. A firmware profile label identifies the source; this is a firmware reference curve, not live RPM or a time series.

Invalid endpoints are omitted with a visible notice, not clamped or assigned a made-up temperature. Interior invalid samples break the line. Repeated valid temperatures are preserved. Malformed or unavailable data produces an explicit empty state. The selected manual fan base can be previewed independently of Apply. Driver curve validation and hardware behavior remain unchanged.

## App behavior

Build with `bash scripts/build-rogcontrol.sh`; install and relaunch with `bash scripts/build-rogcontrol.sh --install`. A regular launch opens the app window; `--background` runs in the menu bar. Closing the window keeps the utility running. AC/battery preferences remain independent.

The window retains Overview, Performance, Lighting, Battery & Display, and Settings, with shared bindings. Command-0 opens it; Command-R refreshes; Command-W closes; Command-M minimizes; Command-Q quits. Geometry is saved.

## Verification

`bash scripts/test-rogcontrol.sh` tests decoding using real firmware samples: Turbo 255 endpoints, duplicate temperatures, gaps, invalid duty, descending points, short buffers, and empty data. It never writes hardware.

Offscreen native AppKit/SwiftUI renders were inspected for the light/dark primary panel, Manual sliders, the Performance chart, and the Turbo omission notice. Default controls fit without scrolling; selected keyboard and charge levels remain visible. Build target remains macOS 13, x86_64.

These checks validate layout and decoding. They do not replace observed user-task testing, and hardware-setting actions were not exercised as part of the chart tests.
