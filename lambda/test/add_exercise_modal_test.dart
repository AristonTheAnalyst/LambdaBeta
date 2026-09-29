import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/add_exercise_modal.dart';

/// The shared add-exercise picker. It had no coverage at all until 2026-09-29 —
/// which is how it became three copy-pasted copies, and how the hold-to-delete X
/// beside it outlived everyone who knew about it.
///
/// The harness opens the sheet from a button, the way a screen does: the picker
/// is a route (`showLambdaModal`), so it needs a real context under a Navigator.
Future<void> pumpPicker(
  WidgetTester tester, {
  required Listenable listenable,
  required List<AddExerciseEntry> Function() entries,
  required bool Function(String exerciseId) isAdded,
  Future<void> Function(String exerciseId)? onAdd,
  Future<void> Function(String exerciseId)? onRemoveRequest,
  Future<String?> Function(String name)? onCreate,
  bool Function()? isCreating,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAddExerciseModal(
                context,
                listenable: listenable,
                entries: entries,
                isAdded: isAdded,
                onAdd: onAdd,
                onRemoveRequest: onRemoveRequest,
                onCreate: onCreate,
                isCreating: isCreating,
              ),
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

/// Three exercises, deliberately out of order: one trained recently, one never
/// trained, and one whose name sorts first among the never-trained. Ordering is
/// recency first, then name — nothing here is pre-sorted, so the picker has to
/// do the work.
final _library = [
  const AddExerciseEntry(exerciseId: 'ex-squat', name: 'Squat'),
  const AddExerciseEntry(exerciseId: 'ex-bench', name: 'Bench Press'),
  AddExerciseEntry(
    exerciseId: 'ex-deadlift',
    name: 'Deadlift',
    lastUsed: DateTime(2026, 9, 20),
  ),
];

/// The one search field, which doubles as the new name.
Finder get _searchField => find.byType(TextField);

void main() {
  testWidgets('orders by recency, then by name', (tester) async {
    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: (_) => false,
    );

    double y(String label) => tester.getTopLeft(find.text(label)).dy;

    expect(y('Deadlift'), lessThan(y('Bench Press')),
        reason: 'a trained exercise outranks a never-trained one');
    expect(y('Bench Press'), lessThan(y('Squat')),
        reason: 'among the never-trained, the name decides');
  });

  testWidgets('typing filters to matching names', (tester) async {
    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: (_) => false,
    );

    await tester.enterText(_searchField, 'dead');
    await tester.pumpAndSettle();

    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('tapping an unadded row adds it and leaves the sheet open',
      (tester) async {
    final added = <String>{};
    final notifier = ValueNotifier(0);
    final calls = <String>[];

    await pumpPicker(
      tester,
      listenable: notifier,
      entries: () => _library,
      isAdded: added.contains,
      onAdd: (id) async {
        calls.add('add:$id');
        added.add(id);
        // What a screen does: mutate, then wake the sheet.
        notifier.value++;
      },
    );

    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    expect(calls, ['add:ex-squat']);
    expect(find.text('Added'), findsOneWidget,
        reason: 'the row reports the new state without being reopened');
    expect(_searchField, findsOneWidget,
        reason: 'the sheet is still up — that is the whole point of the '
            'widget, and the reason building a session used to be one visit '
            'per exercise');
  });

  testWidgets('tapping a ticked row asks to remove it, and never to add it',
      (tester) async {
    final added = {'ex-squat'};
    final calls = <String>[];

    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: added.contains,
      onAdd: (id) async => calls.add('add:$id'),
      onRemoveRequest: (id) async => calls.add('remove:$id'),
    );

    expect(find.text('Added'), findsOneWidget);

    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    expect(calls, ['remove:ex-squat'],
        reason: 'a tick is a control, not a label — but it asks, because the '
            'screen owns the confirmation dialog and the data');
    expect(added, {'ex-squat'},
        reason: 'the picker never removes anything itself');
  });

  testWidgets('a null onRemoveRequest makes the tick informational',
      (tester) async {
    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: (id) => id == 'ex-squat',
      onAdd: (_) async {},
    );

    expect(find.text('Added'), findsOneWidget);

    // Read-only contexts (a program version, the logs viewer) still show which
    // exercises are in play; there is simply nothing to tap.
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    expect(find.text('Added'), findsOneWidget);
  });

  testWidgets('a null onAdd leaves unadded rows inert', (tester) async {
    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: (_) => false,
      onRemoveRequest: (_) async {},
    );

    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    expect(find.text('Added'), findsNothing);
  });

  group('the create row', () {
    testWidgets('appears only past one character', (tester) async {
      await pumpPicker(
        tester,
        listenable: ValueNotifier(0),
        entries: () => _library,
        isAdded: (_) => false,
        onCreate: (_) async => null,
      );

      await tester.enterText(_searchField, 'z');
      await tester.pumpAndSettle();
      expect(find.text('+ Create "z"'), findsNothing,
          reason: 'a single letter is a search, not a name');

      await tester.enterText(_searchField, 'ze');
      await tester.pumpAndSettle();
      expect(find.text('+ Create "ze"'), findsOneWidget);
    });

    testWidgets('not offered for a name the library already has',
        (tester) async {
      await pumpPicker(
        tester,
        listenable: ValueNotifier(0),
        entries: () => _library,
        isAdded: (_) => false,
        onCreate: (_) async => null,
      );

      // Case-insensitively: the user is looking at the exercise they were
      // about to create.
      await tester.enterText(_searchField, 'squat');
      await tester.pumpAndSettle();

      expect(find.text('+ Create "squat"'), findsNothing);
      expect(find.text('Squat'), findsOneWidget);
    });

    testWidgets('hidden when the caller has no create capability',
        (tester) async {
      await pumpPicker(
        tester,
        listenable: ValueNotifier(0),
        entries: () => _library,
        isAdded: (_) => false,
      );

      await tester.enterText(_searchField, 'Zercher');
      await tester.pumpAndSettle();

      expect(find.text('+ Create "Zercher"'), findsNothing);
    });

    testWidgets('creates, adds, clears the query, and ticks the new row',
        (tester) async {
      final added = <String>{};
      final notifier = ValueNotifier(0);
      final entries = [..._library];
      final calls = <String>[];

      await pumpPicker(
        tester,
        listenable: notifier,
        entries: () => entries,
        isAdded: added.contains,
        onCreate: (name) async {
          calls.add('create:$name');
          entries.add(AddExerciseEntry(exerciseId: 'ex-zercher', name: name));
          notifier.value++;
          return 'ex-zercher';
        },
        onAdd: (id) async {
          calls.add('add:$id');
          added.add(id);
          notifier.value++;
        },
      );

      await tester.enterText(_searchField, 'Zercher');
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Create "Zercher"'));
      await tester.pumpAndSettle();

      expect(calls, ['create:Zercher', 'add:ex-zercher'],
          reason: 'creating and adding are one tap for the user — they never '
              'asked for an exercise that is not in the session');
      expect(tester.widget<TextField>(_searchField).controller!.text, isEmpty,
          reason: 'a cleared query is what makes the new row reachable — it '
              'no longer matches the filter that created it');
      expect(find.text('Added'), findsOneWidget);
    });

    testWidgets('stays visible but inert while a create is in flight',
        (tester) async {
      final calls = <String>[];

      await pumpPicker(
        tester,
        listenable: ValueNotifier(0),
        entries: () => _library,
        isAdded: (_) => false,
        onCreate: (name) async {
          calls.add(name);
          return null;
        },
        isCreating: () => true,
      );

      await tester.enterText(_searchField, 'Zercher');
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ Create "Zercher"'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty,
          reason: 'a row that vanished under the finger would read as a '
              'mis-tap, so it greys instead of disappearing');
    });
  });

  testWidgets('the search field stops at twenty characters and counts them',
      (tester) async {
    await pumpPicker(
      tester,
      listenable: ValueNotifier(0),
      entries: () => _library,
      isAdded: (_) => false,
      onCreate: (_) async => null,
    );

    await tester.enterText(_searchField, 'a' * 25);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(_searchField).controller!.text.length,
      20,
      reason: 'the text *is* the new name when the create row is used, so the '
          'field carries the same cap the database does',
    );
    expect(find.text('20/20'), findsOneWidget,
        reason: 'the field silently refusing the twenty-first character reads '
            'as a broken keyboard without this');
  });
}
