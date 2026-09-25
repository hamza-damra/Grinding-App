# الجاروشة — Grinding App

Shop-floor Android app for Taleeb grinding workers (`GRINDING_WORKER`):
PIN login → scan or type the 12-digit roll / pallet number → `/check` →
«بدء الجرش» → physical grinding → «تأكيد انتهاء الجرش».

- **Business / API contract:** [`docs/GRINDING_APP_BACKEND_CONTRACT.md`](docs/GRINDING_APP_BACKEND_CONTRACT.md)
  (endpoints under `/api/v1/grinding-app`, envelope, session codes, idempotency §4.4, Arabic copy §10).
- **Engineering / UX reference:** the Taleeb Operator App (same stack, theme, widgets, Riverpod/Dio patterns).

Toolchain: Flutter 3.44 / Dart 3.12. Android only.

## Configuration

Everything is a compile-time `--dart-define`. There are **no defaults for secrets in source**.

| Key | Meaning |
|---|---|
| `APP_ENV` | `production` \| `staging` \| `dev` (release builds default to `production`) |
| `API_BASE_URL` | Backend origin. Production builds fall back to `https://taleeb.me`; any other build **must** set it. |
| `DEVICE_KEY` | The per-installation device key sent as `X-Device-Key`. No default: without it the app shows the config screen and sends nothing. |

Keep real values in a gitignored file and pass it whole:

```sh
cp env/dev.example.json env/dev.local.json     # fill in; *.local.json is gitignored
flutter run --dart-define-from-file=env/dev.local.json
flutter build apk --release --dart-define-from-file=env/prod.local.json
```

Never commit `env/*.local.json`, keystores or `key.properties` (all in `.gitignore`).

### Transport policy — no credentials over cleartext

The PIN, the device key and the session token only ever travel over HTTPS.

- **Release:** HTTPS only. `network_security_config.xml` (main) forbids cleartext for every host, and
  `AppConfig` refuses a non-HTTPS base URL (config screen, nothing sent).
- **Debug / profile:** plain HTTP is allowed **only to the device loopback** (`localhost`, `127.0.0.1`),
  which is what `adb reverse` uses — traffic never leaves the USB link:
  ```sh
  adb reverse tcp:8080 tcp:8080          # device 127.0.0.1:8080 → host :8080
  flutter run --dart-define-from-file=env/dev.local.json   # API_BASE_URL=http://127.0.0.1:8080
  ```
  The host side of that port can be a local backend or an **encrypted** tunnel (e.g. `ssh -L 8080:…`)
  to a test server.
- A `TransportGuardInterceptor` (first in the Dio chain) refuses any non-HTTPS, non-loopback request
  before a credential header is attached; Dio never follows redirects.
- **One lab exception (owner-approved 2026-09-22):** plain HTTP to `hamzadamra.ddns.net` only, and only in a
  build compiled with `ALLOW_CLEARTEXT_LAB=true` **and** a non-production `APP_ENV`. The Dart layer
  (`AppConfig.cleartextLabHost`) and Android (`network_security_config_lab.xml`, selected by
  `app/build.gradle.kts` from the same define) both name that single host; production builds and every other
  host stay HTTPS-only, and the live smoke test still refuses it. A lab build may only carry **disposable
  test credentials and a test device key** — never the shared factory device key or a real worker PIN:
  ```sh
  cp env/ddns.example.json env/ddns.local.json      # fill in the TEST device key; gitignored
  flutter build apk --release --split-per-abi --target-platform android-arm64 \
    --dart-define-from-file=env/ddns.local.json     # → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
  ```
- There is no cleartext exception for any other DDNS or LAN host.

## Architecture

Feature-first `data / domain / presentation` (same layout as the Operator App):

```
lib/
  app/        router (auth redirect), splash, config-missing screen, MaterialApp (ar, RTL, text scale ≤1.2)
  core/       config, api (Dio + interceptors), auth session, errors (+ all Arabic copy), formatting
              (Asia/Hebron time, decimal weight, bidi isolates, Arabic-Indic digits), storage, theme, widgets
  features/   grinding_auth, grinding_orders, home, scanner
```

- Riverpod 2 with manual providers; Dio chain: transport guard → redacting logger (debug only) → read-only
  retry (GET + `/check`) → device key → session token (+ auth generation) → error envelope → session
  invalidation signal.
- `ArabicMessages` is the single source of worker-facing text. Backend `error.message` (English) is never
  shown; unknown codes show «تعذر تنفيذ العملية. حاول مرة أخرى.».
- Hand-written sealed classes and DTOs (no code generation).

### Shared roll/pallet numbers (contract §4.2)

- The backend decides which item a scanned number means. When the number names a roll and a pallet and
  only one can be acted on, `/check` answers with that one (`AUTO_RESOLVED`); the card names the other item
  and the START / COMPLETE confirmation says which item is being ground. The app pins that item for every
  re-check of the open number, so a refresh never switches items mid-flow.
- Only when BOTH can be acted on (409 `GRINDING_IDENTIFIER_AMBIGUOUS`) does the worker choose «رول» /
  «طبلية» — each option shows its status and next action. The app never guesses.

