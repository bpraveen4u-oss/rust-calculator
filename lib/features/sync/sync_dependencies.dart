import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PairedDevice {
  const PairedDevice({required this.profileId, required this.deviceToken});

  final String profileId;
  final String deviceToken;
}

class PairingCode {
  const PairingCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

class SyncHistoryRecord {
  const SyncHistoryRecord({
    required this.id,
    required this.expression,
    required this.result,
    required this.timestamp,
    required this.topic,
  });

  final String id;
  final String expression;
  final String result;
  final String timestamp;
  final String topic;

  factory SyncHistoryRecord.fromJson(Map<String, dynamic> json) {
    return SyncHistoryRecord(
      id: json['entry_id'] as String,
      expression: json['expression'] as String,
      result: json['result'] as String,
      timestamp: json['recorded_at'] as String,
      topic: json['topic_tag'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'entry_id': id,
    'expression': expression,
    'result': result,
    'recorded_at': timestamp,
    'topic_tag': topic,
  };
}

class SyncSnapshot {
  const SyncSnapshot({
    required this.profileId,
    required this.grade,
    required this.history,
  });

  final String profileId;
  final int grade;
  final List<SyncHistoryRecord> history;

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    return SyncSnapshot(
      profileId: json['profile_id'] as String,
      grade: json['grade'] as int,
      history: (json['history'] as List<dynamic>)
          .map(
            (entry) =>
                SyncHistoryRecord.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

abstract interface class SyncApi {
  Future<PairingCode> createPairingCode(String bearerToken);

  Future<PairedDevice> pair(String code);

  Future<SyncSnapshot> sync({
    required String profileId,
    required String bearerToken,
    int? grade,
    required List<SyncHistoryRecord> history,
  });

  Future<void> eraseHistory({
    required String profileId,
    required String guardianCredential,
  });
}

abstract interface class SyncCredentialStore {
  Future<String?> read(String profileId);

  Future<void> write(String profileId, String token);

  Future<void> delete(String profileId);
}

abstract interface class ConnectivitySource {
  Future<bool> get isOnline;

  Stream<bool> get changes;

  Future<void> dispose();
}

class SecureSyncCredentialStore implements SyncCredentialStore {
  SecureSyncCredentialStore({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  String _key(String profileId) => 'sync_device_token_$profileId';

  @override
  Future<String?> read(String profileId) => _secureStorage.read(
    key: _key(profileId),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: const AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  @override
  Future<void> write(String profileId, String token) async {
    await _secureStorage.write(
      key: _key(profileId),
      value: token,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
      aOptions: const AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }

  @override
  Future<void> delete(String profileId) => _secureStorage.delete(
    key: _key(profileId),
  );
}

class ConnectivityPlusSource implements ConnectivitySource {
  ConnectivityPlusSource({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async =>
      _isConnected(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(
    _isConnected,
  );

  static bool _isConnected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  Future<void> dispose() async {}
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi({required Uri baseUri, HttpClient? httpClient})
    : _baseUri = baseUri,
      _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final HttpClient _httpClient;

  @override
  Future<PairingCode> createPairingCode(String bearerToken) async {
    final response = await _request(
      'POST',
      '/api/pairing-codes',
      bearerToken: bearerToken,
    );
    return PairingCode(
      code: response['code'] as String,
      expiresAt: DateTime.parse(response['expires_at'] as String).toUtc(),
    );
  }

  @override
  Future<PairedDevice> pair(String code) async {
    final response = await _request(
      'POST',
      '/api/pair',
      body: {'code': code},
    );
    return PairedDevice(
      profileId: response['profile_id'] as String,
      deviceToken: response['device_token'] as String,
    );
  }

  @override
  Future<SyncSnapshot> sync({
    required String profileId,
    required String bearerToken,
    int? grade,
    required List<SyncHistoryRecord> history,
  }) async {
    final path = '/v1/profiles/${Uri.encodeComponent(profileId)}/sync';
    if (grade == null && history.isEmpty) {
      return SyncSnapshot.fromJson(
        await _request('GET', path, bearerToken: bearerToken),
      );
    }
    return SyncSnapshot.fromJson(
      await _request(
        'POST',
        path,
        bearerToken: bearerToken,
        body: {
          if (grade != null) 'grade': grade,
          'history': history.map((entry) => entry.toJson()).toList(),
        },
      ),
    );
  }

  @override
  Future<void> eraseHistory({
    required String profileId,
    required String guardianCredential,
  }) async {
    final path = '/v1/profiles/${Uri.encodeComponent(profileId)}/history';
    await _request(
      'DELETE',
      path,
      guardianCredential: guardianCredential,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? bearerToken,
    String? guardianCredential,
    Map<String, Object?>? body,
  }) async {
    final request = await _httpClient.openUrl(
      method,
      _baseUri.resolve(path),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (bearerToken != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
    if (guardianCredential != null) {
      request.headers.set(
        'X-Guardian-Authorization',
        'Bearer $guardianCredential',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Sync request failed (${response.statusCode}).');
    }
    if (responseBody.isEmpty) return const {};
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  void close() {
    _httpClient.close(force: true);
  }
}

class SyncBuildConfiguration {
  const SyncBuildConfiguration._();

  static const _mode = String.fromEnvironment(
    'LEARNING_CALCULATOR_SYNC',
    defaultValue: 'disabled',
  );
  static const _baseUrl = String.fromEnvironment(
    'LEARNING_CALCULATOR_SYNC_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  static bool get developmentSyncEnabled =>
      kDebugMode && _mode == 'development';

  static Uri get developmentBaseUri {
    final uri = Uri.parse(_baseUrl);
    if (uri.scheme != 'http' ||
        !{'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host)) {
      throw StateError(
        'Development sync is restricted to the local test service.',
      );
    }
    return uri;
  }
}
