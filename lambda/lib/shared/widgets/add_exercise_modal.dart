import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/utils/name_limit.dart';
import '../../features/session/model/session_local_state.dart';
import './container_styles.dart';
import './name_limit_counter.dart';
import './slide_up_modal.dart';

/// One row of the picker: the exercise, the label to draw, and when it was last
/// trained.
///
/// The caller builds these — the picker only filters and sorts them. `name` is
/// whatever the caller wants drawn (they apply `toProperCase`), and `lastUsed`
/// drives the ordering: most recently trained first, never-trained last.
class AddExerciseEntry {
  const AddExerciseEntry({
    required this.exerciseId,
    required this.name,
    this.lastUsed,
  });

  final String exerciseId;
  final String name;

  /// Null = never trained, which sorts below every dated entry.
  final DateTime? lastUsed;
}

/// The "most recently used" date for [exerciseId], or null if it has no history.
///
/// `groupHistoryByExercise` sorts newest-first, so `first` is the newest
/// session — this is the one spelling of that fact, shared by the two screens
/// that read it off a history map (the planner and the past-session viewer).
DateTime? lastUsedFromHistory(
  Map<String, List<ExerciseHistorySession>> history,
  String exerciseId,
) {
  final sessions = history[exerciseId];
  return (sessions == null || sessions.isEmpty) ? null : sessions.first.date;
}

/// The exercise picker: search the library, tap to add, tap again to remove.
///
/// Opens as a modal sheet that **stays open** across every action — adding an
/// exercise ticks it and leaves the sheet up, so building a session is one
/// visit rather than one visit per exercise. Removal lives here too: a tap on a
/// ticked row asks the caller to remove it (the caller owns the confirmation
/// dialog and the data), which is what replaced the old hold-to-delete X on the
/// selector field.
///
/// The caller supplies **closures**, not snapshots: [entries] and [isAdded] are
/// re-read inside a `ListenableBuilder` on [listenable], so the list grows and
/// the ticks appear as the user works. A snapshot taken at open time would
/// leave a newly added exercise invisible until the sheet was reopened.
///
/// Null callbacks mean the capability is absent, never styled differently:
/// [onAdd] null leaves unticked rows inert and muted, [onRemoveRequest] null
/// leaves a tick as information rather than a control, and [onCreate] null
/// hides the create row.
void showAddExerciseModal(
  BuildContext context, {
  required Listenable listenable,
  required List<AddExerciseEntry> Function() entries,
  required bool Function(String exerciseId) isAdded,
  Future<void> Function(String exerciseId)? onAdd,
  Future<void> Function(String exerciseId)? onRemoveRequest,
  Future<String?> Function(String name)? onCreate,
  bool Function()? isCreating,
  String title = 'Add exercise',
}) {
  showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _AddExerciseModalContent(
      listenable: listenable,
      entries: entries,
      isAdded: isAdded,
      onAdd: onAdd,
      onRemoveRequest: onRemoveRequest,
      onCreate: onCreate,
      isCreating: isCreating,
      title: title,
    ),
  );
}

class _AddExerciseModalContent extends StatefulWidget {
  const _AddExerciseModalContent({
    required this.listenable,
    required this.entries,
    required this.isAdded,
    required this.title,
    this.onAdd,
    this.onRemoveRequest,
    this.onCreate,
    this.isCreating,
  });

  final Listenable listenable;
  final List<AddExerciseEntry> Function() entries;
  final bool Function(String exerciseId) isAdded;
  final Future<void> Function(String exerciseId)? onAdd;
  final Future<void> Function(String exerciseId)? onRemoveRequest;
  final Future<String?> Function(String name)? onCreate;
  final bool Function()? isCreating;
  final String title;

  @override
  State<_AddExerciseModalContent> createState() =>
      _AddExerciseModalContentState();
}

