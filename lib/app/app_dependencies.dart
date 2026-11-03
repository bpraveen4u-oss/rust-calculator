export 'local_store.dart';

enum SyncPhase {
  disabled,
  notPaired,
  waitingForConnection,
  syncing,
  synced,
  failed,
}

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.pendingChanges = 0,
    this.lastSuccessfulSyncAt,
  });

  final SyncPhase phase;
  final int pendingChanges;
  final DateTime? lastSuccessfulSyncAt;

  String get label => switch (phase) {
    SyncPhase.disabled => 'Sync off',
    SyncPhase.notPaired => 'Not paired',
    SyncPhase.waitingForConnection => 'Waiting for connection',
    SyncPhase.syncing => 'Syncing',
    SyncPhase.synced => 'Synced',
    SyncPhase.failed => 'Sync paused',
  };
}

abstract interface class SyncClient {
  SyncStatus get status;

  Stream<SyncStatus> get statusChanges;

  bool get pairingAvailable;

  Future<void> initialize();

  Future<void> syncPendingChanges();

  Future<void> eraseCloudHistory(
    String localProfileId,
    String guardianCredential,
  );

  Future<void> pairDevice(String localProfileId, String code);

  Future<String> createPairingCode(String localProfileId);

  Future<void> dispose();
}
