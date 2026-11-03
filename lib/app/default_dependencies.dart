import 'app_dependencies.dart';

class DisabledSyncClient implements SyncClient {
  @override
  Future<void> syncPendingChanges() async {}
}
