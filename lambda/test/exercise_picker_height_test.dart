import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/add_exercise_modal.dart';
import 'package:lambda/shared/widgets/exercise_selector.dart';

/// Both exercise pickers cap their list at ONE shared height (2026-10-26): half
/// the screen, where the fixed 260 they each carried showed about five rows.
/// The selector's popover and the Add/Remove Exercises sheet are the one picker
/// in two shapes, so this pins that they read the same cap — and that neither
/// one overflows when the space shrinks: a field low on the screen, or the
/// keyboard the sheet's own search field raises.
void main() {
  const phone = Size(402, 874);

  /// Gives the test the phone-sized surface the cap is computed against.
  /// Physical size with a 1.0 ratio, so logical == physical.
  void sizeScreen(WidgetTester tester, [Size size = phone]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A library long enough that its list always wants more than the cap.
  List<AddExerciseEntry> library([int n = 20]) => [
    for (var i = 0; i < n; i++)
      AddExerciseEntry(exerciseId: 'e$i', name: 'Exercise $i'),
  ];

  /// Pumps the selector with its field at [top]; null puts it where the
  /// layout happens to put it (the top of the body).
  Future<void> pumpSelector(WidgetTester tester, {double? top}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.only(top: top ?? 0),
              child: ExerciseSelector(
                exercises: [for (var i = 0; i < 20; i++) 'Exercise $i'],
                activeIndex: 0,
                onSelect: (_) {},
                onMove: (_, _) {},
                onAdd: () {},
              ),
            ),
          ),
        ),
      );

  /// The popover's own box — the capped container under the field.
  Size popoverSize(WidgetTester tester) => tester.getSize(
    find.byKey(const ValueKey('exercise-selector-popover')),
  );

  /// Opens the add sheet from a button, the way a screen does.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAddExerciseModal(
                  context,
                  listenable: ValueNotifier(0),
                  entries: library,
                  isAdded: (_) => false,
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

  Size sheetListSize(WidgetTester tester) =>
      tester.getSize(find.byType(ListView));

  testWidgets('the one cap is half the screen, with the old 260 as its floor', (
    tester,
  ) async {
    sizeScreen(tester);

    late double portrait;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            portrait = exercisePickerListCap(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      portrait,
      437,
      reason: 'a phone in portrait doubles the old 260 — about twice the rows',
    );

    // The app allows landscape, where half the height would be 201: the
    // picker keeps the old cap rather than shrinking below what it always
    // showed.
    sizeScreen(tester, const Size(874, 402));
    late double landscape;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            landscape = exercisePickerListCap(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(landscape, 260);
  });

  testWidgets('the popover grows to the cap — twice the rows of the old 260', (
    tester,
  ) async {
    sizeScreen(tester);
    await pumpSelector(tester);
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();

    final size = popoverSize(tester);
    expect(
      size.height,
      moreOrLessEquals(437),
      reason:
          'twenty exercises want more than the cap, so the popover shows '
          'exactly it — half the screen, where it used to stop at 260',
    );
    expect(
      size.height,
      greaterThan(260),
      reason: 'the old fixed cap is what this exists to leave behind',
    );
  });

  testWidgets('a popover under a low field takes the room it actually has', (
    tester,
  ) async {
    sizeScreen(tester);
    // The field's bottom lands at 490 on the 874-tall screen, leaving 372
    // between it and the bottom edge — less than the cap.
    await pumpSelector(tester, top: 450);
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();

    expect(
      popoverSize(tester).height,
      moreOrLessEquals(372),
      reason:
          'the taller cap must not push the popover off the screen — it is '
          'narrowed to the space below the field',
    );
  });

  testWidgets('the add sheet list takes the same cap', (tester) async {
    sizeScreen(tester);
    await openSheet(tester);

    final size = sheetListSize(tester);
    expect(
      size.height,
      moreOrLessEquals(437),
      reason:
          'the same value the popover reads — the one picker in two shapes '
          'must not drift apart',
    );
  });

  testWidgets('the add sheet list gives way to the keyboard without '
      'overflowing', (tester) async {
    sizeScreen(tester);
    await openSheet(tester);

    // The search field raises the keyboard as the sheet opens; 336 is its
    // height on the phone this was walked on.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the sheet, its chrome and the keyboard must fit the screen — '
          'the list shrinks into the space left instead of overflowing',
    );
    final height = sheetListSize(tester).height;
    expect(height, greaterThan(0));
    expect(
      height,
      lessThan(437),
      reason: 'half a screen is the cap, not a promise the screen can honour',
    );
  });
}
