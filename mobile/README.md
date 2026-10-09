# VIMJ Studio Mobile App (Flutter)

A Flutter app for coaches and admins. Students are records the admin/coach
manage (attendance subjects, fee accounts) but do not get their own login —
the backend rejects Student-role logins outright. The login screen
(`lib/features/auth/login_screen.dart`) routes to `CoachHome` or `AdminHome`
based on the account's role. The admin view (`lib/features/admin/`) covers
day-to-day operations (students, coaches, activities, attendance, leave,
fees, salary); the web dashboard remains the fuller admin surface for
batches/analytics/reports/settings.

## Setup

`android/` and `ios/` **are committed** (unlike a typical `flutter create`
scaffold) because real, hand-added customizations live inside them — camera/
location/biometric permissions, the orange/yellow launcher icon regenerated
via `flutter_launcher_icons`, and the release-signing workaround in
`android/app/build.gradle.kts`. None of that is reproducible by re-running
`flutter create`, so it must not be treated as disposable generated output —
that was tried before and silently lost the icon and permissions on every
fresh checkout. Their own nested `android/.gitignore` / `ios/.gitignore`
already exclude the genuinely machine-specific pieces (`local.properties`,
`.gradle/`, `Pods/`, `ephemeral/`, keystores), so a plain clone is safe.

`macos/`, `windows/`, `linux/`, and `web/` are still generated on demand
(`flutter create .`) — they're unused scaffolding with no customization,
kept out of git only because there's nothing in them worth preserving.

On any machine with the Flutter SDK:

```bash
cd mobile
flutter pub get
```

Build with `flutter build apk --release` (installable `.apk`, split per ABI
for releases — see the release process note below) or `flutter build
appbundle --release` (Play Store upload format).

**If you ever add/change a permission, regenerate the launcher icon, or touch
signing config, commit the changed files under `android/`/`ios/` in the same
commit as the code change** — the whole point of tracking these folders is
that `git status` will show the diff instead of it silently disappearing on
the next machine.

### iOS signing

Building and signing the `.ipa` requires Xcode on macOS with an Apple
Developer account — that can't be done from this Windows environment. On a
Mac: `cd mobile && flutter pub get && open ios/Runner.xcworkspace` (CocoaPods
generates `ios/Pods/`, `Podfile`, and `Podfile.lock` on first build, all of
which stay untracked per `ios/.gitignore` — only `Podfile`/`Podfile.lock`
should be committed once they exist, `Pods/` itself never), set up signing in
Xcode, then `flutter build ipa --release` or Product → Archive from Xcode.
The bundle id (`com.vimjstudio.vimjAttendance`) and deployment target
(iOS 15.0) are already set.

## Configuration

The API base URL and facility geofence are compile-time `--dart-define` values
(see `lib/core/api_config.dart`), so they can differ per build without editing
code:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=FACILITY_LAT=12.9745723 \
  --dart-define=FACILITY_LNG=77.5689324 \
  --dart-define=GEOFENCE_RADIUS_METERS=100
```

- Android emulator → host machine backend: `http://10.0.2.2:8000`
- iOS simulator: `http://localhost:8000`
- Physical device: your machine's LAN IP, e.g. `http://192.168.1.20:8000`
- Facility lat/lng/radius should match the backend's `.env` (`FACILITY_LAT`,
  `FACILITY_LNG`, `GEOFENCE_RADIUS_METERS`) — the client-side check in
  `lib/core/geofence.dart` is just an early warning; the server re-validates
  independently on every request regardless of what the client sends.
  **The values above are geocoded from the facility's street address (near
  Chowdeswari Temple, TD Ln, Subhash Nagar, Cottonpete, Bengaluru 560053),
  accurate to roughly a city block, not an exact pin.** They replace an
  earlier placeholder that was ~3km off and meant attendance marking failed
  unconditionally, every time, everywhere near the real building — a release
  build that reverts to demo coordinates (from an old copy of this command,
  or omitting the flags and falling back to `api_config.dart`'s defaults)
  reintroduces exactly that. For full accuracy, stand at the facility,
  long-press the exact spot in Google Maps, and use the coordinates it shows
  instead of these.

## Release process

Android and iOS production builds must provide an HTTPS `API_BASE_URL` at build time. The mobile source has no Render production default; an unconfigured native build points to a reserved `.invalid` hostname and cannot connect. Releases must target the verified Cloud Run API configured as the GitHub Actions variable `VIMJ_API_BASE_URL`.

The next package target is `1.26.33+69`, tag `mobile-v1.26.33`. Do not build or publish it until Cloud Run Admin and Coach end-to-end verification has passed and the production release has been explicitly approved.

The release workflow verifies the tag/version, Flutter tests, analysis, and HTTPS API configuration when the tag is pushed. After E2E verification, dispatch **Verify, sign, and publish mobile APKs** with:

- `release_tag`: `mobile-v1.26.33`
- `production_e2e_verified`: `true`
- `publish_release`: `true` only when release publication is approved

The workflow signs all three ABI APKs with the persistent Android upload key, checks the signing certificate against the established fingerprint, records SHA-256 checksums, and creates the GitHub Release. The `mobile-release` GitHub environment must have its required approval configured. The workflow refuses to overwrite an existing release.

Local release builds fail if the persistent signing configuration is absent. Configure `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` as GitHub Actions secrets. Keep the keystore and credentials private; never commit or share them.
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

## Android release signing

GitHub Actions signs release APKs with a persistent upload keystore. Configure
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD` as repository Actions secrets. Keep a private backup of the
keystore and credentials; never commit them. The release workflow decodes the key
only on its ephemeral runner. All future APKs must use this same key so Android can
install them as updates without uninstalling.

