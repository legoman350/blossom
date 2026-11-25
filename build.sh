#!/bin/bash
# ./build.sh           build build/Release/Blossom.app (the same place Xcode puts it)
# ./build.sh install   build, copy to /Applications, launch
# ./build.sh test      run LayoutEngine tests
# ./build.sh release   universal (Apple Silicon + Intel) build, zipped for a GitHub release
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
VERSION=0.1.0       # CFBundleShortVersionString; bump for each release
BUILD_NUMBER=1      # CFBundleVersion; bump for each release
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
    if [[ "${UNIVERSAL:-0}" == 1 ]]; then
        # One slice per architecture, then lipo them into a single binary, so the release
        # runs natively on both Apple Silicon and Intel Macs. The x86_64 link warns that
        # libswiftCompatibilityPacks.a has no x86_64 slice in the Command Line Tools; Blossom
        # uses nothing from it (a missing symbol would fail the link), so it's harmless.
        local slices="$BUILD_DIR/slices"
        rm -rf "$slices" && mkdir -p "$slices"
        for arch in arm64 x86_64; do
            swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "$slices/Blossom-$arch"
        done
        lipo -create "$slices/Blossom-arm64" "$slices/Blossom-x86_64" -output "$APP/Contents/MacOS/Blossom"
        rm -rf "$slices"
    else
        swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Blossom"
    fi

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
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
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
    release)
        # Releases must be signed with the real certificate: users' Accessibility grants
        # are tied to it, so an ad-hoc release would make every update ask again.
        if [[ "$SIGN_IDENTITY" == "-" ]]; then
            echo "error: release needs the \"Blossom Dev\" certificate (see the header); refusing to ship ad-hoc." >&2
            exit 1
        fi
        run_tests
        UNIVERSAL=1 build
        codesign --verify --strict --verbose=1 "$APP"
        echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Blossom")"
        ZIP="$BUILD_DIR/Blossom-$VERSION.zip"
        rm -f "$ZIP"
        # ditto, not zip: it keeps the bundle's extended attributes and code signature intact.
        ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
        echo "Release archive: $ZIP"
        shasum -a 256 "$ZIP"
        ;;
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
    *) echo "usage: $0 [build|install|test|release]" >&2; exit 2 ;;
esac