class _AddExerciseModalContentState extends State<_AddExerciseModalContent> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// One key per exercise, so a freshly created one can be scrolled to. It
  /// sorts into the never-trained group, which can sit below the fold.
  final _rowKeys = <String, GlobalKey>{};

  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _rowKey(String exerciseId) =>
      _rowKeys.putIfAbsent(exerciseId, () => GlobalKey());

  /// Name-ordered matches for the current query, most recently used first
  /// (never-used last), then alphabetically.
  List<AddExerciseEntry> get _filtered {
    final q = _query.toLowerCase();
    final matches =
        widget.entries().where((e) => e.name.toLowerCase().contains(q)).toList();
    matches.sort((a, b) {
      final da = a.lastUsed;
      final db = b.lastUsed;
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return matches;
  }

  /// The create row is offered only for a name that is actually new. Two
  /// characters is the floor — a single letter matches enough of the library to
  /// be a search, not a name — and an exact case-insensitive match means the
  /// user is looking at the exercise they were about to create.
  bool get _canCreate =>
      widget.onCreate != null &&
      _query.trim().length > 1 &&
      !widget.entries().any(
        (e) => e.name.toLowerCase() == _query.trim().toLowerCase(),
      );

  /// Whether the typed text is long enough to be a name in progress — what the
  /// counter needs to know before it is worth showing.
  bool get _isNaming => _query.trim().length > 1;

  /// Create the typed name, then add it. The query is cleared so the new row is
  /// visible; it is then scrolled to, because a brand-new exercise has no
  /// history and sorts into the never-trained group.
  Future<void> _create() async {
    final id = await widget.onCreate!(_query.trim());
    if (id == null || !mounted) return;
    _searchController.clear();
    setState(() => _query = '');
    await widget.onAdd?.call(id);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _searchController,
              autofocus: true,
              // The text *is* the new name when the create row is used, so the
              // field carries the same cap the database does. (Material's own
              // counter is suppressed — it is not the app's type.)
              maxLength: kMaxExerciseNameLength,
              style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Search exercises…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            if (_isNaming) ...[
              const SizedBox(height: 4),
              NameLimitCounter(length: _query.trim().length),
            ],
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListenableBuilder(
                listenable: widget.listenable,
                builder: (context, _) => ListView(
                  controller: _scrollController,
                  shrinkWrap: true,
                  children: [
                    ..._filtered.map((e) {
                      final added = widget.isAdded(e.exerciseId);
                      return _resultRow(
                        key: _rowKey(e.exerciseId),
                        label: e.name,
                        onTap: _tapFor(e, added: added),
                        added: added,
                      );
                    }),
                    if (_canCreate)
                      _resultRow(
                        label: '+ Create "${_query.trim()}"',
                        // Visible but inert while a create is in flight — a row
                        // that vanished under the finger would read as a
                        // mis-tap.
                        onTap: (widget.isCreating?.call() ?? false) ? null : _create,
                        accent: true,
                      ),
                    if (_filtered.isEmpty && !_canCreate && _query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: Text(
                            'No exercises found',
                            style: AppFonts.ui(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What a tap on a row does — or null when the caller offers nothing for that
  /// direction. An added row asks to remove (only if [onRemoveRequest] exists);
  /// an unadded one asks to add (only if [onAdd] does).
  VoidCallback? _tapFor(AddExerciseEntry entry, {required bool added}) {
    if (added) {
      final remove = widget.onRemoveRequest;
      return remove == null ? null : () => remove(entry.exerciseId);
    }
    final add = widget.onAdd;
    return add == null ? null : () => add(entry.exerciseId);
  }

  Widget _resultRow({
    required String label,
    required VoidCallback? onTap,
    Key? key,
    bool accent = false,
    bool added = false,
  }) {
    final enabled = onTap != null;
    final color = accent
        ? AppColors.accent
        : (enabled ? AppColors.primary : AppColors.muted);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          // Pressable rows — the glass recipe in their semantic color.
          decoration: glassBox(accent ? AppColors.accent : AppColors.primary),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  // A `+ Create "<20-char name>"` label is well past the sheet's
                  // width; without this it overflows rather than shortening.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: 14,
                    fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (added) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 14, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  'Added',
                  style: AppFonts.mono(
                    fontSize: 13,
                    letterSpacing: 0.4,
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
