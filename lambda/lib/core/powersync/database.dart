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
  'fact_session': 'session_id',
  'dim_exercise': 'custom_exercise_id',
  'dim_variation': 'custom_variation_id',
  'fact_bodyweight': 'user_weight_id',
  'fact_session_set': 'session_set_id',
  'dim_program': 'program_id',
  'fact_program_run': 'program_run_id',
  'fact_pr': 'pr_id',
  'dim_lesson': 'lesson_id',
  'fact_rest': 'rest_id',
  'dim_planned_session': 'session_id',
  'dim_planned_session_set': 'set_id',
  'fact_goal': 'goal_id',
};

// dim_exercise_variation_bridge is the one table with no single-column PK —
// its real Postgres primary key is the composite pair below (there's no 'id'
// column server-side at all). PUT upserts on the pair instead of a pkCol;
// PATCH needs the pair's actual values, which aren't in a PATCH's opData
// (only changed columns are), so those get looked up locally by PowerSync's
// internal id first. No DELETE case: bridge rows are soft-deleted via
// deleted_locally instead of a hard delete, sidestepping this entirely.
const _compositeKeyTables = {
  'dim_exercise_variation_bridge': ['custom_exercise_id', 'custom_variation_id'],
  'coaching_relationship': ['coach_user_id', 'athlete_user_id'],
};

// Postgres integer[] columns are mirrored locally as Column.text (written as
// JSON-encoded strings, same as how they arrive via download sync). Undo that
// encoding on the way back up, or PostgREST receives a string instead of an
// array.
const _arrayColumns = {
  'reps',
  'duration_seconds',
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
  RegExp(r'^23502$'), // NOT NULL violation (permanent)
  RegExp(r'^23505$'), // unique violation (permanent)
  RegExp(r'^23514$'), // check violation (permanent)
  RegExp(r'^42501$'), // insufficient privilege / RLS
  RegExp(r'^PGRST205$'), // table not found in schema cache (transient but
                         // unrecoverable — the row won't change, and retrying
                         // the same op keeps failing the same way)
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
    // An expired session must not be handed to PowerSync — it would retry a
    // stale token forever while the UI looks authenticated.
    if (_isExpired(session)) return null;
    return PowerSyncCredentials(
      endpoint: _powersyncUrl,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: session.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000),
    );
  }

  static bool _isExpired(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;
    // 30s buffer: a token that dies within the next 30s is treated as dead.
    return DateTime.now().millisecondsSinceEpoch / 1000 >= (expiresAt - 30);
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

        final compositeKey = _compositeKeyTables[op.table];

        if (op.op == UpdateType.put) {
          final data = _decodeArrayColumns(op.opData ?? {});
          if (compositeKey != null) {
            data.remove('id');
            await table.upsert(data, onConflict: compositeKey.join(','));
          } else {
            data[pkCol] = op.id;
            await table.upsert(data);
          }
        } else if (op.op == UpdateType.patch) {
          if (compositeKey != null) {
            final localRows = await database
                .getAll('SELECT * FROM ${op.table} WHERE id = ?', [op.id]);
            if (localRows.isEmpty) continue;
            final patchData = _decodeArrayColumns(op.opData!);
            patchData.remove('id');
            var query = table.update(patchData);
            for (final col in compositeKey) {
              query = query.eq(col, localRows.first[col]);
            }
            await query;
          } else {
            await table.update(_decodeArrayColumns(op.opData!)).eq(pkCol, op.id);
          }
        } else if (op.op == UpdateType.delete) {
          if (compositeKey != null) {
            final localRows = await database
                .getAll('SELECT * FROM ${op.table} WHERE id = ?', [op.id]);
            if (localRows.isEmpty) continue;
            var query = table.delete();
            for (final col in compositeKey) {
              query = query.eq(col, localRows.first[col]);
            }
            await query;
          } else {
            await table.delete().eq(pkCol, op.id);
          }
        }
      }
      await transaction.complete();
    } on PostgrestException catch (e) {
      if (e.code != null && _fatalCodes.any((r) => r.hasMatch(e.code!))) {
        _log.severe('Fatal upload error - discarding $lastOp', e);
        // Quarantine the failing op locally before it's dropped from the
        // upload queue, so it isn't lost with no trace. upload_failures is
        // a local-only table (not in the sync streams), so it never syncs.
        try {
          await database.writeTransaction((tx) async {
            await tx.execute(
              '''
              INSERT INTO upload_failures
                (table_name, op_id, op_type, op_data, error_code, created_at)
              VALUES (?, ?, ?, ?, ?, ?)
              ''',
              [
                lastOp?.table,
                lastOp?.id,
                lastOp?.op.name,
                lastOp?.opData == null ? null : jsonEncode(lastOp!.opData),
                e.code,
                DateTime.now().toUtc().toIso8601String(),
              ],
            );
          });
        } catch (quarantineErr) {
          _log.warning('Failed to quarantine upload failure', quarantineErr);
        }
        await transaction.complete();
      } else {
        rethrow;
      }
    }
  }
}

