import 'app_dependencies.dart';

class OfflineLocalStore implements LocalStore {
  @override
  Future<void> initialize() async {}
}

class DisabledSyncClient implements SyncClient {
  @override
  Future<void> syncPendingChanges() async {}
}
