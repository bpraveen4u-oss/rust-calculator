# Learning Calculator

The Flutter app is an offline-first starting point for the grades 3–5 learning
calculator. Local storage and sync are injected through `LocalStore` and
`SyncClient`; the starter app initializes local storage and does not start sync
or make network requests. The default implementations are placeholders, not
persistent storage or an enabled sync service.

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

Widget tests inject an in-memory local store and a fake sync client so app
startup and user-visible calculator entry can be tested without network access.

## Rust service foundation

This crate is the local Rust service foundation for the Learning Calculator. It uses Axum/Tokio, SQLx, and SQLite. The production `main` router exposes only `GET /health/ready`; learner synchronization is not implemented, and pairing is not mounted by default. **Do not send real learner data to this service.**

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

Configuration failures are reported explicitly (`DATABASE_URL` is required and `BIND_ADDR` must be a socket address). Database startup and migration errors are returned rather than silently ignored. The default service requires no application secrets.

### Experimental pairing API

The router builder `app_with_pairing` adds two experimental endpoints for isolated
contract testing or future approved integration:

- `POST /api/pairing-codes` requires an existing device bearer token and returns
  a manually entered, single-use code that expires after ten minutes.
- `POST /api/pair` accepts a code and returns a new opaque device ID and bearer
  token. Invalid, expired, and already-used codes share one response. Pairing
  attempts are limited to five per source IP per ten-minute window.

Codes are generated from 50 bits of OS randomness and stored as HMAC-SHA-256
hashes. The HMAC key must be at least 32 bytes and is supplied only when
explicitly building the experimental router. The default `main` continues to
use `app`, so neither pairing nor learner sync is exposed in production. Do not
mount `app_with_pairing` in a deployment until legal/privacy review approves the
parental-consent approach. No child email, QR flow, learner history, or sync
endpoint is included.

### Persistence

`migrations/0001_initial_schema.sql` defines pseudonymous profiles, device references, hashed pairing-code records, and minimal history fields (expression, result, timestamp, and topic tag). `0002_device_auth_and_pairing_limits.sql` adds device-token hashes and short-lived source-IP attempt buckets. The schema intentionally contains no learner name, email, contacts, precise location, or freeform notes. Migrations are applied at startup; production pairing and sync must remain blocked until the parental-consent approach has passed legal/privacy review.

### Tests and conventions

Run:

```powershell
cargo test
cargo fmt --check
cargo clippy --all-targets -- -D warnings
```
HTTP contract tests exercise the Axum router at its public endpoint. Migration tests apply the actual SQLx migrations to an isolated in-memory SQLite database and verify the resulting persistence contract. Keep tests at these public seams; do not couple them to framework internals or query layout.
HTTP contract tests exercise the Axum router at its public endpoint. Migration tests apply the actual SQLx migrations to an isolated in-memory SQLite database and verify the resulting persistence contract. Keep tests at these public seams; do not couple them to framework internals or query layout.
