#!/bin/zsh
# Runs the SplouchCore tests.
#
# Prefers `swift test`. Falls back to driving swiftc directly when SwiftPM cannot
# launch, which is the state of a CommandLineTools install whose swift-package
# binary and llbuild framework come from different releases. The fallback pins
# the macOS SDK that matches the compiler and links the Testing framework that
# ships in CommandLineTools, so the same Swift Testing suites run either way.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if swift package describe >/dev/null 2>&1; then
    exec swift test "$@"
fi

echo "swift-package cannot launch on this toolchain; using the swiftc fallback" >&2
CLT=/Library/Developer/CommandLineTools
SDK=${SPLOUCH_SDK:-$CLT/SDKs/MacOSX15.5.sdk}
FW=$CLT/Library/Developer/Frameworks
PLUGIN=$CLT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
BUILD=$ROOT/.build/fallback
mkdir -p "$BUILD"

COMMON=(-sdk "$SDK" -swift-version 6 -strict-concurrency=complete -parse-as-library)

swiftc "${COMMON[@]}" -enable-testing \
    -module-name SplouchCore \
    -emit-module -emit-module-path "$BUILD/SplouchCore.swiftmodule" \
    -emit-library -o "$BUILD/libSplouchCore.dylib" \
    $(find Sources/SplouchCore -name '*.swift' | sort)

cat > "$BUILD/main.swift" <<'MAIN'
import Foundation
import Testing
@main struct Runner {
    static func main() async {
        let code: CInt = await Testing.__swiftPMEntryPoint()
        exit(code)
    }
}
MAIN

swiftc "${COMMON[@]}" \
    -module-name SplouchCoreTests \
    -I "$BUILD" -L "$BUILD" -lSplouchCore \
    -F "$FW" -framework Testing -Xfrontend -disable-cross-import-overlays \
    -load-plugin-library "$PLUGIN" \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$BUILD" \
    -o "$BUILD/SplouchCoreTests" \
    $(find Tests/SplouchCoreTests -name '*.swift' | sort) "$BUILD/main.swift"

exec "$BUILD/SplouchCoreTests" "$@"
