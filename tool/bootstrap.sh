#!/usr/bin/env bash
# Prepares a fresh checkout of Mellow and runs the checks.
#
# `android/` and `ios/` are not in the repository: they are generated here, in a
# temporary directory, and copied in. Generating them in place would let
# `flutter create` overwrite files the repository owns (pubspec.yaml, README).
set -euo pipefail

cd "$(dirname "$0")/.."

scheme="${MELLOW_OAUTH_SCHEME:-app.mellow}"

echo "▸ flutter pub get"
flutter pub get

echo "▸ generating Drift code"
dart run build_runner build --delete-conflicting-outputs

if [ ! -d android ] || [ ! -d ios ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "▸ creating platform folders (android, ios) in $tmp"
  flutter create --platforms=android,ios --org app.mellow \
    --project-name mellow "$tmp/platform"
  [ -d android ] || cp -r "$tmp/platform/android" ./android
  [ -d ios ] || cp -r "$tmp/platform/ios" ./ios
fi

echo "▸ patching Android manifest (minSdk 23, OAuth redirect scheme: $scheme)"
python3 tool/platform/prepare_android.py --scheme "$scheme"

echo "▸ flutter analyze"
flutter analyze

echo "▸ architecture rules"
bash tool/check_structure.sh

echo "▸ flutter test"
flutter test

echo "✓ Mellow is ready."
echo "  Run:      flutter run"
echo "  Install:  flutter build apk --debug"
echo "            → build/app/outputs/flutter-apk/app-debug.apk"
