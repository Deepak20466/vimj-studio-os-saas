# VIMJ Studio OS SaaS — Mobile App (Flutter)

A Flutter app for coaches and admins. Students are records the admin/coach
manage (attendance subjects, fee accounts) but do not get their own login —
the backend rejects Student-role logins outright. The login screen
(`lib/features/auth/login_screen.dart`) routes to `CoachHome` or `AdminHome`
based on the account's role. The admin view (`lib/features/admin/`) covers
day-to-day operations (students, coaches, activities, attendance, leave,
fees), reports, batch analytics, and the Admin-only AI Command Center. Coaches
continue to use their separate student and attendance dashboard.

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

Production backend: **https://vimj-backend-eqwnplgd6q-el.a.run.app** (Google
Cloud Run, `asia-south1`; PostgreSQL is hosted by Supabase). The Cloud Run
service scales to zero when idle, so a cold start can take longer than a warm
request. Any APK built for distribution off the office LAN must point at this
URL, not a LAN IP:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://vimj-backend-eqwnplgd6q-el.a.run.app \
  --dart-define=FACILITY_LAT=12.9745723 \
  --dart-define=FACILITY_LNG=77.5689324 \
  --dart-define=GEOFENCE_RADIUS_METERS=100
```

Set the configured API and facility values to match the backend deployment. To
publish an APK, update `version` in `pubspec.yaml`, commit the change, then push
a `mobile-vX.Y.Z` tag. The GitHub Actions workflow builds and attaches the three
split-ABI APKs to the release. It signs builds with the persistent Android
keystore configured in repository Actions secrets; keep that key private and
use the same key for future updates.

```bash
git tag mobile-vX.Y.Z
git push origin mobile-vX.Y.Z
```

Installers should use the APKs attached to the latest GitHub release tag.
## What's implemented

- **Admin AI Command Center**: Admin-only revenue-risk predictions, fee
  reminder queue actions, next-month collection forecast, and batch
  profitability/attendance insights. Predictions use local rules and the
  authenticated FastAPI endpoint; no paid AI API is required. Coach screens do
  not include these insights. Claude Desktop accesses the separate MCP server.
- **Auth**: login, forgot/reset password, biometric app-unlock on relaunch
  (`lib/features/auth/`), JWT access/refresh handled transparently by
  `lib/core/api_client.dart`.
- **Coach**: a separate role-based view for class lists, student attendance,
  leave requests, class swaps, fee receipts, and settings (`lib/features/coach/`).
- **Offline queue**: if marking attendance fails due to no connectivity, it's
  queued in a local SQLite table (`lib/core/offline_queue.dart`) and flushed
  automatically the next time connectivity is detected
  (`lib/core/sync_service.dart`).
- **Theme**: light/dark/system toggle, persisted (`lib/core/theme_controller.dart`).
- **Notifications**: local (on-device) notifications via
  `flutter_local_notifications`. Full push delivery while the app is closed
  needs a Firebase project wired into this plugin — that's account-specific
  setup outside this codebase's scope. The Admin reminder action queues a mock
  reminder through the backend and does not send a paid SMS/WhatsApp message.

## Android release signing

GitHub Actions signs release APKs with a persistent upload keystore. Configure
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD` as repository Actions secrets. Keep a private backup of the
keystore and credentials; never commit them. The release workflow decodes the key
only on its ephemeral runner. All future APKs must use this same key so Android can
install them as updates without uninstalling.

