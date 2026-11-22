# BARQ Android Build Recovery Record

Date: 2026-11-23
Repository: alhmdanybdhmhmwd-cmd/siraj-api-2026
Preservation branch: barq/phase8-cleanup-preview-readiness-2026-11-23

## Purpose

Preserve the Android build-environment diagnosis so the final APK build can resume without repeating the audit. This record does not change production, the default branch, Firebase configuration, app identity, or application features.

## Verified project state (Google Colab audit)

Flutter project root:
`/content/siraj-api-2026/android`

Native Android project:
`/content/siraj-api-2026/android/android`

Confirmed present:
- Flutter `pubspec.yaml` and `analysis_options.yaml`
- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/app/build.gradle.kts`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/local.properties` with `flutter.sdk=/content/flutter`

Confirmed missing at audit time:
- Gradle wrapper launcher `android/gradlew`
- Gradle wrapper launcher `android/gradlew.bat`
- Gradle wrapper JAR `android/gradle/wrapper/gradle-wrapper.jar`
- Android SDK at `/content/android-sdk`, `/opt/android-sdk`, and `/usr/lib/android-sdk`
- `ANDROID_HOME` and `ANDROID_SDK_ROOT` environment variables
- system commands `gradle`, `sdkmanager`, and `adb`

Java:
- Java 17 is installed at `/usr/lib/jvm/java-17-openjdk-amd64`.

Existing Gradle wrapper properties request:
- Gradle distribution: `gradle-9.5.0-all.zip`

Existing Android Gradle configuration (observed, not modified):
- Application ID / namespace: `com.barq.app`
- compileSdk: 37
- minSdk: 26
- Java/Kotlin target: 17
- Android Gradle Plugin declaration: 9.3.1
- Kotlin Android plugin declaration: 2.4.20
- Google Services plugin: 4.4.2

## Important status

The Gradle configuration files exist, but the wrapper is incomplete and the Android SDK is not installed/configured in the audited Colab runtime. Therefore, no successful Android APK build has yet been established by this audit. Flutter dependency resolution, analysis, and Dart tests were reported successful in the preceding audit; those results do not prove an Android APK can be built.

## Safe continuation procedure

1. Re-check out this preservation branch and confirm the current commit before changing anything.
2. Keep Java 17.
3. Install Android command-line tools and configure an SDK directory; set both `ANDROID_HOME` and `ANDROID_SDK_ROOT` to that directory.
4. Install Android platform 37 and a compatible Android build-tools package using `sdkmanager`; accept SDK licenses and verify `sdkmanager --list_installed`.
5. Restore the Gradle wrapper for the exact configured Gradle version (9.5.0), including both launcher scripts and `gradle-wrapper.jar`. Do not hand-write the JAR or silently change the Gradle/AGP/Kotlin versions.
6. Verify wrapper files and run `./gradlew --version` from the native Android directory.
7. Run Flutter Android release build from the Flutter project root. Record the actual exit code and generated APK paths/sizes.
8. Commit any verified source-level wrapper restoration to this preservation branch, never directly to `main`. Keep generated SDK files and build outputs out of Git.

## Safety constraints

- Do not delete or recreate the Flutter project.
- Do not overwrite `local.properties` without preserving the Flutter SDK path.
- Do not change Firebase project/app IDs, application ID, signing configuration, or features as part of environment recovery.
- Do not claim the build is complete until an APK is produced and its existence/size are verified.
- Real-device testing remains separate from Colab/CI build verification.
