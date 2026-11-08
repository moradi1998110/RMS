#!/usr/bin/env bash
# Generates the Android project for app/ and applies everything we need on top of
# flutter create: permissions, name, icon and the release signing key. Run from app/.
# Shared by the app build and the release workflows so both produce the same app.
#
# With ANDROID_SIGNING_PASSWORD set and app/signing/zad-upload.jks.enc present, release
# builds are signed with ZAD's own key, so each new version installs over the last.
# Without them they fall back to Flutter's throwaway debug key (tests still run).
# With REQUIRE_SIGNING=1 a missing key is an error instead.
set -euo pipefail

flutter create --project-name rms --org com.rms --platforms android . > ../create.log 2>&1
# flutter create overwrites some of our files, such as the lint rules.
git checkout -- .
rm -f test/widget_test.dart

manifest=android/app/src/main/AndroidManifest.xml
sed -i 's|<manifest xmlns:android="http://schemas.android.com/apk/res/android">|&\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.CAMERA"/>\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>|' "$manifest"
sed -i 's|android:label="[^"]*"|android:label="ZAD"|' "$manifest"
grep -q 'android.permission.REQUEST_INSTALL_PACKAGES' "$manifest"

# The launcher icon is drawn in SVG (assets/icon) and rendered for every screen
# density, so no image editor or committed PNGs are needed.
if ! command -v rsvg-convert > /dev/null; then
  sudo apt-get install -y -qq librsvg2-bin > /dev/null
fi
res=android/app/src/main/res
for density in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  name="${density%%:*}"
  size="${density##*:}"
  mkdir -p "$res/mipmap-$name"
  rsvg-convert -w "$size" -h "$size" assets/icon/zad_legacy.svg -o "$res/mipmap-$name/ic_launcher.png"
  # Adaptive layers are 108dp for a 48dp icon.
  layer=$((size * 108 / 48))
  rsvg-convert -w "$layer" -h "$layer" assets/icon/zad_foreground.svg -o "$res/mipmap-$name/ic_launcher_foreground.png"
done
mkdir -p "$res/mipmap-anydpi-v26" "$res/values"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML
cat > "$res/values/ic_launcher_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFF4E2</color>
</resources>
XML
grep -q 'android:icon="@mipmap/ic_launcher"' "$manifest"

# Release signing. The key file is committed only in encrypted form; the password
# lives in the repository's secrets.
encrypted=signing/zad-upload.jks.enc
if [ -n "${ANDROID_SIGNING_PASSWORD:-}" ] && [ -f "$encrypted" ]; then
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in "$encrypted" -out android/app/zad-upload.jks \
    -pass env:ANDROID_SIGNING_PASSWORD
  cat > android/app/zad-signing.gradle <<'GRADLE'
// Added by scripts/prepare-android.sh: signs release builds with ZAD's own key.
android {
    signingConfigs {
        zad {
            storeFile file('zad-upload.jks')
            storePassword System.getenv('ANDROID_SIGNING_PASSWORD')
            keyAlias 'zad'
            keyPassword System.getenv('ANDROID_SIGNING_PASSWORD')
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.zad
        }
    }
}
GRADLE
  if [ -f android/app/build.gradle.kts ]; then
    printf '\napply(from = "zad-signing.gradle")\n' >> android/app/build.gradle.kts
  else
    printf "\napply from: 'zad-signing.gradle'\n" >> android/app/build.gradle
  fi
  echo "signing: ZAD release key"
elif [ "${REQUIRE_SIGNING:-0}" = 1 ]; then
  echo "The release key is missing: add ANDROID_SIGNING_PASSWORD and run 'Create signing key' first." >&2
  exit 1
else
  echo "signing: debug key (no release key available)"
fi
