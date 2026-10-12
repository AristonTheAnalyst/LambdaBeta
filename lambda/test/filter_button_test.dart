import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/filter_button.dart';

/// The shared filter control — the sort control's sibling. Its contract
/// (2026-10-10): the menu opens on the narrowing in force ticked, a pick
/// applies and closes it, and re-picking the narrowing in force closes
/// without answering — the same question, the same answer, nothing written.
Future<List<String>> _open(WidgetTester tester, {String value = 'all'}) async {
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FilterButton<String>(
            options: const [
              FilterOption(label: 'All', value: 'all'),
              FilterOption(label: 'In this review', value: 'in'),
              FilterOption(label: 'Not in this review', value: 'out'),
            ],
            value: value,
            active: value != 'all',
            onChanged: calls.add,
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('opens on the narrowing in force, ticked', (tester) async {
    await _open(tester, value: 'in');

    expect(find.text('All'), findsOneWidget);
    expect(find.text('In this review'), findsOneWidget);
    expect(find.text('Not in this review'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'the narrowing in force is the one ticked');
  });

  testWidgets('a pick applies and closes', (tester) async {
    final calls = await _open(tester);

    await tester.tap(find.text('Not in this review'));
    await tester.pumpAndSettle();

    expect(calls, ['out']);
    expect(
      find.text('All'),
      findsNothing,
      reason: 'one question, one answer — the menu closes on the pick',
    );
  });

  testWidgets('re-picking the narrowing in force closes without answering', (
    tester,
  ) async {
    final calls = await _open(tester, value: 'in');

    await tester.tap(find.text('In this review'));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.text('All'), findsNothing, reason: 'the menu still closed');
  });
}
