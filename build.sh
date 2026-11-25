#!/bin/bash
# ./build.sh           build build/Release/Blossom.app (the same place Xcode puts it)
# ./build.sh install   build, copy to /Applications, launch
# ./build.sh test      run LayoutEngine tests
#
# Needs only the Command Line Tools. Xcode users can open Blossom.xcodeproj instead; both
# produce the same signed bundle in build/.
#
# Signing decides whether the Accessibility grant survives a rebuild:
#   - Ad-hoc ("-"): macOS ties the grant to the binary's hash, so EVERY rebuild looks like
#     a new app. The toggle in System Settings stays on but no longer applies, and the app
#     keeps asking for access.
#   - Any real certificate: the grant is tied to identifier + certificate and survives
#     rebuilds. A free self-signed one is enough. Create it once in Keychain Access →
#     Certificate Assistant → Create a Certificate…, with name "Blossom Dev", identity type
#     "Self Signed Root" and certificate type "Code Signing".
# Order: $SIGN_IDENTITY if set, else "Blossom Dev" if it's in the keychain, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_DIR=build
APP_NAME=Blossom.app
APP="$BUILD_DIR/Release/$APP_NAME"
BUNDLE_ID=dev.blossom.Blossom
ICONSET_SRC=Resources/Assets.xcassets/AppIcon.appiconset

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-certificate -c "Blossom Dev" >/dev/null 2>&1; then
        SIGN_IDENTITY="Blossom Dev"
    else
        SIGN_IDENTITY="-"
        echo "note: ad-hoc signing; Accessibility must be re-granted after each rebuild (see build.sh header)" >&2
    fi
fi

build() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Blossom"

    # Xcode compiles the asset catalog with actool; here we turn the same PNGs into an
    # .icns with iconutil, which ships with the Command Line Tools.
    local iconset="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$iconset" && mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        cp "$ICONSET_SRC/icon_${size}.png" "$iconset/icon_${size}x${size}.png"
        cp "$ICONSET_SRC/icon_$((size * 2)).png" "$iconset/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$iconset"

    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>            <string>Blossom</string>
    <key>CFBundleDisplayName</key>     <string>Blossom</string>
    <key>CFBundleExecutable</key>      <string>Blossom</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF
    # A stable --identifier keeps the code-signing identity consistent across rebuilds.
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "Built $APP"
}

run_tests() {
    mkdir -p "$BUILD_DIR/tests"
    swiftc -parse-as-library -swift-version 5 Sources/LayoutEngine.swift Tests/LayoutEngineTests.swift \
        -o "$BUILD_DIR/tests/LayoutEngineTests"
    "$BUILD_DIR/tests/LayoutEngineTests"
}

case "${1:-build}" in
    build)   build ;;
    test)    run_tests ;;
    install)
        build
        pkill -x Blossom || true
        # Retire the pre-rename build of this same project.
        pkill -x Tiler || true
        rm -rf /Applications/Tiler.app
        rm -rf "/Applications/$APP_NAME"
        cp -R "$APP" /Applications/
        open "/Applications/$APP_NAME"
        echo "Installed and launched /Applications/$APP_NAME"
        ;;
    *) echo "usage: $0 [build|install|test]" >&2; exit 2 ;;
esac
