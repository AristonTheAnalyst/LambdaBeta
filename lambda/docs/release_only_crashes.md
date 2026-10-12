# Release-only crashes

Notes on crashes that reproduce in a **release (AOT)** build but not in debug
(JIT). Written after the 2026-09-30 launch crash. For the practical triage
checklist, see the `release-crash-triage` skill; this file is the record of
what actually happened and why the diagnostic steps are what they are.

## Why these are confusing

Debug and release builds of the same Dart source go through **different
compilers**. `flutter run` uses the JIT; `flutter build ios --release` uses the
AOT compiler. A defect can therefore exist in exactly one of them, which means
"works when I run it, crashes when I install it" is a *compiler* symptom, not
an app-logic symptom.

It gets more confusing because the failure surfaces somewhere unrelated to the
cause. The 2026-09-30 crash threw inside `sqlite_async`'s `mapParameters`, so
the first instinct is to audit the database layer — which is a dead end.

## Incident: 2026-09-30 — launch crash after Flutter 3.44 → 3.47

### Symptom

On device, every release build aborted ~1 second after launch, **before
`runApp`** — the user saw an instant crash with no UI. Debug builds were fine,
and the same code ran fine on the previous Flutter version.

### Evidence chain

1. Crash report showed a Dart VM **FATAL / SIGABRT on a `DartWorker`** thread
   (a `sqlite_async` connection isolate), fully symbolicated:
   `mapParameters (sqlite_async/src/utils/shared_utils.dart:78)`
   ← `runStatement (native_sqlite_connection_impl.dart:343)`
   ← `handle` ← `RawReceivePort._handleMessage`.

2. The VM's fatal message was `hit null error with cid 94`. Mapping cid 94
   against the engine revision's `class_id.h` gives **`StringCid`** — so a
   selector was invoked on a `String` receiver that `String` does not
   implement. At that line, the only such calls are iterating `parameters`.

3. `_SqliteIsolateStatement.args` is a real `final List<Object?> args` field on
   an ordinary class, and isolates in one group **share a heap** — so the
   message is not deserialized. A `String` appearing where a `List<Object?>`
   belongs is a **wrong field read**: codegen.

4. Ruled out, each with a test rather than reasoning:
   - **Stale build artifacts** — full `flutter clean` + rebuild crashed
     identically.
   - **`attachedLogger`** — A/B with and without, identical crash.
   - **Schema / Supabase / fonts / intl** — the minimal harness did all of these.
   - **Native SQLite version mismatch, timing, nondeterminism** — deterministic
     3/3, and the native layer worked in the surviving harness.

5. **The decisive test.** A harness with the real 19-table schema,
   `AppFonts.init()`, `Supabase.initialize()`, `initializeDateFormatting`, and a
   full DB init **survived**. The *identical* harness **aborted** once the app's
   own code was merely *linked* into the snapshot — behind a condition the
   compiler could not fold, and never executed.

   That result ends the investigation into app behaviour: the trigger is **what
   is compiled in**, not what runs.

### Root cause

Flutter 3.47's AOT compiler miscompiled the app's **legacy PowerSync 1.x stack**.
The stack fed SQLite through a packaging mechanism the ecosystem has since
retired:

| Package | Was | Now published as |
|---|---|---|
| `sqlite3_flutter_libs` | 0.5.42 | `0.6.0+eol` — *"Not used anymore, update to version 3.x of package:sqlite3 instead"* |
| `powersync_flutter_libs` | 0.4.15+1 | `0.5.0+eol` — *"This package no longer does anything."* |

**The `+eol` marker is the tell.** It means the package is a no-op shim for a
mechanism the current toolchain has moved past. `grep eol pubspec.lock` would
have found this immediately.

### Fix

`powersync: ^1.8.0` → `^2.4.0`, which resolves `sqlite3` 2.9.4 → 3.5.2 and
`sqlite_async` 0.13.1 → 0.14.5, and drops `powersync_core` + `mutex`.

**Zero Dart source changes were required** — `flutter analyze` was clean
untouched. PowerSync Dart 2.0 replaced the CocoaPods native-libs plugins with
`sqlite3` 3.x compiled via **Dart build hooks** (`sqlite3/hook/build.dart`), so
the `sqlite3`, `sqlite3_flutter_libs`, `powersync_flutter_libs`, and
`powersync-sqlite-core` pods all disappear from `Podfile.lock`.

Footprint: `pubspec.yaml` (one line), `pubspec.lock`, `ios/Podfile.lock`.

Verified on device: cold launch, stable, no crash reports, UI rendered with
data re-synced from Supabase.

### What was NOT the cause

- **Not Xcode.** Xcode 27 caused a separate, earlier *build* failure (the
  explicit-module `VerifyModule` issue), already fixed in `ios/Podfile` and the
  xcconfigs. See [[ios-toolchain-xcode27]].
- **Not the upgrade to Flutter per se** — pinning an older Flutter would have
  hidden the problem and left the app on a retired mechanism.

### Honest limits

The exact codegen defect inside the AOT compiler was not isolated — that would
need a standalone Dart SDK repro. What is established is the *trigger class*
(code compiled into the snapshot) and that replacing the retired stack fixes it.

## Generalizing

1. **Split debug vs release early.** It halves the search space instantly.
2. **`grep eol pubspec.lock` before bisecting anything.** Retired packages are a
   bigger risk than your own recent changes.
3. **Ask "linked or executed?"** The unreachable-branch harness is the cheapest
   way to tell a compiler problem from an app problem, and it is conclusive.
4. **Prefer moving to the current major over pinning an old toolchain.** Pinning
   buys time and defers the same migration, usually with more pressure.
5. **Never install test builds on the user's phone without flagging it** — each
   `devicectl install` creates a fresh app data container, destroying the local
   database and any unsynced writes.
