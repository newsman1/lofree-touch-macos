#!/bin/sh
set -eu
cd "$(dirname "$0")"
DEST="$PWD"
STAGE=$(mktemp -d /private/tmp/lofree-mapper-build.XXXXXX)
APP="$STAGE/Lofree Bluetooth Mapper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$STAGE/AppIcon.iconset"
# Icon packaging only: resize the generated art to Apple's iconset sizes.
for SIZE in 16 32 128 256 512; do
    DOUBLE=$((SIZE * 2))
    sips -z "$SIZE" "$SIZE" Assets/AppIcon.png --out "$STAGE/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$DOUBLE" "$DOUBLE" Assets/AppIcon.png --out "$STAGE/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
python3 build_icon.py "$STAGE/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 -module-cache-path "$STAGE/cache" -framework AppKit -framework ApplicationServices -framework IOKit -framework ServiceManagement Source/DeviceProfile.swift Source/EventFactory.swift Source/Settings.swift Source/GestureEngine.swift Source/SideDecoder.swift Source/main.swift -o "$APP/Contents/MacOS/LofreeBluetoothMapper"
cp Source/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$APP" "$DEST/LofreeBluetoothMapper-v0.4.2-arm64.zip"
echo "Verified app: $APP"
echo "Distribution: $DEST/LofreeBluetoothMapper-v0.4.2-arm64.zip"
echo "Temporary build folder (may be deleted): $STAGE"
