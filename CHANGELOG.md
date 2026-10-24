# Changelog

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