### Camera scanner

- `mobile_scanner` 6 + ML Kit (bundled). **Release builds need `android/app/proguard-rules.pro`**: without
  its ML Kit keep rules R8 breaks `BarcodeScanning.getClient()` (NullPointerException) and every scan screen
  shows «تعذر تشغيل الكاميرا» although the permission is granted. Debug builds are not minified, so the
  problem only shows up in release.
- The camera permission is asked for explicitly (`permission_handler`, as in the Operator App) before the
  camera starts; a denied permission shows «السماح بالكاميرا», a permanently denied one «فتح الإعدادات».
- The controller is started / stopped by the screen through one serial queue; leaving the screen while
  the camera is still starting stops it only after the start returns (otherwise mobile_scanner 6 leaves the
  camera bound and every later scanner fails). Manual entry is always available.

### START / COMPLETE idempotency (contract §4.4)

- One `clientRequestId` (UUID v4) per confirmed tap, per order, per command. Cancelling a confirmation
  mints nothing.
- The id is **durably persisted before the first request**. Pending records live in
  `DurableFileStore` (app-private support directory, excluded from backups): write `*.tmp` with
  `flush: true` (fsync) → atomic rename; the send starts only after the rename returned. A failed write
  sends nothing.
  - Why not `shared_preferences` / `flutter_secure_storage`: on Android both write through
    `SharedPreferences.Editor.apply()` (flutter_secure_storage 9.x/10.x) or depend on the legacy plugin
    happening to use `commit()` — neither guarantees the value is on disk when the future completes.
  - Residual risk: Dart cannot fsync the directory, so a sudden **power loss** within the file system's
    journal interval could roll back the rename. A process kill cannot lose it (proved by
    `tool/process_kill_test.ps1`).
- Transport failures (timeout, lost connection, 408/429/5xx) are retried automatically 3× with the same id
  (1 s / 2 s / 4 s), then «انقطع الاتصال — أعد المحاولة» offers a retry with the same id.
- Records are cleared only on 2xx (including `replayed:true`) or a definitive 4xx.
- Nothing is ever sent automatically after a restart, a resume or a re-login. Restored records appear as
  Home banners and need the full confirmation again; a different worker is shown who sent it. A record
  whose order has moved on offers «تحقق من الطلب السابق», which resends the **same** id once.
- Every login/logout/invalidation opens a new *auth generation*; retry loops and late session errors from a
  previous worker are fenced by it, so worker A's command is never sent under worker B's session.

## Tests

```sh
flutter analyze
flutter test                                        # unit, API, provider and widget tests
flutter test integration_test/app_flows_test.dart -d <device>
pwsh tool/process_kill_test.ps1 -Device <device>    # real Android process-kill test
```

- `test/support/fake_grinding_backend.dart` is an in-process implementation of the contract (state machine,
  idempotency table, session codes, fault injection) plugged in behind the real Dio chain.
- `integration_test/app_flows_test.dart` runs on a device with the real secure storage, SharedPreferences and
  pending-command files (scenarios: happy path, lost response → `replayed:true`, a number shared by a roll and
  a pallet (auto-resolved / worker selection), pending approval,
  session expiry with a pending command → re-login by the same / another worker).
- `tool/process_kill_test.ps1` kills the app with SIGKILL right before / right after the server commits a
  START, reads the persisted record from the sandbox with `adb shell run-as`, relaunches, and asserts the
  same id is recovered and resent with **no new id minted**. Output: `tool/out/` (gitignored).

### Live smoke (test backend only)

`integration_test/live_smoke_test.dart` drives the real API client against a **disposable test database**
(PIN → check → START → COMPLETE → replay → shared roll/pallet number → pending approval → logout).

```sh
cp env/smoke.example.json env/smoke.local.json      # fill in; gitignored
adb reverse tcp:8080 tcp:8080                       # when API_BASE_URL is http://127.0.0.1:8080
flutter test integration_test/live_smoke_test.dart -d <device> --dart-define-from-file=env/smoke.local.json
```

- Runs only when the compile-time value `SMOKE_ENABLED` is exactly `true`; otherwise skipped.
- When enabled, a missing required value fails immediately, listing the **key names** only.
- Refuses `taleeb.me` and any non-HTTPS, non-loopback URL. Prints statuses and order numbers only — never
  the PIN, device key, token or base URL.
- **Production** checks after the cutover are read-only (contract §13): PIN login, `/sessions/me`, `/check`
  on a known legacy number, `/orders`, logout. Never START / COMPLETE in production.

## Release checklist

- `applicationId` is still the template `com.example.flutter_grinding_app` — set the Taleeb id before the
  first release (changing it later loses installed data, including pending records).
- Release signing is not configured (`build.gradle.kts` signs release with the debug key) — add the Taleeb
  keystore via a gitignored `key.properties`.
- Launcher icon: `dart run flutter_launcher_icons` (config in `pubspec.yaml`, source `assets/images/icon.jpg`).
