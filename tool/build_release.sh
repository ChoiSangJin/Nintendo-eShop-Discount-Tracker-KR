#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
mkdir -p dist
app_version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
apk_path="dist/switch-sale-tracker-kr-arm64-v${app_version}.apk"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$apk_path"
python3 tool/verify_apk.py "$apk_path"
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_root" ]]; then
  echo 'ANDROID_HOME must point to an Android SDK for signing validation.' >&2
  exit 1
fi
"$sdk_root/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$apk_path"
