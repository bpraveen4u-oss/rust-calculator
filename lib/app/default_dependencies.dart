import '../features/sync/sync_coordinator.dart';
import '../features/sync/sync_dependencies.dart';
import 'app_dependencies.dart';

class DisabledSyncClient implements SyncClient {
  @override
  SyncStatus get status => const SyncStatus(phase: SyncPhase.disabled);

  @override
  Stream<SyncStatus> get statusChanges => const Stream<SyncStatus>.empty();

  @override
  bool get pairingAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncPendingChanges() async {}

  @override
  Future<void> eraseCloudHistory(
    String localProfileId,
    String guardianCredential,
  ) async {
    throw StateError('Cloud sync is disabled pending legal/privacy review.');
  }

  @override
  Future<void> pairDevice(String localProfileId, String code) async {
    throw StateError('Cloud sync is disabled pending legal/privacy review.');
  }

  @override
  Future<String> createPairingCode(String localProfileId) async {
    throw StateError('Cloud sync is disabled pending legal/privacy review.');
  }

  @override
  Future<void> dispose() async {}
}

SyncClient createDefaultSyncClient(LocalStore localStore) {
  if (!SyncBuildConfiguration.developmentSyncEnabled) {
    return DisabledSyncClient();
  }
  return SyncCoordinator(
    localStore: localStore,
    api: HttpSyncApi(baseUri: SyncBuildConfiguration.developmentBaseUri),
    credentials: SecureSyncCredentialStore(),
    connectivity: ConnectivityPlusSource(),
    enabled: true,
  );
}
