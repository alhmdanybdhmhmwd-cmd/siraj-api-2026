#!/usr/bin/env bash
# BARQ Android full diagnostic runner for Google Colab/Linux.
# Collects all relevant failures in one pass; does not edit tracked source files.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" || ! -f "$REPO_ROOT/android/pubspec.yaml" ]]; then
  echo "ERROR: Run inside the cloned BARQ repository." >&2
  exit 2
fi

FLUTTER_ROOT="$REPO_ROOT/android"
NATIVE_ROOT="$FLUTTER_ROOT/android"
REPORT_DIR="${BARQ_DIAGNOSTIC_DIR:-/content/barq-diagnostics-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$REPORT_DIR"
SUMMARY="$REPORT_DIR/summary.txt"
: > "$SUMMARY"

record() {
  printf '%-28s %s\n' "$1" "$2" | tee -a "$SUMMARY"
}

run_check() {
  local name="$1"
  shift
  local log="$REPORT_DIR/$name.log"
  echo
  echo "===== $name ====="
  printf '$'
  printf ' %q' "$@"
  printf '\n'
  "$@" >"$log" 2>&1
  local code=$?
  tail -n 100 "$log"
  record "$name" "exit=$code (full log: $log)"
  return 0
}

echo "BARQ Android diagnostics"
echo "Repository: $REPO_ROOT"
echo "Flutter project: $FLUTTER_ROOT"
echo "Report directory: $REPORT_DIR"
echo

record "git_branch" "$(git -C "$REPO_ROOT" branch --show-current)"
record "git_head" "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
record "java" "$(java -version 2>&1 | head -n 1)"
record "flutter" "$(flutter --version 2>&1 | head -n 1)"
record "android_sdk" "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-NOT_SET}}"

for path in \
  "$FLUTTER_ROOT/pubspec.yaml" \
  "$FLUTTER_ROOT/pubspec.lock" \
  "$NATIVE_ROOT/settings.gradle.kts" \
  "$NATIVE_ROOT/app/build.gradle.kts" \
  "$NATIVE_ROOT/gradlew" \
  "$NATIVE_ROOT/gradle/wrapper/gradle-wrapper.jar" \
  "$NATIVE_ROOT/gradle/wrapper/gradle-wrapper.properties"; do
  if [[ -e "$path" ]]; then record "file:$(basename "$path")" "PRESENT: $path"
  else record "file:$(basename "$path")" "MISSING: $path"; fi
done

run_check "flutter_doctor" flutter doctor -v
run_check "flutter_pub_get" bash -lc "cd '$FLUTTER_ROOT' && flutter pub get"
run_check "flutter_analyze" bash -lc "cd '$FLUTTER_ROOT' && flutter analyze"
run_check "flutter_test" bash -lc "cd '$FLUTTER_ROOT' && flutter test"
run_check "gradle_version" bash -lc "cd '$NATIVE_ROOT' && ./gradlew --version"
run_check "android_debug_apk" bash -lc "cd '$FLUTTER_ROOT' && flutter build apk --debug"

echo
echo "===== SUMMARY ====="
cat "$SUMMARY"
echo
echo "All logs saved under: $REPORT_DIR"
echo "No git add, commit, push, deployment, or production changes were performed."
