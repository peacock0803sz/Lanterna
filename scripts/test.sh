#!/usr/bin/env bash
# Runs the test suite with the host Apple toolchain.
#
# SDKROOT and DEVELOPER_DIR are cleared unconditionally: Nix's devshell exports
# them pointing at an old Apple SDK that has no SwiftPM. A DEVELOPER_DIR set on
# purpose is discarded here too, so /usr/bin/swift always picks the toolchain it
# would use with no environment at all.
#
# The extra flags are added whenever the Command Line Tools directory holds
# Testing.framework, whether or not Xcode is installed as well: CLT ships Swift
# Testing outside the toolchain's default search paths, and DYLD_* variables are
# stripped from the SIP-protected test helper, so the framework and its interop
# dylib have to be baked in as rpaths at link time. Without that directory the
# flags stay empty.
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
