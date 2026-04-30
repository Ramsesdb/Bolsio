#!/bin/bash
# Build APK for arm64-v8a (POCO rodin daily driver) and rename to Bolsio-{version}.apk
set -e

cd "$(dirname "$0")/.."

flutter build apk --release --split-per-abi --target-platform android-arm64

VERSION=$(grep '^version:' pubspec.yaml | sed 's/.*: //;s/+.*//')
SOURCE="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
DEST="build/app/outputs/flutter-apk/Bolsio-${VERSION}.apk"

cp "$SOURCE" "$DEST"
echo "✓ $DEST ($(du -h "$DEST" | cut -f1))"
