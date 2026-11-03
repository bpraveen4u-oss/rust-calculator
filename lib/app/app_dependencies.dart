export 'local_store.dart';

abstract interface class SyncClient {
  Future<void> syncPendingChanges();
}
