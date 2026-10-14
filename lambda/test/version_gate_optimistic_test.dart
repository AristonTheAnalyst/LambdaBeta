import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/version_check/version_check_service.dart';
import 'package:lambda/data/models/app_config.dart';
import 'package:lambda/data/repositories/app_config_repository.dart';
import 'package:lambda/core/version_check/version_check_store.dart';
import 'package:lambda/features/update/view/update_required_screen.dart';
import 'package:lambda/version_gate_app.dart';

/// The cached-first version gate (2026-10-13): the first frame reads the
/// persisted last result, never the network. A cached `updateRequired`
/// blocks immediately and self-heals when the live check clears it;
/// anything else renders the app optimistically and swaps to the update
/// screen only on a live `required`.
class _FakeStore extends VersionCheckStore {
  VersionCheckResult? cached;

  @override
  Future<VersionCheckResult?> read() async => cached;

  @override
  Future<void> write(VersionCheckResult result) async {
    cached = result;
  }
}

/// No Supabase construction — the fake repo short-circuits the check.
class _FakeConfigRepo implements AppConfigRepository {
  @override
  Future<AppConfig?> fetchForPlatform(String platform) async => null;
}

class _FakeService extends VersionCheckService {
  _FakeService({VersionCheckResult? result})
    : completer = null,
      super(repo: _FakeConfigRepo()) {
    _result = result;
  }

  _FakeService.pending(this.completer) : super(repo: _FakeConfigRepo());

  VersionCheckResult? _result;
  final Completer<VersionCheckResult>? completer;

  @override
  Future<VersionCheckResult> check() async {
    final c = completer;
    if (c != null) return c.future;
    return _result ?? const VersionCheckResult(status: VersionCheckStatus.unknown);
  }
}

void main() {
  Widget gate({
    required VersionCheckService service,
    required VersionCheckStore store,
    required void Function(bool nudge) onApp,
  }) => MaterialApp(
    home: VersionGateApp(
      checkService: service,
      store: store,
      appBuilder: (nudge) {
        onApp(nudge);
        return Text('app:$nudge');
      },
    ),
  );

  testWidgets('no cache and a pending check render the app optimistically', (
    tester,
  ) async {
    bool? nudge;
    final completer = Completer<VersionCheckResult>();
    await tester.pumpWidget(gate(
      service: _FakeService.pending(completer),
      store: _FakeStore(),
      onApp: (n) => nudge = n,
    ));
    await tester.pump();

    expect(find.text('app:false'), findsOneWidget,
        reason: 'the first frame is the app, not a network spinner');
    expect(nudge, isFalse);

    // Settle the check so its timeout timer doesn't outlive the test.
    completer.complete(
      const VersionCheckResult(status: VersionCheckStatus.unknown),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a cached required blocks immediately', (tester) async {
    final completer = Completer<VersionCheckResult>();
    await tester.pumpWidget(gate(
      service: _FakeService.pending(completer),
      store: _FakeStore()
        ..cached = const VersionCheckResult(
          status: VersionCheckStatus.updateRequired,
        ),
      onApp: (_) {},
    ));
    await tester.pump();

    expect(find.byType(UpdateRequiredScreen), findsOneWidget,
        reason: 'the persisted answer gates the first frame — no network');

    completer.complete(
      const VersionCheckResult(status: VersionCheckStatus.unknown),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a live required swaps the optimistic app to the update screen', (
    tester,
  ) async {
    final completer = Completer<VersionCheckResult>();
    await tester.pumpWidget(gate(
      service: _FakeService.pending(completer),
      store: _FakeStore(),
      onApp: (_) {},
    ));
    await tester.pump();
    expect(find.byType(UpdateRequiredScreen), findsNothing);

    completer.complete(
      const VersionCheckResult(status: VersionCheckStatus.updateRequired),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
  });

  testWidgets('a cached required self-heals when the live check clears', (
    tester,
  ) async {
    await tester.pumpWidget(gate(
      service: _FakeService(
        result: const VersionCheckResult(status: VersionCheckStatus.upToDate),
      ),
      store: _FakeStore()
        ..cached = const VersionCheckResult(
          status: VersionCheckStatus.updateRequired,
        ),
      onApp: (_) {},
    ));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateRequiredScreen), findsNothing,
        reason: 'a post-update false-block must clear in one check round');
    expect(find.text('app:false'), findsOneWidget);
  });

  testWidgets('a recommended answer passes through as the nudge flag', (
    tester,
  ) async {
    bool? nudge;
    await tester.pumpWidget(gate(
      service: _FakeService(
        result: const VersionCheckResult(
          status: VersionCheckStatus.updateRecommended,
        ),
      ),
      store: _FakeStore(),
      onApp: (n) => nudge = n,
    ));
    await tester.pumpAndSettle();

    expect(nudge, isTrue);
    expect(find.text('app:true'), findsOneWidget);
  });
}
