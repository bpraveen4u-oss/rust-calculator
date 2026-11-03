# Learning Calculator

The Flutter app is an offline-first grades 3–5 learning calculator. Local
storage and sync are injected through `LocalStore` and `SyncClient`. The app
uses SQLite for pseudonymous learner profiles and per-profile calculation
history; no learner name, email, or freeform notes are requested or stored.
Local history remains until explicitly cleared and is separate from cloud
retention or deletion. Sync remains disabled by default.

The calculator evaluates arithmetic expressions on-device, including
parentheses, standard operation precedence, decimals, and proper or mixed
fractions. Results are simplified exact fractions; a decimal equivalent is
available separately. Incomplete and invalid expressions are reported without
showing a misleading answer. Learners can choose grades 3, 4, or 5 and reveal
deterministic on-device hints or worked steps separately from the immediate
answer. Fraction bars appear only for fraction addition or subtraction when
they clarify the result; no online service is used to generate learning
content.

Guardian controls are in a separate PIN-protected area. A platform biometric
unlock is offered when the device supports it. Pairing is an opt-in experiment
only; no pairing or cloud sync is available until legal/privacy review approves
the parental-consent approach. The acknowledgement in guardian controls is not
consent and does not enable sync.

When explicitly enabled in a local debug build, guardians can manually enter a
single-use pairing code or create one for an already-linked device. Device
tokens are kept in iOS Keychain or Android Keystore through
`flutter_secure_storage`; pending profile/history changes remain in the local
SQLite outbox while offline and retry after connectivity returns. The server
merges history by entry ID and the app keeps both local and remote entries.
The calculator shows sync state, queued changes, and the last successful sync.
Production sync remains disabled by default.

The PIN is kept in platform secure storage. Biometric access uses the
`local_auth` plugin and is hidden when no supported biometric is enrolled. When
generating native runners, follow that plugin's Android activity and iOS
Face ID usage-description setup instructions before expecting biometric unlock
to work.

## Prerequisites

### Run the Flutter app on Android

Install the following:

- **Flutter SDK** (stable; Flutter 3.19 or newer, with its bundled Dart SDK).
  Add the Flutter `bin` directory to `PATH`, or call `flutter.bat` by its full
  path.
- **Android Studio** with the Android SDK, Android SDK Platform-Tools, Android
  Emulator, and at least one Android SDK platform and emulator image installed.
  Android Studio's bundled Java runtime is sufficient; a separate JDK is not
  required.
- **An Android emulator or device.** For a physical device, enable developer
  options and USB debugging, and install the device's USB driver if Windows
  requires one.

After installing, open PowerShell in the repository root and check the setup:

```sh
flutter doctor
flutter doctor --android-licenses
flutter devices
```

Accept the Android SDK licenses when prompted. In Android Studio's SDK Manager,
install any SDK components `flutter doctor` reports missing. The first Android
build downloads Gradle and Android dependencies, so it requires network access.

### Optional: run the Rust service or its tests

Install the **stable Rust toolchain** with `rustup` (including `cargo`). SQLite
is used through the Rust crate and Flutter plugin dependencies; no separate
SQLite installation is required.

## Run the Flutter app

The Android runner project is included in this repository. From PowerShell at
the repository root:

```powershell
flutter pub get
flutter devices
flutter run -d <device-id>
```

For example, use the device ID shown by `flutter devices`, such as
`emulator-5554`. To use the default connected emulator without selecting an ID:

```powershell
flutter run
```

If native runner folders are missing in a fresh checkout, generate them once:

```powershell
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

For iOS, use macOS with Xcode and an iOS Simulator or device; iOS is not
available to build from Windows.

The standard app keeps cloud sync disabled. A local debug build may opt into
the development client with
`--dart-define=LEARNING_CALCULATOR_SYNC=development`; its default endpoint is
loopback, and any override is restricted to the local emulator/test host.
Release builds ignore this option. Use only synthetic test data and an isolated
development service. The normal Rust server does not expose pairing/sync routes;
the legal/privacy approval feature is not a development shortcut and must not
be enabled to exercise the Flutter fake-API tests.

## Test and analyze

```sh
flutter test
flutter analyze
```

Widget tests inject an in-memory local store and fake sync client. Sync-flow
tests use an in-memory SQLite store, controllable connectivity, and a fake API
to cover manual pairing, offline queueing/retry, duplicate-safe submission,
multi-device history merge, and visible status. SQLite store-contract tests
cover in-memory isolation and reopen durability using a local database that
the tests remove afterward.

## Rust service foundation

This crate is the local Rust service foundation for the Learning Calculator. It uses Axum/Tokio, SQLx, and SQLite. The production `main` router exposes only `GET /health/ready`; pairing and learner sync are not mounted by default. Sync contract handlers are exercised through a test-only router, and mounting learner sync in the server requires the explicit `sync-legal-approved` Cargo feature. **Legal/privacy approval has not been granted. Do not enable that feature or send real learner data to this service.**

### Run locally

With the optional Rust toolchain installed, start the service from the repository
root in PowerShell:

```powershell
$env:DATABASE_URL = "sqlite://service.db"
cargo run
```

`DATABASE_URL` is required and must be a SQLx SQLite URL. The service creates the database file if needed and applies checked-in migrations on startup. `BIND_ADDR` is optional and defaults to `127.0.0.1:3000`; use that loopback default for local development.

Check readiness:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health/ready
```

