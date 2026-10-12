import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/sort_button.dart';

/// The shared sort control behind every library list's toolbar. It is generic
/// on purpose — the lists own their criteria — so the test drives it with
/// plain strings rather than any feature's enum.
///
/// The menu's contract (2026-10-10): it opens on the criterion in force with
/// its direction arrowed, a fresh pick lands in the criterion's natural
/// direction, re-tapping the criterion in force flips it, every pick closes
/// the menu, and a tap outside closes it answering nothing.
Future<List<(String, bool)>> _open(
  WidgetTester tester, {
  String value = 'name',
  bool descending = false,
}) async {
  final calls = <(String, bool)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SortButton<String>(
            options: const [
              SortOption(label: 'A–Z', value: 'name'),
              SortOption(
                label: 'Last used',
                value: 'last',
                naturalDescending: true,
              ),
            ],
            value: value,
            descending: descending,
            onChanged: (v, d) => calls.add((v, d)),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.sort));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('opens on the criterion in force, its direction arrowed', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('A–Z'), findsOneWidget);
    expect(find.text('Last used'), findsOneWidget);
    // The active row wears the direction arrow in place of the tick — the
    // sheet and its Ascending/Descending switch are gone, not hidden.
    expect(
      find.byIcon(Icons.arrow_upward),
      findsOneWidget,
      reason: '"A–Z" is active and reads ascending',
    );
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('Sort by'), findsNothing);
    expect(find.text('Ascending'), findsNothing);
  });

  testWidgets('picking a criterion lands in its natural direction, and the '
      'menu closes', (tester) async {
    final calls = await _open(tester);

    await tester.tap(find.text('Last used'));
    await tester.pumpAndSettle();

    expect(calls, [('last', true)], reason:
        '"Last used" reads newest-first — picking it must not land in its '
        'upside-down reading');
    expect(
      find.text('A–Z'),
      findsNothing,
      reason: 'one question, one answer — the menu closes on the pick',
    );
  });

  testWidgets('re-tapping the criterion in force flips its direction', (
    tester,
  ) async {
    final calls = await _open(tester, value: 'last', descending: true);

    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    await tester.tap(find.text('Last used'));
    await tester.pumpAndSettle();

    expect(calls, [('last', false)],
        reason: 'the criterion is untouched — only the direction flips');
    expect(find.text('A–Z'), findsNothing, reason: 'the pick closed it');
  });

  testWidgets('a tap outside puts the menu away and answers nothing', (
    tester,
  ) async {
    final calls = await _open(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('A–Z'), findsNothing);
    expect(calls, isEmpty);
  });
}
