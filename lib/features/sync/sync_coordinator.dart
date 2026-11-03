import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app_dependencies.dart';
import 'sync_dependencies.dart';

class SyncCoordinator implements SyncClient {
  SyncCoordinator({
    required LocalStore localStore,
    required SyncApi api,
    required SyncCredentialStore credentials,
    required ConnectivitySource connectivity,
    required bool enabled,
  }) : _localStore = localStore,
       _api = api,
       _credentials = credentials,
       _connectivity = connectivity,
       _enabled = enabled && kDebugMode,
       _status = SyncStatus(
         phase: enabled && kDebugMode
             ? SyncPhase.notPaired
             : SyncPhase.disabled,
       );

  final LocalStore _localStore;
  final SyncApi _api;
  final SyncCredentialStore _credentials;
  final ConnectivitySource _connectivity;
  final bool _enabled;
  final StreamController<SyncStatus> _statusChanges =
      StreamController<SyncStatus>.broadcast();

  SyncStatus _status;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _syncing;
  bool _disposed = false;

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> get statusChanges => _statusChanges.stream;

  @override
  bool get pairingAvailable => _enabled;

  @override
  Future<void> initialize() async {
    if (!_enabled || _disposed) return;
    _connectivitySubscription ??= _connectivity.changes.listen(
      (online) {
        if (online) {
          unawaited(syncPendingChanges().catchError((Object _) {}));
        } else {
          unawaited(_refreshStatus(SyncPhase.waitingForConnection));
        }
      },
    );
    if (await _connectivity.isOnline) {
      try {
        await syncPendingChanges();
      } catch (_) {
        // A service outage must not prevent local calculator use.
      }
    } else {
      await _refreshStatus(SyncPhase.waitingForConnection);
    }
  }

