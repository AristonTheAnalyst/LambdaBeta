import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import '../../../core/powersync/database.dart' as ps;
import '../../../core/powersync/schema.dart';
import '../../../data/repositories/lab_mode.dart';

/// The flow lab's sandbox: its own PowerSync database, and the swap that puts
/// the app's real screens on top of it.
///
/// The sandbox is a real database with the real schema — that is the whole
/// point. Every repository, view model and screen keeps working unmodified;
/// they simply read and write here instead of the app's own file while the
/// lab is open. It is **never connected**, so nothing in it is ever uploaded,
/// and nothing in the user's account is ever downloaded into it.
///
/// The file lives beside the app's own (`lambda_lab.db` in the same support
/// directory), which makes the sandbox durable: what the user built last time
/// they were in the lab is still there when they come back. [reset] is the
/// way to start over.
class LabDatabase {
  LabDatabase._();

  static PowerSyncDatabase? _sandbox;

  /// The database the swap replaced — the app's own. Held here rather than
  /// returned to the caller so a nested or repeated [enter] can never lose it.
  static PowerSyncDatabase? _appDatabase;

  /// The open in flight, if any — two screens entering on a cold process
  /// share one open instead of racing two.
  static Future<PowerSyncDatabase>? _opening;

  /// How many live lab screens are relying on the swap.
  ///
  /// The lab is one route on the root navigator, but `push('/dev/lab')`
  /// stacks a second copy on top of the first, and Flutter disposes them in
  /// stack order — either may dispose first. The swap therefore belongs to
  /// the *set* of mounted lab screens, not to whichever entered first:
  /// [leave] hands the app's database back only when the last one is gone.
  ///
  /// 2026-10-08: before this count, the second copy's [enter] no-opped
  /// ("already in the lab") and its dispose then reverted the swap out from
  /// under the first, which stayed mounted — quietly reading and writing the
  /// real, synced database. That is how a review built in the lab reached
  /// the user's account.
  static int _holders = 0;

  /// Whether the app is currently pointed at the sandbox.
  static bool get isActive => labMode;

  static Future<String> _path() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, 'lambda_lab.db');
  }

  static Future<PowerSyncDatabase> _open() async {
    final db = PowerSyncDatabase(schema: schema, path: await _path());
    await db.initialize();
    return db;
  }

  /// Opens the sandbox (first time only) and points the app at it. One call
  /// per lab screen mount; each one must be paired with a [leave] in dispose.
  ///
  /// Call before any screen of the lab builds its view model: repositories
  /// read `ps.db` per call, so a swap made afterwards would leave a screen
  /// built before it talking to the app's real database — and, with
  /// [labMode] set, writing to it without the REST half.
  static Future<void> enter() async {
    _holders++;
    await _swapIn();
  }

  /// One lab screen is going away. Hands the app's own database back only
  /// when it was the last one still relying on the swap. Safe to call when
  /// not entered.
  static void leave() {
    if (_holders > 0) _holders--;
    if (_holders > 0) return;
    _handBack();
  }

  /// The swap-in itself — opening the sandbox first if this is a cold start.
  /// A no-op while [labMode] is already set (an earlier holder did the
  /// swap), and skipped if another screen swapped while this one awaited.
  static Future<void> _swapIn() async {
    if (labMode) return;
    final sandbox = _sandbox ?? await (_opening ??= _open());
    _opening = null;
    _sandbox = sandbox; // first to open wins; a second open is not a keeper
    if (labMode) return; // the other enter finished while this one awaited
    _appDatabase = ps.swapDatabase(sandbox);
    labMode = true;
  }

  /// The swap-back itself. [leave]'s last-holder path, and the forced step at
  /// the start of a [reset], where the sandbox file is about to be replaced
  /// and mounted screens must not be left pointing at it.
  static void _handBack() {
    final app = _appDatabase;
    if (app == null) return;
    ps.swapDatabase(app);
    _appDatabase = null;
    labMode = false;
  }

  /// Empties the sandbox: throws the file away and opens a fresh one —
  /// pointed at by the app again if the lab is open. Anything the user built
  /// last time is gone; the caller re-seeds.
  ///
  /// The app database is handed back for the length of the operation, so
  /// nothing can touch a closed sandbox while its file is being replaced.
  /// The holder count is left alone: the caller is a mounted lab screen that
  /// has not gone anywhere, and its own [leave] still has to find it.
  static Future<void> reset() async {
    final active = isActive;
    final old = _sandbox;
    _handBack();
    _sandbox = null;
    await old?.close();
    final path = await _path();
    // SQLite keeps its journal and write-ahead log beside the file. Deleting
    // only the database leaves a WAL that replays the rows this was supposed
    // to throw away — an empty-looking file that fills back up on open.
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (file.existsSync()) await file.delete();
    }
    if (active) await _swapIn();
  }
}
