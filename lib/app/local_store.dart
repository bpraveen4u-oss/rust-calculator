class LearnerProfile {
  const LearnerProfile({
    required this.id,
    required this.grade,
    required this.createdAt,
  });

  final String id;
  final int grade;
  final DateTime createdAt;
}

class CalculationHistoryEntry {
  const CalculationHistoryEntry({
    required this.id,
    required this.profileId,
    required this.expression,
    required this.result,
    required this.timestamp,
    required this.topic,
  });

  final String id;
  final String profileId;
  final String expression;
  final String result;
  final DateTime timestamp;
  final String topic;
}

class SyncProfileState {
  const SyncProfileState({
    required this.profile,
    required this.remoteProfileId,
    required this.lastSuccessfulSyncAt,
  });

  final LearnerProfile profile;
  final String remoteProfileId;
  final DateTime? lastSuccessfulSyncAt;
}

class PendingSyncChanges {
  const PendingSyncChanges({
    required this.profile,
    required this.gradeChanged,
    required this.history,
  });

  final LearnerProfile profile;
  final bool gradeChanged;
  final List<CalculationHistoryEntry> history;
}

abstract interface class LocalStore {
  Future<void> initialize();

  Future<List<LearnerProfile>> getProfiles();

  Future<LearnerProfile?> getProfile(String profileId);

  Future<LearnerProfile> createProfile({required int grade});

  Future<LearnerProfile> updateProfileGrade(
    String profileId, {
    required int grade,
  });

  Future<CalculationHistoryEntry> addHistoryEntry({
    required String profileId,
    required String expression,
    required String result,
    required DateTime timestamp,
    required String topic,
  });

  Future<List<CalculationHistoryEntry>> getHistory(String profileId);

  Future<void> clearHistory(String profileId);

  Future<void> linkSyncProfile({
    required String localProfileId,
    required String remoteProfileId,
  });

  Future<List<SyncProfileState>> getSyncProfiles();

  Future<PendingSyncChanges?> getPendingSyncChanges(String profileId);

  Future<int> getPendingSyncCount();

  Future<void> mergeRemoteProfileGrade(
    String profileId, {
    required int grade,
  });

  Future<void> mergeRemoteHistory(
    String profileId,
    List<CalculationHistoryEntry> entries,
  );

  Future<void> markSyncSucceeded({
    required String profileId,
    required DateTime syncedAt,
    required int? syncedGrade,
    required List<String> syncedHistoryIds,
  });
}
