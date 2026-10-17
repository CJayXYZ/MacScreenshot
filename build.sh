#!/bin/bash
# Builds MacScreenshot.app into ./build.
#   --install  also copy it to /Applications and (re)start it
#   --release  universal binary (Apple Silicon + Intel) zipped for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
if [[ "$MODE" == "--release" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    PRODUCTS=.build/apple/Products/Release
else
    swift build -c release
    PRODUCTS=.build/release
fi

APP=build/MacScreenshot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$PRODUCTS/MacScreenshot" "$APP/Contents/MacOS/MacScreenshot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/io.github.cjayxyz.MacScreenshot.agent.plist "$APP/Contents/Library/LaunchAgents/"

# App icon.
# macOS 26+: Resources/AppIcon.icon (Icon Composer format) compiled into Assets.car. The system
#   applies its standard shape and switches light / dark / tinted with the theme.
# macOS 14-15: AppIcon.icns, every size from the 1024px master (scripts/make-icon.swift).
ACTOOL_OUT=build/actool
rm -rf "$ACTOOL_OUT" && mkdir -p "$ACTOOL_OUT"
xcrun actool Resources/AppIcon.icon --compile "$ACTOOL_OUT" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$ACTOOL_OUT/partial.plist" >/dev/null
cp "$ACTOOL_OUT/Assets.car" "$APP/Contents/Resources/Assets.car"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/Icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/Icon/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# MacScreenshot Editor: a separate app (own process, own name in Activity Monitor) inside
# the main bundle. Quitting or crashing it never affects capture.
EDITOR="$APP/Contents/Helpers/MacScreenshot Editor.app"
mkdir -p "$EDITOR/Contents/MacOS" "$EDITOR/Contents/Resources"
# The executable name is what Activity Monitor shows, so it carries the readable name.
cp "$PRODUCTS/MacScreenshotEditor" "$EDITOR/Contents/MacOS/MacScreenshot Editor"
cp Resources/Editor-Info.plist "$EDITOR/Contents/Info.plist"
cp "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/Assets.car" "$EDITOR/Contents/Resources/"

# A stable signing identity keeps the Screen Recording permission across rebuilds.
IDENTITY="${MACSCREENSHOT_SIGN_IDENTITY:-Apple Development}"
# Sign the nested editor first, then the outer app (which seals the editor's signature).
if codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$EDITOR" 2>/dev/null; then
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
    echo "warning: '$IDENTITY' not found, signing ad hoc (Screen Recording permission resets each build)"
    codesign --force --sign - "$EDITOR"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

if [[ "$MODE" == "--release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    ZIP="build/MacScreenshot-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Release archive: $ZIP ($(lipo -archs "$APP/Contents/MacOS/MacScreenshot"))"
fi

if [[ "$MODE" == "--install" ]]; then
    rm -rf /Applications/MacScreenshot.app
    cp -R "$APP" /Applications/MacScreenshot.app
    # Restart the launchd-supervised copy on the new binary, or start it the first time.
    if ! launchctl kickstart -k "gui/$(id -u)/io.github.cjayxyz.MacScreenshot.agent" 2>/dev/null; then
        open /Applications/MacScreenshot.app
    fi
    echo "Installed /Applications/MacScreenshot.app"
fi
