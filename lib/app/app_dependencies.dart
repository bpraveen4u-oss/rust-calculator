abstract interface class LocalStore {
  Future<void> initialize();
}

abstract interface class SyncClient {
  Future<void> syncPendingChanges();
}
