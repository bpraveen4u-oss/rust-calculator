# Learning Calculator

The Flutter app is an offline-first starting point for the grades 3–5 learning
calculator. Local storage and sync are injected through `LocalStore` and
`SyncClient`; the starter app initializes local storage and does not start sync
or make network requests. The default implementations are placeholders, not
persistent storage or an enabled sync service.

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

Widget tests inject an in-memory local store and a fake sync client so app
startup and user-visible calculator entry can be tested without network access.
