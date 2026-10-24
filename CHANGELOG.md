# Changelog

## 0.1.0 — 2026-10-24

First release.

- A 🌐 tap switches to the next enabled keyboard layout on the first press, through a listen-only event tap and `TISSelectInputSource`. There is no picker HUD to swallow keystrokes.
- Runs as a `KeepAlive` LaunchAgent (`dev.yemelianov.globe-switch`), so launchd never idle-kills it.
- fn chords (fn+arrows, fn+E, fn+F-keys, media keys) and holds longer than 600 ms do not switch.
- `install.sh` builds, signs, and loads the agent. It sets 🌐 to "Do Nothing" and restarts macOS's text-input agents so they stop switching as well. `install.sh uninstall` reverts all of it.
- The log stays quiet when everything works. It records layout bounces, switch failures, and over-long holds.
- `tools/globe-probe.swift` sends synthetic 🌐 taps to test the agent without pressing the key.
