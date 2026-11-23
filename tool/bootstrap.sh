#!/usr/bin/env bash
# Prepares a fresh checkout of Mellow and runs the sprint-01 checks.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "▸ flutter pub get"
flutter pub get

echo "▸ generating Drift code"
dart run build_runner build --delete-conflicting-outputs

if [ ! -d android ] && [ ! -d ios ]; then
  echo "▸ creating platform folders (android, ios)"
  flutter create --platforms=android,ios --org app.mellow --project-name mellow .
fi

echo "▸ flutter analyze"
flutter analyze

echo "▸ flutter test"
flutter test

echo "✓ Mellow foundation is ready. Run: flutter run"
