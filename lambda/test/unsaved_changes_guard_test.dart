import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/mixins/unsaved_changes_guard.dart';

/// The back door's warning (2026-10-23): **two verbs, never three**.
///
/// `UnsavedChangesGuard`'s dialog is a discard-or-stay decision — Save is the
/// screen's own button, because a warning that can write on the way out puts
/// an accidental commit one tap from a back gesture. The one exception is the
/// review settle, which has no Discard side at all: there the question really
/// is "save first?", so it reads Save and finish / Stay.
class _GuardedScreen extends StatefulWidget {
  const _GuardedScreen();

  @override
  State<_GuardedScreen> createState() => _GuardedScreenState();
}

class _GuardedScreenState extends State<_GuardedScreen>
    with UnsavedChangesGuard<_GuardedScreen> {
  bool _dirty = true;
  String _result = '';

  @override
  bool get hasUnsavedChanges => _dirty;

  @override
  Future<void> onSave() async => setState(() => _dirty = false);

  @override
  void onDiscard() => setState(() => _dirty = false);

  @override
  Widget build(BuildContext context) {
    return buildGuardedScaffold(
      scaffold: Scaffold(
        body: Column(
          children: [
            TextButton(
              onPressed: () async {
                final proceed = await confirmBack();
                if (mounted) {
                  setState(() => _result = proceed ? 'left' : 'stayed');
                }
              },
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () async {
                final proceed = await settleForReview();
                if (mounted) {
                  setState(() => _result = proceed ? 'settled' : 'stayed');
                }
              },
              child: const Text('Finish'),
            ),
            Text(_result),
          ],
        ),
      ),
    );
  }
}

void main() {
  Finder dialogVerbs() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextButton),
  );

  testWidgets('the back door offers Discard and Stay — nothing that writes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _GuardedScreen()));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved Changes'), findsOneWidget);
    expect(dialogVerbs(), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Discard'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Stay'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
      findsNothing,
      reason: 'Save is the screen\'s own button, never the warning\'s',
    );
  });

  testWidgets('Discard leaves and Stay keeps the edits on screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _GuardedScreen()));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('stayed'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('left'), findsOneWidget);
  });

  testWidgets('the review settle asks "save first?" — Save and finish / '
      'Stay, with no discard side', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _GuardedScreen()));
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(dialogVerbs(), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save and finish'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Stay'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Discard'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('stayed'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and finish'));
    await tester.pumpAndSettle();
    expect(find.text('settled'), findsOneWidget);
  });
}
