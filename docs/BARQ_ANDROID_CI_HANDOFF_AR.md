# BARQ Phase 2 — Android CI handoff

This branch adds a guarded Android quality workflow. It runs Flutter dependency resolution, static analysis, Flutter tests, and a **debug validation APK** only after the Android project is present at `android/pubspec.yaml`.

## Safety
- No production deployment.
- No release signing and no production APK.
- No production database or secrets are needed for these checks.
- The workflow only uploads a short-lived validation artifact (7 days).

## Required source placement
The validated Android source archive is currently held outside this GitHub repository. It must be extracted into the repository's `android/` directory (so `android/pubspec.yaml` exists) on this branch before the Android workflow can run. Do not upload keystores, signing passwords, Firebase Admin credentials, or server secrets.

## Acceptance
A successful workflow must show all three steps passing: `flutter pub get`, `flutter analyze`, `flutter test`, followed by a successful debug APK build. This does not replace real-device/API integration testing.

The workflow deliberately does not merge or deploy anything.
