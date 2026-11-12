#!/bin/bash
# 构建 QJson 的 macOS 应用与 DMG。
#
# 默认：ad-hoc 签名 + DMG（本机/少量内部分发，零申请）。
# 正式签名与公证（需 Apple Developer Program）：
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE="qjson-notary" scripts/build_app.sh release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/Info.plist")"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/QJson.app"
DMG="$ROOT/build/QJson-$VERSION.dmg"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JSONEditor" "$APP/Contents/MacOS/QJson"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    codesign --force --deep --sign - "$APP"
    codesign --verify --strict "$APP"
fi

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/QJson.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "QJson" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [ -n "${CODESIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "已签名并公证: $DMG"
else
    echo "已生成（ad-hoc 签名，未公证）: $DMG"
    echo "首次打开被 Gatekeeper 拦截时：系统设置 → 隐私与安全性 → 仍要打开，"
    echo "或执行: xattr -dr com.apple.quarantine /Applications/QJson.app"
fi

echo "应用: $APP"