  @override
  Future<void> pairDevice(String localProfileId, String code) async {
    _ensureEnabled();
    if (!await _connectivity.isOnline) {
      await _refreshStatus(SyncPhase.waitingForConnection);
      throw StateError('Connect to the internet to pair this device.');
    }
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw ArgumentError.value(code, 'code', 'Enter a pairing code.');
    }
    final pairedDevice = await _api.pair(normalizedCode);
    if (pairedDevice.profileId.isEmpty || pairedDevice.deviceToken.isEmpty) {
      throw const FormatException('The pairing service returned invalid data.');
    }
    await _credentials.write(localProfileId, pairedDevice.deviceToken);
    try {
      await _localStore.linkSyncProfile(
        localProfileId: localProfileId,
        remoteProfileId: pairedDevice.profileId,
      );
    } catch (_) {
      await _credentials.delete(localProfileId);
      rethrow;
    }
    await _refreshStatus(SyncPhase.synced);
    try {
      await syncPendingChanges();
    } catch (_) {
      // Pairing succeeded; the durable outbox will retry when sync is available.
    }
  }

  @override
  Future<String> createPairingCode(String localProfileId) async {
    _ensureEnabled();
    if (!await _connectivity.isOnline) {
      await _refreshStatus(SyncPhase.waitingForConnection);
      throw StateError('Connect to the internet to create a pairing code.');
    }
    final token = await _credentials.read(localProfileId);
    if (token == null) {
      throw StateError('Pair this device before creating another pairing code.');
    }
    final pairingCode = await _api.createPairingCode(token);
    return '${pairingCode.code} (expires ${pairingCode.expiresAt.toLocal()})';
  }

  @override
  Future<void> syncPendingChanges() {
    if (!_enabled || _disposed) return Future<void>.value();
    final current = _syncing;
    if (current != null) return current;
    final operation = _runSync();
    _syncing = operation;
    return operation.whenComplete(() {
      if (identical(_syncing, operation)) _syncing = null;
    });
  }

  @override
  Future<void> eraseCloudHistory(
    String localProfileId,
    String guardianCredential,
  ) async {
    _ensureEnabled();
    final credential = guardianCredential.trim();
    if (credential.isEmpty) {
      throw ArgumentError.value(
        guardianCredential,
        'guardianCredential',
        'Enter the guardian credential.',
      );
    }
    if (!await _connectivity.isOnline) {
      await _refreshStatus(SyncPhase.waitingForConnection);
      throw StateError('Connect to the internet to delete cloud history.');
    }
    SyncProfileState? linkedProfile;
    for (final profile in await _localStore.getSyncProfiles()) {
      if (profile.profile.id == localProfileId) {
        linkedProfile = profile;
        break;
      }
    }
    if (linkedProfile == null) {
      throw StateError('This learner profile is not paired with cloud sync.');
    }
    await _api.eraseHistory(
      profileId: linkedProfile.remoteProfileId,
      guardianCredential: credential,
    );
  }

  Future<void> _runSync() async {
    if (!await _connectivity.isOnline) {
      await _refreshStatus(SyncPhase.waitingForConnection);
      return;
    }

    final linkedProfiles = await _localStore.getSyncProfiles();
    if (linkedProfiles.isEmpty) {
      await _refreshStatus(SyncPhase.notPaired);
      return;
    }

    await _refreshStatus(SyncPhase.syncing);
    try {
      for (final linked in linkedProfiles) {
        if (_disposed) return;
        final token = await _credentials.read(linked.profile.id);
        if (token == null) {
          throw StateError('Secure sync credential is unavailable.');
        }
        final pending = await _localStore.getPendingSyncChanges(
          linked.profile.id,
        );
        if (pending == null) continue;
        final outgoingHistory = pending.history
            .map(
              (entry) => SyncHistoryRecord(
                id: entry.id,
                expression: entry.expression,
                result: entry.result,
                timestamp: entry.timestamp.toUtc().toIso8601String(),
                topic: entry.topic,
              ),
            )
            .toList(growable: false);
        final snapshot = await _api.sync(
          profileId: linked.remoteProfileId,
          bearerToken: token,
          grade: pending.gradeChanged ? pending.profile.grade : null,
          history: outgoingHistory,
        );
        if (snapshot.profileId != linked.remoteProfileId) {
          throw const FormatException(
            'The sync service returned a different learner profile.',
          );
        }
        final importedHistory = snapshot.history
            .map(
              (entry) => CalculationHistoryEntry(
                id: entry.id,
                profileId: linked.profile.id,
                expression: entry.expression,
                result: entry.result,
                timestamp: DateTime.parse(entry.timestamp).toUtc(),
                topic: entry.topic,
              ),
            )
            .toList(growable: false);
        await _localStore.mergeRemoteHistory(
          linked.profile.id,
          importedHistory,
        );
        if (!pending.gradeChanged) {
          await _localStore.mergeRemoteProfileGrade(
            linked.profile.id,
            grade: snapshot.grade,
          );
        }
        await _localStore.markSyncSucceeded(
          profileId: linked.profile.id,
          syncedAt: DateTime.now().toUtc(),
          syncedGrade: pending.gradeChanged ? pending.profile.grade : null,
          syncedHistoryIds: pending.history.map((entry) => entry.id).toList(),
        );
      }
      await _refreshStatus(SyncPhase.synced);
    } catch (_) {
      await _refreshStatus(
        await _connectivity.isOnline
            ? SyncPhase.failed
            : SyncPhase.waitingForConnection,
      );
      rethrow;
    }
  }

  Future<void> _refreshStatus(SyncPhase phase) async {
    if (_disposed) return;
    if (!_enabled) {
      _setStatus(const SyncStatus(phase: SyncPhase.disabled));
      return;
    }
    final linkedProfiles = await _localStore.getSyncProfiles();
    final count = await _localStore.getPendingSyncCount();
    final latestSync = linkedProfiles
        .map((profile) => profile.lastSuccessfulSyncAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (latest, next) {
          if (latest == null || next.isAfter(latest)) return next;
          return latest;
        });
    final effectivePhase = phase == SyncPhase.synced && linkedProfiles.isEmpty
        ? SyncPhase.notPaired
        : phase;
    _setStatus(
      SyncStatus(
        phase: effectivePhase,
        pendingChanges: count,
        lastSuccessfulSyncAt: latestSync,
      ),
    );
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_statusChanges.isClosed) _statusChanges.add(status);
  }

  void _ensureEnabled() {
    if (!_enabled) {
      throw StateError('Cloud sync is disabled pending legal/privacy review.');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _connectivitySubscription?.cancel();
    await _connectivity.dispose();
    if (_api case final HttpSyncApi api) api.close();
    if (!_statusChanges.isClosed) await _statusChanges.close();
  }
}
