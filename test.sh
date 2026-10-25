#!/bin/sh
set -eu
cd "$(dirname "$0")"
STAGE=$(mktemp -d /private/tmp/lofree-tests.XXXXXX)
xcrun swiftc -swift-version 5 -module-cache-path "$STAGE/cache" Source/DeviceProfile.swift Source/EventFactory.swift Source/Settings.swift Source/GestureEngine.swift Source/SideDecoder.swift Tests/main.swift -o "$STAGE/tests"
"$STAGE/tests" "$@"
echo "Temporary test folder (may be deleted): $STAGE"
