---
name: release-crash-triage
description: >
  Diagnose a crash that happens in a release/AOT build but not in debug —
  especially "app crashes immediately on launch on device". Use when a release
  build on a physical device dies instantly, when debug works but the installed
  build does not, when a crash report shows a Dart VM fatal (SIGABRT /
  "hit null error with cid N"), or right after a Flutter or Xcode upgrade
  breaks a previously working build. Also use before bisecting app code, to
  check the cheaper hypotheses first.
---

# Release-only crash triage (lambda)

A release-only crash is almost never in your app's logic. Release builds run
through the **AOT compiler**; debug runs through the **JIT**. They are different
compilers, so a bug can exist in exactly one of them. Bias your search toward
*the build*, not *the code*.

Real incident this skill exists for: 2026-09-30, launch crash on device. Full
forensic record in `docs/release_only_crashes.md`.

## Do these in order — cheapest first

**1. Rule out the build cache (3 min, do it first).**
```bash
flutter clean && flutter pub get && flutter build ios --release
```
Stale artifacts after a Flutter/Xcode upgrade are the most common cause. Do
this before theorising, so you can stop wondering about it.

**2. Check the dependency stack for retired packages.**
```bash
grep -n "eol" pubspec.lock
```
A version string like `0.6.0+eol` means the package is a **no-op shim** for a
retired mechanism. Its description on pub.dev usually names the replacement
(e.g. *"Not used anymore, update to version 3.x of package:sqlite3 instead"*).
Any `+eol` in the lock file is a strong signal the whole stack is on a
mechanism the current toolchain has moved past.

**3. Establish the debug/release split precisely.**
If `flutter run` (debug) works and the installed release build dies, it is an
AOT issue. Do not spend time on app logic, schema, config, or backend.

**4. The decisive question: is the trigger code being LINKED or EXECUTED?**

This is the test that actually cracks these. Build a minimal `lib/main.dart`
that exercises the same packages the real app does, but **does not** run any
app code. Then add the app's own code back *only as a linked reference* behind
a condition the compiler cannot fold:

```dart
Future<void> _keepAppLinked() async {
  if (Platform.environment['NEVER_TAKE_THIS_BRANCH'] != null) {
    await openDatabase();          // never executes
    runApp(const VersionGateApp());
  }
}
```

- Survives without the app linked, **aborts** with it linked → the AOT snapshot
  itself is bad, triggered by *what is compiled in*, not what runs. Stop looking
  at app behaviour entirely; the fix is in the toolchain/dependency versions.
- Aborts either way → keep bisecting the package set instead.

**5. Read the VM fatal properly.**
`hit null error with cid N` means the VM dispatched a selector on a receiver
whose class id was `N`, and that class does not implement it — usually a wrong
field read. Map `N` against the engine's `class_id.h` for the exact revision.

**Trap:** the `enum ClassId` body is macro-generated and expanding it naively
yields garbage. The real list is built from `CLASS_LIST(V)` via nested macros
(`CLASS_LIST_NO_OBJECT`, `CLASS_LIST_MAPS`, `CLASS_LIST_STRINGS`, …). Expand the
chain in order, remembering the enum starts after 4 preamble entries
(`IllegalCid`, `NativePointer`, `FreeListElement`, `ForwardingCorpse`).
Sane spot-checks: `ObjectCid = 4`, `StringCid = 94`, `OneByteStringCid = 95`,
`LinkedHashBaseCid = 97`.

## Device tooling (physical iPhone)

The device must be **unlocked** to launch anything.

```bash
# install  (NOTE: each install creates a FRESH app data container — local DB
# and queued offline writes are destroyed)
xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app

# launch, streaming stderr (this is how you see VM fatals; stdout is often not captured)
xcrun devicectl device process launch --console --device <UDID> <bundle-id>

# is it alive? (the crash signature here is dying within ~1s)
xcrun devicectl device info processes --device <UDID> | grep Runner

# screenshot / crash logs
xcrun devicectl device capture screenshot --device <UDID> --destination /tmp/s.png
xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs --destination /tmp/crash
```

Symbolicate against the matching dSYM (verify the UUID matches the installed
binary first):
```bash
dwarfdump --uuid build/ios/Release-iphoneos/App.framework.dSYM/Contents/Resources/DWARF/App
atos -arch arm64 -o <dwarf-path> -l <usedImages-base-from-ips> <addresses>
```

## Traps that wasted real time

- **You cannot reproduce AOT crashes on a simulator.** Flutter refuses:
  `Release mode is not supported for simulators.` / `Profile mode is not
  supported for simulators.` A device is the only observation path.
- **Don't A/B two variables at once.** An early wrong conclusion here came from
  changing the logger *and* the linked set together.
- **A/B the logger first if you suspect it.** `attachedLogger` was ruled out
  this way; it never crosses an isolate boundary in this stack.
- **stderr, not stdout.** `print()` is invisible in release; write probes with
  `stderr.writeln` so the device console captures them.
- **`devicectl process launch` needs the phone unlocked** — a lock error looks
  like an unrelated launch failure, not a crash.

## The fix pattern

Get onto the **current major** of the storage/sync stack rather than pinning an
old Flutter. Pinning hides the problem and leaves you on a dead mechanism. In
the 2026-09-30 incident, `powersync ^1.8.0 → ^2.4.0` (pulling `sqlite3` 3.x
via Dart build hooks) fixed it with **zero Dart source changes**.

Before proposing a migration, confirm it resolves without touching code:
```bash
flutter pub add '<pkg>:^<version>' --dry-run   # then restore pubspec.yaml
```
