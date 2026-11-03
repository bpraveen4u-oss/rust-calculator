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
}
