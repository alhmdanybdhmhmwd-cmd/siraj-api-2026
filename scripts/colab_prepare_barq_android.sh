#!/usr/bin/env bash
# Reproducible BARQ Android build-tool bootstrap for Google Colab (Linux).
# Run from any directory. Does not delete or recreate the Flutter project.
set -Eeuo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: Run this script from inside a cloned BARQ Git repository." >&2
  exit 2
fi

FLUTTER_ROOT="$REPO_ROOT/android"
NATIVE_ROOT="$FLUTTER_ROOT/android"
SDK_ROOT="${ANDROID_SDK_ROOT:-/content/android-sdk}"
GRADLE_VERSION="9.5.0"
CMDLINE_REV="15859902"
CMDLINE_ZIP="/tmp/barq-commandlinetools-linux-${CMDLINE_REV}.zip"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_REV}_latest.zip"
CMDLINE_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"

[[ -f "$FLUTTER_ROOT/pubspec.yaml" ]] || { echo "ERROR: Flutter project not found: $FLUTTER_ROOT" >&2; exit 3; }
[[ -f "$NATIVE_ROOT/settings.gradle.kts" ]] || { echo "ERROR: Native Android project not found: $NATIVE_ROOT" >&2; exit 4; }

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"
java -version

sudo apt-get update -y
sudo apt-get install -y curl unzip zip

# Install Android command-line tools without touching project source.
mkdir -p "$SDK_ROOT/cmdline-tools"
if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  curl -fL "$CMDLINE_URL" -o "$CMDLINE_ZIP"
  echo "$CMDLINE_SHA256  $CMDLINE_ZIP" | sha256sum -c -
  TMP_TOOLS="$(mktemp -d)"
  unzip -q "$CMDLINE_ZIP" -d "$TMP_TOOLS"
  rm -rf "$SDK_ROOT/cmdline-tools/latest"
  mkdir -p "$SDK_ROOT/cmdline-tools/latest"
  cp -a "$TMP_TOOLS/cmdline-tools/." "$SDK_ROOT/cmdline-tools/latest/"
  rm -rf "$TMP_TOOLS"
fi

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export PATH="$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$PATH"

# sdkmanager may stop reading once all licenses are accepted; then `yes` gets SIGPIPE (141).
# With pipefail enabled, tolerate only that expected status; real sdkmanager errors still fail.
yes | sdkmanager --licenses >/dev/null || {
  license_status=$?
  [[ "$license_status" -eq 141 ]] || exit "$license_status"
}
# Android 17 / API 37 is currently distributed on a preview channel.
# Channel 3 includes stable packages plus preview/canary packages.
sdkmanager --channel=3 "platform-tools" "platforms;android-37" "build-tools;37.0.0"

# Keep the existing Flutter SDK path and add/update only sdk.dir.
python3 - "$NATIVE_ROOT/local.properties" "$FLUTTER_ROOT" "$SDK_ROOT" <<'PY'
from pathlib import Path
import sys
local = Path(sys.argv[1])
flutter = sys.argv[2]
sdk = sys.argv[3]
lines = local.read_text().splitlines() if local.exists() else []
values = {}
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()
values["flutter.sdk"] = flutter
values["sdk.dir"] = sdk
local.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n")
PY

# Generate wrapper in an isolated temporary Gradle project. This avoids
# configuring BARQ's Android plugins just to create the standard wrapper files.
GRADLE_HOME_TMP="$(mktemp -d)"
curl -fL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o "$GRADLE_HOME_TMP/gradle.zip"
unzip -q "$GRADLE_HOME_TMP/gradle.zip" -d "$GRADLE_HOME_TMP"
mkdir -p "$GRADLE_HOME_TMP/wrapper-project"
(
  cd "$GRADLE_HOME_TMP/wrapper-project"
  "$GRADLE_HOME_TMP/gradle-${GRADLE_VERSION}/bin/gradle" wrapper \
    --gradle-version "$GRADLE_VERSION" --distribution-type all
)
mkdir -p "$NATIVE_ROOT/gradle/wrapper"
install -m 755 "$GRADLE_HOME_TMP/wrapper-project/gradlew" "$NATIVE_ROOT/gradlew"
install -m 644 "$GRADLE_HOME_TMP/wrapper-project/gradlew.bat" "$NATIVE_ROOT/gradlew.bat"
install -m 644 "$GRADLE_HOME_TMP/wrapper-project/gradle/wrapper/gradle-wrapper.jar" "$NATIVE_ROOT/gradle/wrapper/gradle-wrapper.jar"
install -m 644 "$GRADLE_HOME_TMP/wrapper-project/gradle/wrapper/gradle-wrapper.properties" "$NATIVE_ROOT/gradle/wrapper/gradle-wrapper.properties"
chmod +x "$NATIVE_ROOT/gradlew"
rm -rf "$GRADLE_HOME_TMP"

echo "=== Verify Android SDK ==="
sdkmanager --list_installed
echo "=== Verify Gradle wrapper ==="
cd "$NATIVE_ROOT"
./gradlew --version
echo "=== Verify Flutter Android toolchain ==="
cd "$FLUTTER_ROOT"
flutter doctor -v

echo
echo "BOOTSTRAP COMPLETE."
echo "Next: run flutter pub get, flutter analyze, flutter test, then build APK."
echo "The SDK is runtime tooling; commit the generated Gradle wrapper files to Git."
