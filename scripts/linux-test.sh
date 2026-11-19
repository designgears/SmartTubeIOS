#!/usr/bin/env bash
# The package's unit tests on Linux: built for the tvOS simulator (scripts/linux-swiftbuild.sh)
# and run in an x86sim Apple TV with the simulator runtime's own xctest, which runs the Swift
# Testing tests too. The device must be running (x86sim start / the launcher).
#
#   X86SIM_ROOT=/path/to/x86sim scripts/linux-test.sh [X86SIM_DEVICE]
#
# Known difference from the Mac: "parsePlaylists emits a log entry…" reads the app's log back
# through OSLogStore, which x86sim doesn't answer the same way.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
x86sim="${X86SIM_ROOT:?set X86SIM_ROOT to the x86sim checkout}"
device="${1:-${X86SIM_DEVICE:-$x86sim/var/device-a64-apple-tv}}"
sdk="${DARWIN_SWIFT_SDK:-$HOME/.config/swiftpm/swift-sdks/darwin.artifactbundle}"
scratch="$root/.build-tvsim"

# CopySwiftLibs fails on the test bundle (no --strip-bitcode-tool); the simulator has the
# Swift runtime, so the linked bundle is all that's needed.
(cd "$root/SmartTubeIOS" && "$root/scripts/linux-swiftbuild.sh" arm64-apple-tvos-simulator --build-tests \
  --scratch-path "$scratch") >"$scratch.log" 2>&1 || grep -q 'CopySwiftLibs' "$scratch.log" \
  || { grep -E 'error:' "$scratch.log" | sort -u >&2; exit 1; }
bundle="$scratch/out/Products/Debug-appletvsimulator/SmartTubeIOSTests.xctest"
[ -f "$bundle/SmartTubeIOSTests" ] || { echo "no test bundle; see $scratch.log" >&2; exit 1; }

xctest=$(ls "$x86sim"/runtimes/tvos-*/RuntimeRoot/Developer/usr/bin/xctest | tail -1)
frameworks="/Volumes/SystemRoot$sdk/Developer/Platforms/AppleTVSimulator.platform/Developer"
X86SIM_DEVICE="$device" "$x86sim/cli/x86sim" spawn --timeout 900 \
  --env DYLD_FRAMEWORK_PATH="$frameworks/Library/Frameworks" --env DYLD_LIBRARY_PATH="$frameworks/usr/lib" \
  "$xctest" "/Volumes/SystemRoot$bundle" | grep -E '^(✘|✔ Test run|✘ Test run)|recorded an issue|^↳ ' || true
