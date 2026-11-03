import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:powersync/powersync.dart';

/// The session row's device id (2026-10-15), against the real schema and SQL:
/// a session is created stamped with its device, the active-session lookup
/// answers only with the caller's own, the watch reports every active session
/// (the another-device notice's feed), and a switch's claim moves the row to
/// the claiming device.
///
///   flutter test integration_test/session_device_repo_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_device');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<String?> storedDevice(String sessionId) async {
    final rows = await db.getAll(
      'SELECT device_id FROM fact_session WHERE session_id = ?',
      [sessionId],
    );
    return rows.single['device_id'] as String?;
  }

  test('a session carries its device; the active lookup and the claim are '
      'device-aware', () async {
    final mine = await repo.createSession(userId, deviceId: 'dev-a');
    expect(
      await storedDevice(mine),
      'dev-a',
      reason: 'the row is stamped at creation — the watch compares on it',
    );

    expect(await repo.getActiveSessionId(userId, deviceId: 'dev-a'), mine);
    expect(
      await repo.getActiveSessionId(userId, deviceId: 'dev-b'),
      isNull,
      reason:
          'another device asking for ITS active session finds nothing '
          'of its own — never mine',
    );

    // The other device starts one: two live sessions now.
    final theirs = await repo.createSession(userId, deviceId: 'dev-b');
    expect(await repo.getActiveSessionId(userId, deviceId: 'dev-a'), mine);
    expect(await repo.getActiveSessionId(userId, deviceId: 'dev-b'), theirs);

    // The watch — the notice's feed — reports both, device ids and all.
    final active = await repo.watchActiveSessions(userId).first;
    expect(active.map((s) => s.sessionId), containsAll([mine, theirs]));
    expect(active.firstWhere((s) => s.sessionId == theirs).deviceId, 'dev-b');

    // The switch's claim moves the row to the claiming device.
    await repo.claimSession(theirs, 'dev-a');
    expect(await storedDevice(theirs), 'dev-a');
    expect(await repo.getActiveSessionId(userId, deviceId: 'dev-a'), isNotNull);

    // An ended session leaves the watch.
    await repo.endSession(theirs);
    final afterEnd = await repo.watchActiveSessions(userId).first;
    expect(afterEnd.map((s) => s.sessionId), [mine]);

    // A row written without a device id (an old client) stores null — which
    // the app reads as another device's.
    final legacy = await repo.createSession(userId);
    expect(await storedDevice(legacy), isNull);
  });
}
