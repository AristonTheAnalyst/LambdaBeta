import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program.dart';
import 'package:lambda/data/models/program_usage.dart';
import 'package:lambda/features/programs/viewmodel/program_library_viewmodel.dart';

/// The Programs list's sort. Today's default is last modified (descending);
/// the criterion orders the rest, while the current program stays pinned
/// first — including against the sort's direction, because "the one you are
/// running" outranks any ordering.
Program _p(String id, String name, DateTime updated) => Program(
  programId: id,
  userId: 'u1',
  name: name,
  createdDate: DateTime(2026, 1, 1),
  updatedDate: updated,
);

/// Three programs with no two orderings agreeing: Alpha is most used but not
/// newest, Bravo is newest-used but barely trained, Charlie has never been
/// used and was edited in the middle.
ProgramLibraryState _state({
  ProgramSortCriterion sort = ProgramSortCriterion.lastModified,
  bool descending = true,
  String? currentProgramId,
}) => ProgramLibraryState(
  programs: [
    _p('p-alpha', 'Alpha', DateTime(2026, 9, 1)),
    _p('p-bravo', 'Bravo', DateTime(2026, 7, 1)),
    _p('p-charlie', 'Charlie', DateTime(2026, 8, 1)),
  ],
  usage: {
    'p-alpha': ProgramUsage(lastUsed: DateTime(2026, 8, 1), sessions: 4),
    'p-bravo': ProgramUsage(lastUsed: DateTime(2026, 9, 30), sessions: 1),
  },
  currentProgramId: currentProgramId,
  sort: sort,
  sortDesc: descending,
);

List<String> _names(ProgramLibraryState s) =>
    [for (final p in s.sortedPrograms) p.name];

void main() {
  test('last modified, descending — the default', () {
    expect(_names(_state()), ['Alpha', 'Charlie', 'Bravo']);
  });

  test('last modified, ascending', () {
    expect(_names(_state(descending: false)), ['Bravo', 'Charlie', 'Alpha']);
  });

  test('A–Z in both directions', () {
    expect(_names(_state(sort: ProgramSortCriterion.name, descending: false)),
        ['Alpha', 'Bravo', 'Charlie']);
    expect(_names(_state(sort: ProgramSortCriterion.name)),
        ['Charlie', 'Bravo', 'Alpha']);
  });

  test('last used — never-used sinks in either direction', () {
    expect(
      _names(_state(sort: ProgramSortCriterion.lastUsed)),
      ['Bravo', 'Alpha', 'Charlie'],
    );
    expect(
      _names(_state(sort: ProgramSortCriterion.lastUsed, descending: false)),
      ['Alpha', 'Bravo', 'Charlie'],
      reason: 'Charlie has no last-used date — absent, not oldest',
    );
  });

  test('most used, descending', () {
    expect(_names(_state(sort: ProgramSortCriterion.mostUsed)),
        ['Alpha', 'Bravo', 'Charlie'],
        reason: '4 sessions, 1, then the never-trained 0');
  });

  test('the current program stays pinned under every sort', () {
    expect(
      _names(_state(sort: ProgramSortCriterion.name, currentProgramId: 'p-bravo')),
      ['Bravo', 'Charlie', 'Alpha'],
      reason: 'z-to-a would put Bravo last; "the program you are running" '
          'outranks the ordering',
    );
    expect(
      _names(_state(
        sort: ProgramSortCriterion.lastModified,
        descending: false,
        currentProgramId: 'p-alpha',
      )),
      ['Alpha', 'Bravo', 'Charlie'],
      reason: 'oldest-modified-first would put Alpha last — still first',
    );
  });

  test('setSort lands on the state', () {
    final vm = ProgramLibraryViewModel();
    addTearDown(vm.dispose);

    vm.setSort(ProgramSortCriterion.mostUsed, false);

    expect(vm.state.value.sort, ProgramSortCriterion.mostUsed);
    expect(vm.state.value.sortDesc, isFalse);
  });
}
