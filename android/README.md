# BARQ 1.3.4 – Firebase Cloud Messaging

## Firebase Android setup
- Firebase project: `barq-60b76`
- Android package: `com.barq.app`
- `android/app/google-services.json` is included and its project/package IDs were checked.
- Firebase Core and Firebase Messaging are declared in `pubspec.yaml`.
- Firebase initializes before the Flutter app starts.
- After login/session restore, the app requests notification permission and registers the FCM token at `/api/devices/token`.
- Token refresh is forwarded while the user is signed in.

## Build on a machine with Flutter installed
Run from the project root:

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

`pubspec.lock` and `.flutter-plugins-dependencies` are intentionally omitted from this portable ZIP so Flutter regenerates dependency resolution for the installed SDK. `android/local.properties` is also omitted because its SDK paths are machine-specific.

## Server-side requirements
The Cloudflare Worker source must be deployed with the FCM sender code, and the Cloudflare secret `FCM_SERVICE_ACCOUNT_JSON` must contain the Firebase service-account JSON. Keep that private key out of GitHub and APK files. The current sender is for private messages; group/status push delivery is not implemented yet. Actual delivery has not been tested.


## BARQ 1.3.5 build notes
- REST API now uses the stable production domain: `https://siraj-api-2026.vercel.app`.
- Realtime WebSocket remains on the Cloudflare Worker endpoint.
- Android application ID remains `com.barq.app`; minimum Android SDK remains 26 (Android 8.0).
- Build a release APK with `flutter pub get` then `flutter build apk --release`.


## Automated Android APK build (GitHub Actions)
This project includes `.github/workflows/android-apk.yml`. After pushing the project to a GitHub repository's `main` or `master` branch, GitHub Actions builds `app-release.apk`; download it from the successful run's **Artifacts** section. You can also start it manually with **Actions → Build BARQ Android APK → Run workflow**.
