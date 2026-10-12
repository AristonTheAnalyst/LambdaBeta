import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program.dart';

/// A program's shape, as it survives a trip through the database.
///
/// `uses_blocks` is the one field the whole tab layout, the begin sheet and the
/// goal scoping are read from, and it arrives through a sync window that can
/// hand over a row written before the column existed. What that row reads as is
/// therefore part of the feature, not a decoding detail — which is why the null
/// case is asserted here rather than left to the column's default.
void main() {
  Program program({bool usesBlocks = false, int? defaultTargetSessions}) =>
      Program(
        programId: 'p1',
        userId: 'u1',
        name: 'Base',
        description: 'Eight weeks',
        createdDate: DateTime(2026, 1, 1),
        updatedDate: DateTime(2026, 2, 2),
        usesBlocks: usesBlocks,
        defaultTargetSessions: defaultTargetSessions,
      );

  test('a blocked program round-trips as blocked', () {
    final back = Program.fromMap(program(usesBlocks: true).toMap());

    expect(back.usesBlocks, isTrue);
    expect(back.name, 'Base');
    expect(back.description, 'Eight weeks');
    expect(back.createdDate, DateTime(2026, 1, 1));
    expect(back.updatedDate, DateTime(2026, 2, 2));
    expect(back.archivedDate, isNull);
  });

  test('a simple program round-trips as simple', () {
    expect(Program.fromMap(program().toMap()).usesBlocks, isFalse);
  });

  test('a row that predates the column reads as simple, not blocked', () {
    final map = program(usesBlocks: true).toMap()..remove('uses_blocks');

    expect(
      Program.fromMap(map).usesBlocks,
      isFalse,
      reason: 'the local mirror holds a row written before `uses_blocks` '
          'existed, and it reads NULL until a download lands. The two wrong '
          'answers are not equal: a temporary "simple" costs a missing Blocks '
          'tab, while a temporary "blocked" would put block surfacing on every '
          'program in the app',
    );
  });

  test('a null length is a length nobody has set, not a zero', () {
    final map = program().toMap();
    expect(map['default_target_sessions'], isNull);

    expect(
      Program.fromMap(map).defaultTargetSessions,
      isNull,
      reason: 'the begin sheet prefills from this. A null that came back as 0 '
          'would open every first run on "0 sessions" — a number the program '
          'never remembered and the user never chose',
    );
  });

  test('a remembered length round-trips', () {
    expect(
      Program.fromMap(program(defaultTargetSessions: 12).toMap())
          .defaultTargetSessions,
      12,
    );
  });

  test('the length survives the string the database hands back', () {
    // Synced rows do not all arrive as ints — a real read path has produced
    // both a num and a string for the same column.
    final map = program(defaultTargetSessions: 12).toMap();

    expect(Program.fromMap({...map, 'default_target_sessions': '12'})
        .defaultTargetSessions, 12);
    expect(Program.fromMap({...map, 'default_target_sessions': 12.0})
        .defaultTargetSessions, 12);
  });

  test('the shape survives the string and int forms too', () {
    final map = program().toMap();

    expect(Program.fromMap({...map, 'uses_blocks': 1}).usesBlocks, isTrue);
    expect(Program.fromMap({...map, 'uses_blocks': true}).usesBlocks, isTrue);
    expect(Program.fromMap({...map, 'uses_blocks': 0}).usesBlocks, isFalse);
  });

  test('an archived program keeps the date it was archived on', () {
    final archived = Program(
      programId: 'p1',
      userId: 'u1',
      name: 'Base',
      createdDate: DateTime(2026, 1, 1),
      updatedDate: DateTime(2026, 1, 1),
      archivedDate: DateTime(2026, 3, 3),
    );

    expect(Program.fromMap(archived.toMap()).isArchived, isTrue);
  });

  test('a missing updated date falls back to the created one', () {
    final map = program().toMap()..remove('program_updated_date');

    expect(Program.fromMap(map).updatedDate, Program.fromMap(map).createdDate,
        reason: 'every program is at least as old as it is: a row without an '
            'update stamp is one that has never been edited');
  });
}
