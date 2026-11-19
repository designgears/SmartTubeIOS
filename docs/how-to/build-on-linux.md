> status: current (2026-11-19)

# How to build, test and run on Linux

The tvOS app builds, signs, tests and runs on Linux with
[omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev) (Swift, xtool and a Swift
SDK built from Xcode 27.2) and [x86Sim](https://github.com/x86sim/x86sim) (Apple's simulator
runtimes on x86-64 Linux). No Mac is involved.

| Task | Command |
|---|---|
| Format, format check | `just format`, `just format-check` (the toolchain's `swift format`) |
| Lint | `just lint` (SwiftLint's Linux release, same version as the baseline) |
| Unit tests | `X86SIM_ROOT=… just linux-test` (needs a running x86sim Apple TV) |
| App for the simulator | `just linux-build-tvos`, then install `SmartTubeApp/omarchy-xtool/xtool/Smart Tube.app` with x86sim |
| App for the Apple TV | `just linux-build-tvos-device`, then `pymobiledevice3 apps install "…/Smart Tube.app" --developer --tunnel <TV UDID>` |

## How it fits together

- `SmartTubeApp/omarchy-xtool` is an xtool adapter for the "Smart Tube" tvOS target: a SwiftPM
  package around `SmartTubeApp/Smart Tube` (symlinked) and the `SmartTubeIOS` package, with the
  target's Info.plist keys; `xtool.env` names the icon set. Change it when the Xcode target's
  settings change.
- The app recipes run omarchy-apple-dev's `ship.sh --device` (build, then the app icon and Top
  Shelf from the `.brandassets` with the Linux `actool`, then resources at the bundle root);
  the device one ends with `xtool sign`, which signs with the exact bundle ID, so the build
  replaces an Xcode-built Smart Tube and keeps its data. Set `OMARCHY_APPLE_DEV` if the toolkit
  isn't in `~/omarchy-apple-dev`.
- `scripts/linux-swiftbuild.sh` runs `swift build` with the settings xtool uses (SwiftBuild, the
  SDK's toolset, `XCODE_EXTRA_PLATFORM_FOLDERS`). `scripts/linux-test.sh` uses it to build the test
  bundle for the tvOS simulator, then runs it with the simulator runtime's `xctest` through
  `x86sim spawn`, pointing `DYLD_FRAMEWORK_PATH` at the SDK's simulator XCTest and Testing
  frameworks (host paths appear in the device under `/Volumes/SystemRoot`).

## Limits

- x86Sim can't decode video yet (YouTube's and Twitch's HLS both fail with "Cannot Decode"):
  check playback on the Apple TV.
- One unit test reads the app's log back through `OSLogStore` and fails in x86Sim only.
- Installing on an Apple TV goes through pymobiledevice3's `tunneld`, run once as a root
  service (omarchy-apple-dev's `tools/systemd/pymobiledevice3-tunneld.service.in`); after that,
  installs and `developer dvt launch` run as your user with `--tunnel` and the TV's hardware
  UDID. Without the service, `sudo pymobiledevice3 remote start-tunnel -t wifi` gives an
  `--rsd HOST PORT` to use instead.
