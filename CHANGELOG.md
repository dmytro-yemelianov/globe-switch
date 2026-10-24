# Changelog

## 0.5.0 — 2026-10-24

- Changed: the indicator draws flags as pixel art, sharp rectangles of 22 × 14 pixels that are scaled without smoothing. Ukraine and the United Kingdom are drawn so far; other countries keep their emoji flag until theirs is drawn.

## 0.4.0 — 2026-10-24

- New: the indicator lines up every layout's flag with no background. The active one is in the middle, larger and glowing in the accent colour, and on a switch the row slides with a spring so the new layout moves to the middle; quick taps carry on from wherever the row is. Flags come from the country a layout is named after (British → 🇬🇧), otherwise from its language (Ukrainian → 🇺🇦, ABC → 🇺🇸); a layout without one shows its name.
- New: `LayoutFlags` picks your own flag per layout, as a region code (`GB`) or any text.
- New: a soft 40 ms click after each switch, synthesized by the agent and pitched for each layout: the first layout in system order at 1.6 kHz, the next ones a major third, a fifth and an octave higher. `PlaySound`, `Sound` (the click, or any system sound such as `Tink`, the same for every layout) and `SoundVolume` (default 0.35) control it.
- Changed: `ShowIndicator` is on by default. Turn it off with `defaults write dev.yemelianov.globe-switch ShowIndicator -bool false`.
- Changed: the doctor lists each layout with its flag.
- Development: `globe-probe type` refuses to type when another app is in front, so its test letters can't land in your window.

## 0.3.0 — 2026-10-24

- New: GlobeSwitch.app. `globe-switch install` copies it to `~/Applications` and points the LaunchAgent at its executable, with `AssociatedBundleIdentifiers` so that Login Items & Extensions lists it as GlobeSwitch. Input Monitoring is granted to GlobeSwitch, with its own icon, instead of a bare binary path. Opening the app from Finder installs it too and shows the doctor's report. Requires macOS 13.
- Not used: `SMAppService`. launchd found the program of an SMAppService agent through LaunchServices by bundle ID, picked another copy of GlobeSwitch.app (a removed Homebrew build) and could not restart the agent, so the LaunchAgent keeps an absolute path.
- New: Homebrew. `brew install dmytro-yemelianov/tap/globe-switch` builds the app from source; then run `globe-switch install`.
- New: settings in the `dev.yemelianov.globe-switch` domain, reread on every 🌐 press: `TapWindowMilliseconds`, `SkippedLayouts`, `CycleOrder` (`list`, or `recent` to go back to the previous layout like a quick Ctrl+Space) and `ShowIndicator`.
- New: an optional indicator with the new layout's name. It is a panel that never becomes the key window and never activates the app, so it cannot swallow keystrokes.
- New: the doctor reports the LaunchAgent (including when it is turned off in Login Items), the code signature (ad-hoc means Input Monitoring has to be granted again after each update), the settings and SkippedLayouts entries that aren't enabled.
- Changed: `install` and `uninstall` are commands of the binary, shared by `install.sh` and Homebrew. Upgrading from 0.1 or 0.2 points the LaunchAgent at the app and removes the old binary; Input Monitoring then needs a new grant for GlobeSwitch.
- Changed: the app is signed with the hardened runtime, and the binary finds its app bundle when run through a symlink.
- Development: CI also builds for Intel, builds and verifies the app bundle, and shellchecks `scripts/build-app.sh`. The probe gained a `type` check: tap 🌐, then type into its own text field 40 ms later, and every letter must arrive.

## 0.2.0 — 2026-10-24

- New: `globe-switch doctor` asks the running agent for its state and checks Input Monitoring, the 🌐 setting and the enabled layouts. It prints a fix for each problem and exits with status 1 when something is broken. `install.sh` runs it at the end.
- New: the agent checks its Input Monitoring access every 30 seconds. Revoking the access used to leave the agent running but deaf; now it restarts and waits for the grant.
- New: the agent logs when 🌐 is no longer set to **Do Nothing**, because macOS then reacts to taps as well.
- Changed: logs go to the unified log (`/usr/bin/log show --predicate 'subsystem == "dev.yemelianov.globe-switch"'`), which macOS rotates. `~/Library/Logs/globe-switch.log` is no longer written; uninstall removes it.
- Changed: `install.sh` records the 🌐 setting before the first install, and uninstall restores it instead of always choosing **Change Input Source**.
- Fixed: fn held while scrolling counted as a tap and switched the layout.
- Development: the project is a Swift package. Tap detection and layout cycling live in `GlobeSwitchCore` with unit tests, and CI builds with warnings as errors, runs the tests and runs shellcheck. The probe gained a `scroll` check.

## 0.1.1 — 2026-10-24

- Fixed: after Input Monitoring was granted, a waiting agent never noticed and stayed deaf until the next login, because macOS caches the permission answer for the life of a process. The agent now checks with a fresh copy of itself (`--check-access`) every two seconds and, once access is granted, exits so launchd restarts it with the permission in effect.
- Docs: troubleshooting for an Input Monitoring entry recorded for an earlier signature. Re-enabling such an entry does nothing; it has to be removed and added again.

## 0.1.0 — 2026-10-24

First release.

- A 🌐 tap switches to the next enabled keyboard layout on the first press, through a listen-only event tap and `TISSelectInputSource`. There is no picker HUD to swallow keystrokes.
- Runs as a `KeepAlive` LaunchAgent (`dev.yemelianov.globe-switch`), so launchd never idle-kills it.
- fn chords (fn+arrows, fn+E, fn+F-keys, media keys) and holds longer than 600 ms do not switch.
- `install.sh` builds, signs, and loads the agent. It sets 🌐 to "Do Nothing" and restarts macOS's text-input agents so they stop switching as well. `install.sh uninstall` reverts all of it.
- The log stays quiet when everything works. It records layout bounces, switch failures, and over-long holds.
- `tools/globe-probe.swift` sends synthetic 🌐 taps to test the agent without pressing the key.
