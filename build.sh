#!/bin/bash
# ./build.sh           build ./Blossom.app
# ./build.sh install   build, copy to /Applications, launch
# ./build.sh test      run LayoutEngine tests
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

APP=Blossom.app
BUNDLE_ID=dev.blossom.Blossom
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
