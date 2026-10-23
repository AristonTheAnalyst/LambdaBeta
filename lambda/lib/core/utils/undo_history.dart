/// One undoable step (2026-10-13): [inverse] rolls the action back (DB
/// writes + in-memory restore), [replay] re-runs the forward action. Both
/// are closures over the VM, so they read live state and capture boxes at
/// run time — never frozen ids of re-created rows (every insert mints a
/// fresh uuid).
class UndoAction {
  UndoAction({required this.inverse, required this.replay});

  final Future<void> Function() inverse;
  final Future<void> Function() replay;
}

/// Mutable capture for ids minted by inserts — every forward run writes the
/// fresh id here, so an inverse deletes exactly the row the forward created
/// (never a frozen id of a row that no longer exists).
class UndoBox<T> {
  T? value;
}

/// The shared undo/redo stack: structural actions push one entry, `undo`
/// pops to the redo stack, `redo` replays. Capped — the oldest entry falls
/// off past [capacity] — and a new action clears the redo stack (the
/// standard linear-history model).
class ActionUndoHistory {
  static const int capacity = 50;

  final List<UndoAction> _undo = [];
  final List<UndoAction> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(UndoAction action) {
    _undo.add(action);
    if (_undo.length > capacity) _undo.removeAt(0);
    _redo.clear();
  }

  /// Pops the newest action and runs its inverse; the action moves to the
  /// redo stack for [redo].
  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final action = _undo.removeLast();
    await action.inverse();
    _redo.add(action);
  }

  /// Re-runs the newest undone action's forward; the action returns to the
  /// undo stack.
  Future<void> redo() async {
    if (_redo.isEmpty) return;
    final action = _redo.removeLast();
    await action.replay();
    _undo.add(action);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
