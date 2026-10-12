import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/programs/view/run_finished_sheet.dart';

/// The question a reviewed run asks once the plan has been looked at.
///
/// The sheet's whole contract is that its three answers come back as three
/// different values, never merged: the caller branches on them (carry on is a
/// no-write acknowledgement, the other two reopen a flow), and a null — the
/// dismiss — must stay distinguishable from "carry on", because neither writes
/// anything but only one of them is an answer.
void main() {
  late RunFinishedAnswer? result;

  Future<void> openSheet(
    WidgetTester tester, {
    String lengthLabel = '8 weeks',
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showRunFinishedSheet(
                    context,
                    lengthLabel: lengthLabel,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('states the question, the length, and all three answers', (
    tester,
  ) async {
    await openSheet(tester, lengthLabel: '8 weeks 3 days');

    expect(find.text('The run has reached its length'), findsOneWidget);
    // The caller phrases the length — it owns the block/program distinction —
    // so the sheet renders what it was handed, verbatim.
    expect(find.text('PLANNED · 8 weeks 3 days'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Change length'), findsOneWidget);
    expect(find.text('End run'), findsOneWidget);
  });

  testWidgets('carry on answers as itself', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, RunFinishedAnswer.continueRun);
  });

  testWidgets('change length answers as itself', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Change length'));
    await tester.pumpAndSettle();
    expect(result, RunFinishedAnswer.changeLength);
  });

  testWidgets('end run answers as itself', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('End run'));
    await tester.pumpAndSettle();
    expect(result, RunFinishedAnswer.endRun);
  });

  testWidgets('dismissing returns null — no answer yet, nothing changes', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
