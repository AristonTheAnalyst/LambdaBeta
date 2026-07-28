import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'schema.dart';

final _log = Logger('powersync');

const _powersyncUrl =
    'https://6a5f2f813ab36f9f81820b7d.powersync.journeyapps.com';

// Maps each table to its real Supabase primary key column name.
// PowerSync uses 'id' internally; we remap on upload.
const _pkColumns = {
  'dim_user': 'user_id',
  'fact_workout': 'user_workout_id',
  'dim_exercise': 'custom_exercise_id',
  'dim_variation': 'custom_variation_id',
  'fact_bodyweight': 'user_weight_id',
  'fact_workout_set': 'workout_set_id',
  'dim_program': 'program_id',
  'dim_planned_workout': 'planned_workout_id',
  'dim_planned_set': 'planned_set_id',
  'fact_program_run': 'program_run_id',
};

// Postgres integer[] columns are mirrored locally as Column.text (written as
// JSON-encoded strings, same as how they arrive via download sync). Undo that
// encoding on the way back up, or PostgREST receives a string instead of an
// array.
const _arrayColumns = {
  'workout_set_reps',
  'workout_set_duration_seconds',
  'target_reps',
  'target_duration_seconds',
};

Map<String, dynamic> _decodeArrayColumns(Map<String, dynamic> data) {
  final result = Map<String, dynamic>.of(data);
  for (final col in _arrayColumns) {
    final v = result[col];
    if (v is String) {
      try {
        result[col] = jsonDecode(v);
      } catch (_) {}
    }
  }
  return result;
}

final _fatalCodes = [
  RegExp(r'^22...$'), // data exception
  RegExp(r'^23...$'), // integrity constraint violation
  RegExp(r'^42501$'), // insufficient privilege / RLS
];

class SupabaseConnector extends PowerSyncBackendConnector {
  final PowerSyncDatabase db;
  Future<void>? _refreshFuture;

  SupabaseConnector(this.db);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    await _refreshFuture;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: _powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  @override
  void invalidateCredentials() {
    _refreshFuture = Supabase.instance.client.auth
        .refreshSession()
        .timeout(const Duration(seconds: 5))
        .then((_) => null, onError: (_) => null);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    final rest = Supabase.instance.client.rest;
    CrudEntry? lastOp;
    try {
      for (final op in transaction.crud) {
        lastOp = op;
        final pkCol = _pkColumns[op.table] ?? 'id';
        final table = rest.from(op.table);

        if (op.op == UpdateType.put) {
          final data = _decodeArrayColumns(op.opData ?? {});
          data[pkCol] = op.id;
          await table.upsert(data);
        } else if (op.op == UpdateType.patch) {
          await table.update(_decodeArrayColumns(op.opData!)).eq(pkCol, op.id);
        } else if (op.op == UpdateType.delete) {
          await table.delete().eq(pkCol, op.id);
        }
      }
      await transaction.complete();
    } on PostgrestException catch (e) {
      if (e.code != null && _fatalCodes.any((r) => r.hasMatch(e.code!))) {
        _log.severe('Fatal upload error - discarding $lastOp', e);
        await transaction.complete();
      } else {
        rethrow;
      }
    }
  }
}

late final PowerSyncDatabase db;

bool isLoggedIn() =>
    Supabase.instance.client.auth.currentSession?.accessToken != null;

Future<void> openDatabase() async {
  db = PowerSyncDatabase(
    schema: schema,
    path: await _dbPath(),
    logger: attachedLogger,
  );
  await db.initialize();

  SupabaseConnector? connector;

  if (isLoggedIn()) {
    connector = SupabaseConnector(db);
    db.connect(connector: connector);
  }

  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    switch (data.event) {
      case AuthChangeEvent.signedIn:
        connector = SupabaseConnector(db);
        db.connect(connector: connector!);
      case AuthChangeEvent.signedOut:
        connector = null;
        await db.disconnect();
      case AuthChangeEvent.tokenRefreshed:
        connector?.prefetchCredentials();
      default:
        break;
    }
  });
}

Future<void> disconnectAndClear() async {
  await db.disconnectAndClear();
}

Future<String> _dbPath() async {
  const filename = 'lambda.db';
  if (kIsWeb) return filename;
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, filename);
}
