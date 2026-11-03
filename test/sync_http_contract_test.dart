import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/sync/sync_dependencies.dart';

void main() {
  test('cloud history erasure uses the guardian authorization contract',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestReceived = Completer<HttpRequest>();
    final serverDone = server.listen((request) async {
      requestReceived.complete(request);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final api = HttpSyncApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      api.close();
      await serverDone.cancel();
      await server.close(force: true);
    });

    await api.eraseHistory(
      profileId: 'cloud-profile-1',
      guardianCredential: 'guardian-secret',
    );

    final request = await requestReceived.future;
    expect(request.method, 'DELETE');
    expect(request.uri.path, '/v1/profiles/cloud-profile-1/history');
    expect(
      request.headers.value('X-Guardian-Authorization'),
      'Bearer guardian-secret',
    );
    expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
  });

  test('cloud history erasure reports unauthorized service responses',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final api = HttpSyncApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      api.close();
      await serverDone.cancel();
      await server.close(force: true);
    });

    await expectLater(
      api.eraseHistory(
        profileId: 'cloud-profile-1',
        guardianCredential: 'guardian-secret',
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('(401)'),
        ),
      ),
    );
  });

  test('HTTP sync uses the Rust history contract in both directions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final responseJson = {
      'profile_id': 'cloud-profile-1',
      'grade': 5,
      'history': [
        {
          'entry_id': 'local-entry-1',
          'expression': '8 × 7',
          'result': '56',
          'recorded_at': '2026-11-02T18:00:00.000Z',
          'topic_tag': 'multiplication',
        },
        {
          'entry_id': 'remote-entry-1',
          'expression': '9 + 6',
          'result': '15',
          'recorded_at': '2026-11-02T17:00:00.000Z',
          'topic_tag': 'addition',
        },
      ],
    };
    final requestReceived = Completer<HttpRequest>();
    final requestBody = Completer<String>();
    final serverDone = server.listen((request) async {
      requestReceived.complete(request);
      requestBody.complete(await utf8.decoder.bind(request).join());
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(responseJson));
      await request.response.close();
    });
    final api = HttpSyncApi(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      api.close();
      await serverDone.cancel();
      await server.close(force: true);
    });

    final snapshot = await api.sync(
      profileId: 'cloud-profile-1',
      bearerToken: 'device-token',
      grade: 4,
      history: const [
        SyncHistoryRecord(
          id: 'local-entry-1',
          expression: '8 × 7',
          result: '56',
          timestamp: '2026-11-02T18:00:00.000Z',
          topic: 'multiplication',
        ),
      ],
    );

    final request = await requestReceived.future;
    expect(request.method, 'POST');
    expect(request.uri.path, '/v1/profiles/cloud-profile-1/sync');
    expect(
      request.headers.value(HttpHeaders.authorizationHeader),
      'Bearer device-token',
    );
    expect(
      jsonDecode(await requestBody.future),
      {
        'grade': 4,
        'history': [
          {
            'entry_id': 'local-entry-1',
            'expression': '8 × 7',
            'result': '56',
            'recorded_at': '2026-11-02T18:00:00.000Z',
            'topic_tag': 'multiplication',
          },
        ],
      },
    );
    expect(snapshot.profileId, 'cloud-profile-1');
    expect(snapshot.grade, 5);
    expect(
      snapshot.history.map((entry) => entry.toJson()).toList(),
      responseJson['history'],
    );
  });
}
