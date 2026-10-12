import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/exercise_selector.dart';

/// The mark an exercise name wears while a review is being read: a green plus
/// for one the comparison base did not hold, a red minus for one it did and
/// the side on screen does not.
///
/// The mark is the whole feature, so what is pinned here is where it lands —
/// beside the name it is about, in the field and in every popover row alike —
/// and, just as much, where it does not: no review, no marks; a list that stops
/// short leaves the names past its end bare. The ordinary selector (three
/// other screens draw it every day) is untouched by the feature's existence.
void main() {
  Future<void> pumpSelector(
    WidgetTester tester, {
    List<String> exercises = const ['Back Squat', 'Bench Press'],
    int activeIndex = 0,
    List<ExerciseMark?> marks = const [],
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExerciseSelector(
          exercises: exercises,
          activeIndex: activeIndex,
          onSelect: (_) {},
          onMove: null,
          onAdd: null,
          marks: marks,
        ),
      ),
    ),
  );

  /// The glyph drawn beside [name], read off the name's own row: the mark
  /// rides in the same [Row] as the name it belongs to (name first), so that
  /// row is what "next to the name" means. Null when the name wears nothing.
  ///
  /// With the popover open a name can be drawn twice — the field and its own
  /// row — and the field comes first, so a test that means the row asks about
  /// a name the field is not holding.
  Icon? markOf(WidgetTester tester, String name) {
    Element? row;
    tester.element(find.text(name).first).visitAncestorElements((e) {
      if (e.widget is Row) {
        row = e;
        return false;
      }
      return true;
    });
    if (row == null) return null;
    Icon? icon;
    void visit(Element e) {
      if (icon != null) return;
      if (e.widget is Icon) {
        icon = e.widget as Icon;
        return;
      }
      e.visitChildren(visit);
    }

    row!.visitChildren(visit);
    return icon;
  }

  testWidgets('with no marks, every name stays bare — the ordinary selector', (
    tester,
  ) async {
    // The live session, the planner at rest, the past-session viewer: all of
    // them draw this widget and none of them has a second reading to mark
    // against.
    await pumpSelector(tester);

    expect(markOf(tester, 'Back Squat'), isNull);
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();
    expect(markOf(tester, 'Back Squat'), isNull);
    expect(markOf(tester, 'Bench Press'), isNull);
  });

  testWidgets('the field wears the active name\'s own mark, and its colour', (
    tester,
  ) async {
    // What the reader sees without opening anything: the exercise on screen
    // says how it changed the moment the eye lands on it.
    await pumpSelector(
      tester,
      exercises: const ['Broad Jump', 'Bench Press'],
      marks: const [ExerciseMark.added, null],
    );

    final plus = markOf(tester, 'Broad Jump');
    expect(plus?.icon, ExerciseMark.added.icon);
    expect(
      plus?.color,
      AppColors.success,
      reason: 'a green plus is the one word for "this was not in the record"',
    );
  });

  testWidgets('a removed exercise wears the minus, in its own colour', (
    tester,
  ) async {
    await pumpSelector(
      tester,
      exercises: const ['Back Squat', 'Bench Press'],
      marks: const [ExerciseMark.removed, null],
    );

    final minus = markOf(tester, 'Back Squat');
    expect(minus?.icon, ExerciseMark.removed.icon);
    expect(
      minus?.color,
      AppColors.danger,
      reason: 'the minus is red wherever it is drawn — the field here, and '
          'the popover rows below, are one rule',
    );
  });

  testWidgets('an exercise both sides hold stays bare on the field', (
    tester,
  ) async {
    // The field draws the active exercise alone, and this one is unchanged
    // across the review: a mark here would claim an edit nobody made.
    await pumpSelector(
      tester,
      exercises: const ['Broad Jump', 'Bench Press'],
      activeIndex: 1,
      marks: const [ExerciseMark.added, null],
    );

    expect(markOf(tester, 'Bench Press'), isNull);
  });

  testWidgets('the popover rows wear the same marks as the field — every '
      'name, not just the open one', (tester) async {
    // The popover is the whole list, and the list is where a reader compares
    // sides: a name marked only while it is the open one would hide exactly
    // the change the reader is looking for. Both names below are ones the
    // field is NOT holding, so each match is its own row.
    await pumpSelector(
      tester,
      exercises: const ['Back Squat', 'Bench Press', 'Broad Jump'],
      activeIndex: 1,
      marks: const [ExerciseMark.removed, null, ExerciseMark.added],
    );

    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();

    expect(
      markOf(tester, 'Back Squat')?.icon,
      ExerciseMark.removed.icon,
      reason: 'the record held this one, and the side on screen does not',
    );
    expect(
      markOf(tester, 'Broad Jump')?.icon,
      ExerciseMark.added.icon,
      reason: 'the record did not hold this one, and the side on screen does',
    );
  });

  testWidgets('a list that stops short leaves the names past its end bare', (
    tester,
  ) async {
    // The callers hand marks in parallel to the names, and the field's own
    // index walks the list: a mark list built for a shorter list must not
    // borrow a glyph for a name it never described. The field holds the last
    // name — past the mark list's end — and the popover holds the rest.
    await pumpSelector(
      tester,
      exercises: const ['Back Squat', 'Bench Press', 'Overhead Press'],
      activeIndex: 2,
      marks: const [ExerciseMark.removed],
    );

    expect(markOf(tester, 'Overhead Press'), isNull, reason: 'the field');
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();
    expect(
      markOf(tester, 'Back Squat')?.icon,
      ExerciseMark.removed.icon,
      reason: 'the one name the list did describe',
    );
    expect(markOf(tester, 'Bench Press'), isNull);
  });
}
