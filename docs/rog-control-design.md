# ROG Control redesign

Design read: a native macOS hardware utility for Zephyrus G14 owners, using a clean, modern interface and macOS controls. Restrained layout variance, minimal motion, comfortable information density.

## Research

[Taste Skill v2](https://github.com/Leonxlnx/taste-skill/blob/main/skills/taste-skill/SKILL.md) is experimental and primarily targets web landing pages and redesigns. Its relevant principles here are auditing the existing UI, choosing the platform's design foundation, consistent typography and spacing, a single accent, and clear unavailable states. Web marketing patterns and dependencies do not fit this native utility.

The implementation uses system typography, SF Symbols, semantic macOS colors that follow light/dark appearance, 12-point section corners and 8-point interactive corners. It retains the existing AsusWmi/AmdCppc backend and shared ObservableObject, hosted through NSHostingController.

## Usage

Build with `bash scripts/build-rogcontrol.sh`, then open `build/RogControl.app` in Finder. A normal launch opens the main window. The menu bar provides quick mode selection and an **Open ROG Control** button.

The window includes Overview, Performance, Lighting, Battery & Display, and Settings. Existing manual limits, firmware fan curves, charge presets, keyboard and Slash controls, software dimming, login settings, and graphics status remain available.

Close the window to continue in the menu bar. Reopen from Finder, Dock, or the popover. Use Command-0 to show the window, Command-R to refresh, Command-W to close, Command-M to minimize, and Command-Q to quit. Window geometry is saved.

Login launches pass `--background` to avoid opening a window. Existing login items can be updated by switching Open at Login off and on. Settings remain separate for AC and battery. Telemetry refreshes every two seconds while either interface is visible, and every thirty seconds in the background.

## Validation

Build target: macOS 13 or later, x86_64. The build script compiles and ad-hoc signs the app. Hardware interaction and visual checks on the target G14 require a running macOS session with the relevant kexts.