late final PowerSyncDatabase db;

/// Registered by features (e.g. the session screen) to release their cached
/// in-memory state when the user signs out — the local DB is being cleared,
/// so any cached ViewModels must not survive into the next user's session.
VoidCallback? onSignOutReset;

/// Invoked by the auth handler in [openDatabase] after the local DB is
/// cleared on sign-out. Kept here (core) rather than imported from a feature
/// to preserve the core → features dependency direction.
void resetForSignOut() {
  final reset = onSignOutReset;
  onSignOutReset = null;
  reset?.call();
}

/// Centralised bounded write helper — every repository that writes through
/// PowerSync should use this instead of its own copy-pasted `_exec`.  Keeps a
/// hung/stale local DB from freezing the UI: after [timeoutSeconds] the call
/// throws [TimeoutException] so the caller can surface the error.
///
/// Prefer [safeWriteTransaction] for multi-statement work that must be atomic.
Future<void> safeExec(String sql, [List<Object?> params = const []]) async {
  await db
      .execute(sql, params)
      .timeout(Duration(seconds: _execTimeoutSeconds));
}

/// Transactional wrapper — all statements run atomically or not at all.
/// The callback receives the database transaction; prefer this over multiple
/// standalone [safeExec] calls when the writes must be atomic.
Future<void> safeWriteTransaction(
    Future<void> Function(dynamic tx) fn) async {
  await db
      .writeTransaction(fn)
      .timeout(Duration(seconds: _execTimeoutSeconds));
}

/// How long a single PowerSync write may take before the helper gives up.
/// Kept as a mutable top-level so dev tools can bump it for debugging.
int _execTimeoutSeconds = 8;

/// Whether the local app has a usable authenticated session — a session
/// whose token has already expired is treated as signed out so PowerSync
/// stops retrying a stale credential and the router can redirect.
bool isLoggedIn() {
  final session = Supabase.instance.client.auth.currentSession;
  if (session?.accessToken == null) return false;
  final expiresAt = session!.expiresAt;
  if (expiresAt == null) return true;
  // Buffer so a token expiring in the next 30s is already considered dead.
  return DateTime.now().millisecondsSinceEpoch / 1000 < (expiresAt - 30);
}

Future<void> openDatabase() async {
  db = PowerSyncDatabase(
    schema: schema,
    path: await _dbPath(),
    logger: attachedLogger,
  );
  await db.initialize();

  // Purge stale CRUD entries for tables that have been renamed, dropped, or
  // are missing from the sync-stream config.  These entries will never succeed
  // on upload and block the checkpoint from applying, stalling all sync.
  try {
    await db.writeTransaction((tx) async {
      // `coaching_relationship` was historically local-only (missing from the
      // sync stream) — any queued uploads for it would fail with a 404 on the
      // PowerSync server and stall the checkpoint.
      await tx.execute(
        "DELETE FROM ps_crud WHERE table_name = 'coaching_relationship'",
      );
      // Tables renamed in the session-model redesign (2026-08-13) — queued
      // entries under the old names can never upload.
      for (final old in [
        'dim_workout',
        'dim_workout_set',
        'fact_workout',
        'fact_workout_set',
        'fact_program_goal',
        'fact_lesson',
        'dim_planned_workout',
        'dim_planned_set',
        'dim_program_goal',
      ]) {
        await tx.execute(
          'DELETE FROM ps_crud WHERE table_name = ?',
          [old],
        );
      }
    });
  } catch (_) {
    // ps_crud may not exist yet if this is the very first run — harmless.
  }

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
        // Wipe the previous user's on-device rows AND their queued offline
        // mutations — otherwise the next user on this device sees stale data
        // and the previous user's ps_crud entries upload (and are discarded)
        // under the new user's token.
        await db.disconnectAndClear();
        resetForSignOut();
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
