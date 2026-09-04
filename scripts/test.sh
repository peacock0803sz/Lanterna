#!/usr/bin/env bash
# Runs the test suite with the host Apple toolchain.
#
# Two workarounds are applied when only Command Line Tools are installed:
#   - Nix's devshell exports SDKROOT/DEVELOPER_DIR pointing at an old Apple SDK
#     that has no SwiftPM, so both are cleared.
#   - CLT ships Swift Testing outside the toolchain's default search paths, and
#     DYLD_* variables are stripped from the SIP-protected test helper, so the
#     framework and its interop dylib must be baked in as rpaths at link time.
# With a full Xcode installation neither is needed and the flags stay empty.
set -euo pipefail

cd "$(dirname "$0")/.."

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

flags=()
if [ -d "$CLT_FRAMEWORKS/Testing.framework" ]; then
    flags=(
        -Xswiftc -F"$CLT_FRAMEWORKS"
        -Xlinker -F"$CLT_FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$CLT_LIB"
    )
fi

# `"${flags[@]}"` alone aborts under `set -u` in bash 3.2, the /bin/bash macOS
# ships, when the array is empty.
exec env -u SDKROOT -u DEVELOPER_DIR /usr/bin/swift test ${flags[@]+"${flags[@]}"} "$@"
