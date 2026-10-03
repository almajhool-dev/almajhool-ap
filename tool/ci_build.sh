#!/usr/bin/env bash
# بناء تطبيق «المبرمج المجهول» — يُستخدم في GitHub Actions ويمكن تشغيله محليًا.
set -euo pipefail

BUILD_NUMBER="${BUILD_NUMBER:-1}"
DEFINES=()
if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
  DEFINES+=("--dart-define=SUPABASE_URL=${SUPABASE_URL}" "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
  echo ">> Supabase keys will be embedded in the build"
else
  echo ">> No Supabase keys provided: the app will ask for them on first launch"
fi

flutter --version

echo ">> [1/7] Generating Android platform files"
if [[ ! -f android/app/src/main/AndroidManifest.xml ]]; then
  flutter create --org com.almajhool --project-name almajhool_app --platforms android --no-pub .
fi

echo ">> [2/7] Patching Android config (name, permissions, minSdk, signing)"
python3 tool/patch_android.py

echo ">> [3/7] Installing packages"
flutter pub get

echo ">> [4/7] App icon + splash screen"
dart run flutter_launcher_icons
dart run flutter_native_splash:create

echo ">> [5/7] Release signing"
if [[ -n "${KEYSTORE_BASE64:-}" ]]; then
  echo "$KEYSTORE_BASE64" | base64 -d > android/app/upload-keystore.jks
  cat > android/key.properties <<EOF
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEY_PASSWORD:-$KEYSTORE_PASSWORD}
keyAlias=${KEY_ALIAS:-upload}
storeFile=upload-keystore.jks
EOF
  echo "   using your release keystore"
elif [[ -f signing/almajhool.jks ]]; then
  cp signing/almajhool.jks android/app/upload-keystore.jks
  { cat signing/signing.properties; echo "storeFile=upload-keystore.jks"; } > android/key.properties
  echo "   using the project's permanent signing key"
else
  echo "   no keystore: release is signed with the debug key"
fi

echo ">> [6/7] Static analysis"
flutter analyze --no-fatal-infos --no-fatal-warnings

echo ">> [7/7] Building"
# نسخة عالمية تعمل على كل الهواتف (32 و 64 بت)، مع تشويش الكود (Obfuscation) لحمايته
PROTECT=(--obfuscate --split-debug-info=build/symbols --target-platform android-arm,android-arm64)
VER=(--build-number="$BUILD_NUMBER" --build-name="1.0.$BUILD_NUMBER" --dart-define=APP_BUILD="$BUILD_NUMBER")
flutter build apk --release "${PROTECT[@]}" "${VER[@]}" "${DEFINES[@]}"
flutter build appbundle --release "${PROTECT[@]}" "${VER[@]}" "${DEFINES[@]}"

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/almajhool-app.apk
cp build/app/outputs/bundle/release/app-release.aab dist/almajhool-app.aab
ls -la dist

echo ">> Verifying APK signature"
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
if [[ -n "$APKSIGNER" ]]; then
  "$APKSIGNER" verify --verbose --print-certs dist/almajhool-app.apk | grep -E "Verified|Signer #1 certificate SHA-256|DOES NOT VERIFY|ERROR" || true
  "$APKSIGNER" verify dist/almajhool-app.apk
fi
unzip -l dist/almajhool-app.apk | grep -E "lib/.*/libflutter.so" || true
echo ">> BUILD OK"
