#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.0"
APP="Tools/build/VimStickies.app"
CONTENTS="$APP/Contents"

swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp .build/out/Products/Release/VimStickies "$CONTENTS/MacOS/VimStickies"
cp Tools/build/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>VimStickies</string>
	<key>CFBundleDisplayName</key>
	<string>VimStickies</string>
	<key>CFBundleIdentifier</key>
	<string>com.ssh9930.VimStickies</string>
	<key>CFBundleExecutable</key>
	<string>VimStickies</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "built $APP (v$VERSION)"
plutil -p "$CONTENTS/Info.plist" | grep -E "CFBundleShortVersionString|CFBundleVersion"