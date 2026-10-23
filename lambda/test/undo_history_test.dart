import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/undo_history.dart';

/// The shared undo/redo stack's mechanics (2026-10-13): linear history,
/// redo cleared by a new action, capped at 50 with the oldest falling off.
void main() {
  test('undo pops to redo; redo replays back to undo', () async {
    final h = ActionUndoHistory();
    final log = <String>[];
    h.push(
      UndoAction(
        inverse: () async => log.add('inverse'),
        replay: () async => log.add('replay'),
      ),
    );
    expect(h.canUndo, isTrue);
    expect(h.canRedo, isFalse);

    await h.undo();
    expect(log, ['inverse']);
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isTrue);

    await h.redo();
    expect(log, ['inverse', 'replay']);
    expect(h.canUndo, isTrue);
    expect(h.canRedo, isFalse);
  });

  test('a new action clears the redo stack', () async {
    final h = ActionUndoHistory();
    final log = <String>[];
    h.push(
      UndoAction(
        inverse: () async => log.add('inverse-1'),
        replay: () async => log.add('replay-1'),
      ),
    );
    await h.undo();

    h.push(
      UndoAction(
        inverse: () async => log.add('inverse-2'),
        replay: () async => log.add('replay-2'),
      ),
    );
    expect(
      h.canRedo,
      isFalse,
      reason: 'linear history — the undone branch is gone',
    );
    await h.undo();
    expect(log, ['inverse-1', 'inverse-2']);
  });

  test('the cap trims the oldest entry', () async {
    final h = ActionUndoHistory();
    for (var i = 0; i < ActionUndoHistory.capacity + 5; i++) {
      h.push(UndoAction(inverse: () async {}, replay: () async {}));
    }
    var undone = 0;
    while (h.canUndo) {
      await h.undo();
      undone++;
    }
    expect(
      undone,
      ActionUndoHistory.capacity,
      reason: 'only the newest capacity entries survive',
    );
  });

  test('clear empties both stacks', () async {
    final h = ActionUndoHistory();
    h.push(UndoAction(inverse: () async {}, replay: () async {}));
    await h.undo();
    h.clear();
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
  });
}
