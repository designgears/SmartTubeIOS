#!/usr/bin/env bash
# `swift build` for an Apple simulator or device triple on Linux, with the darwin Swift SDK that
# omarchy-apple-dev installs — the same settings xtool uses (SwiftBuild, its toolset, the Darwin
# Swift resource directory for every platform, a linker version ld64.lld accepts).
#
#   scripts/linux-swiftbuild.sh TRIPLE [swift build options...]
#   scripts/linux-swiftbuild.sh arm64-apple-tvos-simulator --build-tests --scratch-path .build-tvsim
set -euo pipefail
sdk="${DARWIN_SWIFT_SDK:-$HOME/.config/swiftpm/swift-sdks/darwin.artifactbundle}"
[ -d "$sdk" ] || { echo "no darwin Swift SDK at $sdk (run omarchy-apple-dev's install-toolchain.sh)" >&2; exit 1; }
resources="$sdk/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift"
triple="$1"; shift
unset SDKROOT
export XCODE_EXTRA_PLATFORM_FOLDERS="$sdk/Developer/Platforms"
export PATH="$sdk/toolset/bin:$PATH"
exec swift build --build-system swiftbuild --triple "$triple" --toolset "$sdk/toolset-swb.json" \
  -Xswiftc -resource-dir -Xswiftc "$resources" -Xcc -resource-dir -Xcc "$resources/clang" \
  -Xswiftc -Xclang-linker -Xswiftc -mlinker-version=705 "$@"
