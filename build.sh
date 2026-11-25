#!/bin/bash
# ./build.sh           build ./Blossom.app
# ./build.sh install   build, copy to /Applications, launch
# ./build.sh test      run LayoutEngine tests
#
# SIGN_IDENTITY defaults to ad-hoc ("-"). Ad-hoc grants can go stale after a rebuild,
# because macOS ties them to the binary's hash. If tiling silently stops working after a
# rebuild, remove Blossom in System Settings → Privacy & Security → Accessibility and add it
# again, or set SIGN_IDENTITY to an Apple Development certificate.
set -euo pipefail
cd "$(dirname "$0")"

APP=Blossom.app
BUNDLE_ID=dev.blossom.Blossom
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

build() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Blossom"
    cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>            <string>Blossom</string>
    <key>CFBundleExecutable</key>      <string>Blossom</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
EOF
    # A stable --identifier keeps the code-signing identity consistent across rebuilds.
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "Built $APP"
}

run_tests() {
    mkdir -p .build
    swiftc -parse-as-library -swift-version 5 Sources/LayoutEngine.swift Tests/LayoutEngineTests.swift -o .build/layout-tests
    .build/layout-tests
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
        rm -rf "/Applications/$APP"
        cp -R "$APP" /Applications/
        open "/Applications/$APP"
        echo "Installed and launched /Applications/$APP"
        ;;
    *) echo "usage: $0 [build|install|test]" >&2; exit 2 ;;
esac
