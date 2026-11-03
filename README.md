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
showing a misleading answer.

Guardian controls are in a separate PIN-protected area. A platform biometric
unlock is offered when the device supports it. Pairing is an opt-in experiment
only; no pairing or cloud sync is available until legal/privacy review approves
the parental-consent approach. The acknowledgement in guardian controls is not
consent and does not enable sync.

The PIN is kept in platform secure storage. Biometric access uses the
`local_auth` plugin and is hidden when no supported biometric is enrolled. When
generating native runners, follow that plugin's Android activity and iOS
Face ID usage-description setup instructions before expecting biometric unlock
to work.

## Flutter app

With Flutter installed and an iOS Simulator or Android emulator/device
available, generate the native runner projects once if they are missing:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

## Test and analyze

```sh
flutter test
flutter analyze
```

Widget tests inject an in-memory local store and a fake sync client. SQLite
store-contract tests cover in-memory isolation and reopen durability using a
local database that the tests remove afterward.

## Rust service foundation

This crate is the local Rust service foundation for the Learning Calculator. It uses Axum/Tokio, SQLx, and SQLite. **It currently exposes only `GET /health/ready`; pairing and learner synchronization are not implemented or enabled. Do not send real learner data to this service.**

### Run locally

Install a current stable Rust toolchain, then from the repository root in PowerShell:

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

Configuration failures are reported explicitly (`DATABASE_URL` is required and `BIND_ADDR` must be a socket address). Database startup and migration errors are returned rather than silently ignored. No application secrets are needed or included.

### Persistence

`migrations/0001_initial_schema.sql` defines pseudonymous profiles, device references, hashed pairing-code records, and minimal history fields (expression, result, timestamp, and topic tag). It intentionally contains no learner name, email, contacts, precise location, or freeform notes. The migration is applied at startup; future API work must remain blocked until the parental-consent approach has passed legal/privacy review.

### Tests and conventions

Run:

```powershell
cargo test
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```
HTTP contract tests exercise the Axum router at its public endpoint. Migration tests apply the actual SQLx migrations to an isolated in-memory SQLite database and verify the resulting persistence contract. Keep tests at these public seams; do not couple them to framework internals or query layout.
