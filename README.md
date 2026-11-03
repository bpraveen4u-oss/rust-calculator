# Learning Calculator

The Flutter app is an offline-first grades 3–5 learning calculator. Local
storage and sync are injected through `LocalStore` and `SyncClient`. The app
uses SQLite for pseudonymous learner profiles and per-profile calculation
history; no learner name, email, or freeform notes are requested or stored.
Local history remains until explicitly cleared and is separate from cloud
retention or deletion. Sync remains disabled by default.

## Run

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
