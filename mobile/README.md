# VIMJ Studio Mobile App (Flutter)

A Flutter app for coaches only. Students are records the admin/coach manage
(attendance subjects, fee accounts) but do not get their own login — the
backend rejects Student-role logins outright. Admins are directed to the web
dashboard instead (see `lib/features/auth/login_screen.dart`).

## One-time setup (this repo ships `lib/` and `pubspec.yaml` only)

This machine doesn't have the Flutter SDK installed, so the native `android/`
and `ios/` platform projects (Gradle files, `AndroidManifest.xml`, Xcode
project, etc.) haven't been generated or verified here — that tooling output
shouldn't be hand-written. After installing Flutter, run this once from
`mobile/`:

```bash
flutter create --org com.vimjstudio --project-name vimj_attendance .
flutter pub get
```

This generates `android/` and `ios/` without touching the `lib/` code already
here. Then add the permissions below before your first run.

### Android — `android/app/src/main/AndroidManifest.xml`

Add inside `<manifest>`, before `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Minimum SDK: set `minSdkVersion 23` in `android/app/build.gradle` (required by
`local_auth` and `geolocator`).

### iOS — `ios/Runner/Info.plist`

Add:

```xml
<key>NSCameraUsageDescription</key>
<string>Used to capture a selfie when marking attendance.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to confirm you're at the facility when checking in or marking attendance.</string>
<key>NSFaceIDUsageDescription</key>
<string>Used to unlock the app quickly and securely.</string>
```

## Configuration

The API base URL and facility geofence are compile-time `--dart-define` values
(see `lib/core/api_config.dart`), so they can differ per build without editing
code:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=FACILITY_LAT=12.9716 \
  --dart-define=FACILITY_LNG=77.5946 \
  --dart-define=GEOFENCE_RADIUS_METERS=50
```

- Android emulator → host machine backend: `http://10.0.2.2:8000`
- iOS simulator: `http://localhost:8000`
- Physical device: your machine's LAN IP, e.g. `http://192.168.1.20:8000`
- Facility lat/lng/radius should match the backend's `.env` (`FACILITY_LAT`,
  `FACILITY_LNG`, `GEOFENCE_RADIUS_METERS`) — the client-side check in
  `lib/core/geofence.dart` is just an early warning; the server re-validates
  independently on every request regardless of what the client sends.

## What's implemented

- **Auth**: login, forgot/reset password, biometric app-unlock on relaunch
  (`lib/features/auth/`), JWT access/refresh handled transparently by
  `lib/core/api_client.dart`.
- **Coach**: today's classes, geofenced facility check-in/out, per-student
  attendance marking with camera selfie + GPS (`lib/features/coach/`), leave
  requests, class swap requests, salary history + acknowledgment.
- **Offline queue**: if marking attendance fails due to no connectivity, it's
  queued in a local SQLite table (`lib/core/offline_queue.dart`) and flushed
  automatically the next time connectivity is detected
  (`lib/core/sync_service.dart`).
- **Theme**: light/dark/system toggle, persisted (`lib/core/theme_controller.dart`).
- **Notifications**: local (on-device) notifications via
  `flutter_local_notifications`. Full push delivery while the app is closed
  needs a Firebase project wired into this plugin — that's account-specific
  setup outside this codebase's scope. SMS/WhatsApp reminders are sent
  directly by the backend and don't depend on this.

## Known gap vs. the spec text

The spec lists "Swaps: accept/reject" as a coach action, but the backend API
only exposes swap *approval* to admins (`PUT /swap/{id}/approve`) — there's no
endpoint for the covering coach to accept/reject directly. The app reflects
what the backend actually supports: coaches request a swap and see its status;
admins approve or reject it (mirroring the Leave approval flow). If a coach-side
accept/reject is wanted, it needs a corresponding backend endpoint added first.
