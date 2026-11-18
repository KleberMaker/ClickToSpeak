#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "Exécuter sur Mac Apple Silicon avec Xcode 26 ou ultérieur." >&2
    exit 1
fi
mode=${1:-local}
case "$mode" in
    local) ;;
    distribution) : "${DEVELOPER_ID:?Identité Developer ID Application requise}" "${NOTARY_PROFILE:?Profil notarytool requis}" ;;
    *) echo "Utilisation : bash scripts/distribution.sh [local|distribution]" >&2; exit 2 ;;
esac
root="$PWD"
mkdir -p "$root/build" "$root/dist"
temp="$(mktemp -d "$root/build/release.XXXXXX")"
trap 'rm -rf "$temp"' EXIT
out="$root/dist/$(date +%Y%m%d-%H%M%S)-$$"
plutil -lint ClickToSpeak/Info.plist ClickToSpeak/ClickToSpeak.entitlements ClickToSpeak.xcodeproj/project.pbxproj
xcrun swiftc -swift-version 5 ClickToSpeak/DictatedText.swift Tests/main.swift -o "$temp/test-edition"
"$temp/test-edition"
xcodebuild -project ClickToSpeak.xcodeproj -scheme ClickToSpeak -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$root/build/Xcode" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build
app="$temp/image/ClickToSpeak.app"
mkdir "$temp/image"
ditto "$root/build/Xcode/Build/Products/Release/ClickToSpeak.app" "$app"
lipo -verify_arch arm64 "$app/Contents/MacOS/ClickToSpeak"
if [[ "$mode" == distribution ]]; then
    codesign --force --options runtime --timestamp --entitlements ClickToSpeak/ClickToSpeak.entitlements \
        --sign "$DEVELOPER_ID" "$app"
    ditto -c -k --keepParent "$app" "$temp/app.zip"
    xcrun notarytool submit "$temp/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
fi
codesign --verify --deep --strict "$app"
ln -s /Applications "$temp/image/Applications"
cp NOTICE.txt "$temp/image/Notice.txt"
dmg="$temp/ClickToSpeak.dmg"
hdiutil create -quiet -volname ClickToSpeak -srcfolder "$temp/image" -format UDZO "$dmg"
if [[ "$mode" == distribution ]]; then
    codesign --timestamp --sign "$DEVELOPER_ID" "$dmg"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature "$dmg"
fi
hdiutil verify "$dmg"
mkdir "$out"
ditto "$app" "$out/ClickToSpeak.app"
mv "$dmg" "$out/ClickToSpeak.dmg"
echo "Application et image disque disponibles dans $out"
