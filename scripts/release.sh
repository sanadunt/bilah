#!/bin/bash
# Rilis versi baru ke GitHub: naikkan VERSION, build, zip, commit + tag, push, buat GitHub Release.
# Pakai:  ./scripts/release.sh 0.3.0 [catatan.md]
# Tanpa file catatan, isi rilis dibuat otomatis dari daftar commit.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
NOTES="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Pakai: ./scripts/release.sh 0.3.0 [catatan.md]" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "Masih ada perubahan yang belum di-commit. Commit dulu, baru rilis." >&2
    exit 1
fi
if gh release view "v$VERSION" >/dev/null 2>&1; then
    echo "Rilis v$VERSION sudah ada." >&2
    exit 1
fi

BUMPED=0
if [ "$(tr -d '[:space:]' < VERSION)" != "$VERSION" ]; then
    echo "$VERSION" > VERSION
    git add VERSION
    git commit -m "Rilis v$VERSION"
    BUMPED=1
fi

./scripts/build-app.sh
if codesign -dv build/Bilah.app 2>&1 | grep -q "Signature=adhoc"; then
    echo "Build ditandatangani ad-hoc. Update otomatis butuh sertifikat \"Bilah Local Signing\"; rilis dibatalkan." >&2
    [ "$BUMPED" = 1 ] && git reset --hard HEAD~1
    exit 1
fi

rm -f build/Bilah.zip
ditto -c -k --keepParent build/Bilah.app build/Bilah.zip

git tag "v$VERSION"
git push origin HEAD
git push origin "v$VERSION"

if [ -n "$NOTES" ]; then
    gh release create "v$VERSION" build/Bilah.zip --title "Bilah v$VERSION" --notes-file "$NOTES"
else
    gh release create "v$VERSION" build/Bilah.zip --title "Bilah v$VERSION" --generate-notes
fi
echo "Rilis v$VERSION terbit. App yang terpasang akan menawarkan update dalam 6 jam, atau lewat Update › Cek sekarang."
