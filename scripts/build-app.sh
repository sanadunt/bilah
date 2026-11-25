#!/bin/bash
# Build Bilah.app (release) ke folder build/. Cukup Command Line Tools, tidak perlu Xcode.
# Versi diambil dari file VERSION. Tanda tangan memakai sertifikat "Bilah Local Signing" kalau ada,
# supaya izin macOS (Aksesibilitas, Automation) tidak hilang antar-update; kalau tidak ada, ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
IDENTITY="${SIGN_IDENTITY:-Bilah Local Signing}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bilah"

APP=build/Bilah.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bilah"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    swift scripts/make-icon.swift build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Helper Now Playing (MediaRemote lewat /usr/bin/perl), lihat Helpers/MediaRemoteBridge.m.
mkdir -p "$APP/Contents/Frameworks"
clang -dynamiclib -fobjc-arc -O2 -framework Foundation -framework AppKit \
    -install_name @rpath/libBilahMediaRemote.dylib \
    Helpers/MediaRemoteBridge.m -o "$APP/Contents/Frameworks/libBilahMediaRemote.dylib"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    SIGN="$IDENTITY"
else
    echo "Peringatan: sertifikat \"$IDENTITY\" tidak ada, pakai tanda tangan ad-hoc." >&2
    SIGN="-"
fi
codesign --force --sign "$SIGN" "$APP/Contents/Frameworks/libBilahMediaRemote.dylib"
codesign --force --sign "$SIGN" "$APP"

echo "Selesai: $APP (v$VERSION, build $BUILD_NUMBER)"