The endpoint returns `{"status":"ready"}` when SQLite can answer a query, or HTTP `503` when the database is unavailable.

Configuration failures are reported explicitly (`DATABASE_URL` is required and `BIND_ADDR` must be a socket address). Database startup and migration errors are returned rather than silently ignored. The default service requires no application secrets.

### Experimental pairing API

The router builder `app_with_pairing` adds two experimental endpoints for isolated
contract testing or future approved integration:

- `POST /api/pairing-codes` requires an existing device bearer token and returns
  a manually entered, single-use code that expires after ten minutes.
- `POST /api/pair` accepts a code and returns a new opaque device ID and bearer
  token plus the associated opaque profile ID needed by the client to link its
  local profile. Invalid, expired, and already-used codes share one response.
  Pairing attempts are limited to five per source IP per ten-minute window.

Codes are generated from 50 bits of OS randomness and stored as HMAC-SHA-256
hashes. The HMAC key must be at least 32 bytes and is supplied only when
explicitly building the experimental router. The default `main` continues to
use `app`, so neither pairing nor learner sync is exposed in production. Do not
mount `app_with_pairing` in a deployment until legal/privacy review approves the
parental-consent approach. No child email or QR flow is included.

### Persistence

`migrations/0001_initial_schema.sql` defines pseudonymous profiles, device
references, hashed pairing-code records, and minimal history fields (expression,
result, timestamp, and topic tag). `0002_device_auth_and_pairing_limits.sql`
adds unique device-token hashes and short-lived source-IP attempt buckets.

The sync HTTP contract supports `GET` and `POST /v1/profiles/{profile_id}/sync`.
Requests require a paired-device bearer token scoped to that profile and accept
only grade and history entries. History is append-only and de-duplicated by
entry ID. Unknown fields, non-math expression/result text, and nonstandard topic
tags are rejected. Responses contain only the opaque profile ID, grade, and
allowed history fields.

The schema and sync handlers do not collect learner names, email, contacts,
precise location, or notes. The `sync-legal-approved` feature is a deliberate
compile-time production gate, not evidence of approval; it must remain disabled
until U.S. legal/privacy review approves the parental-consent approach. The
test-only router is not mounted by the normal server application.

### Cloud history deletion and expiry

The experimental sync router supports
`DELETE /v1/profiles/{profile_id}/history`. It requires a bearer token from a
guardian credential provisioned for that profile in the
`X-Guardian-Authorization: Bearer <credential>` header. An ordinary linked
device bearer token is not accepted. The endpoint deletes all cloud history for
the profile and returns `204 No Content`. It keeps the pseudonymous profile
(including grade), paired devices, and pairing metadata so the profile can sync
again. The app must expose this request only through guardian-protected
controls.
The server records a clear timestamp and rejects history recorded at or before
that time, preventing ordinary retries of pre-erasure queued entries from
reintroducing them.

Guardian credentials have no self-service mint or reset endpoint. The trusted
provisioning boundary is an authorized operator/setup process with direct
administrative access to the service database: generate a high-entropy secret
outside the service, store only its SHA-256 hash in that profile's
`guardian_token_hash` column, and deliver the raw secret to the guardian over a
separately verified secure channel. Never log the secret or place it in source
control, ordinary application traffic, or deployment parameters. Until this
provisioning and secure delivery process is implemented and approved, the
erasure operation is not ready for production use.

The sync API rejects future client `recorded_at` values according to server
UTC time. Each accepted history row expires 90 days after its own recorded
timestamp. Reads omit entries at or past their expiry; cleanup physically
deletes expired rows before sync and pairing operations and from a one-minute
background retention task. Sync activity does not change `recorded_at` or
extend an entry's expiry. Profile activity is recorded in
`profiles.last_activity_at` using server UTC time when a paired device
successfully authenticates a sync read/write or creates a pairing code,
completes a pairing, or a valid guardian credential authenticates history
erasure.
Requests without valid bearer authentication and local-only calculator use do
not count. An authenticated request counts even if its payload is later rejected.
After expired history is removed, an empty profile and its linked-device and
pairing metadata are deleted once `last_activity_at` is 90 days old. These
server operations do not clear or modify the app's local history; local history
remains until the guardian clears it on that device.

Retention cleanup is a live-database operation only. It does not make copies of
the database safe to restore: do not back up learner data or enable production
sync until legal/privacy approval and a separately verified backup/deletion
policy covers every recovery copy.

### Tests and conventions

Run:

```powershell
cargo test
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```
HTTP contract tests exercise the Axum router at its public endpoint. Migration tests apply the actual SQLx migrations to an isolated in-memory SQLite database and verify the resulting persistence contract. Keep tests at these public seams; do not couple them to framework internals or query layout.

### Azure staging

The private, single-VM Azure staging template, systemd unit, and deployment,
backup, and deletion-safety instructions are in [`deploy/azure`](deploy/azure/README.md).
They do not deploy resources. Production learner data and cloud sync remain
blocked on qualified U.S. legal/privacy approval and a verified deletion-safe
backup/recovery policy.
