import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/utils/session_format.dart';
import '../../data/models/session_set.dart';
import '../../features/session/model/session_local_state.dart';
import 'card_pill_button.dart';
import 'exercise_selector.dart';
import 'glass_button.dart';

/// Minimal, VM-free pinned-lesson data for the card's lesson bar.
class PinnedLessonData {
  const PinnedLessonData({required this.text, required this.date});

  final String text;
  final DateTime date;
}

/// The ONE exercise card for all three workout surfaces — the live session,
/// the session planner, and the past-session viewer. Screens adapt their VM
/// state into plain inputs and nullable callbacks; a null callback renders
/// the corresponding control greyed (or hides it, where noted), so the three
/// screens share one implementation and per-context differences are
/// capability, never styling.
class SessionExerciseCard extends StatefulWidget {
  const SessionExerciseCard({
    super.key,
    // ── Exercise selector ──
    required this.exerciseNames,
    required this.activeIndex,
    required this.onSelect,
    this.onMove,
    this.onAdd,
    this.onDeleteRequest,
    // ── Pinned lesson (sits between the selector and the pills) ──
    this.pinnedLesson,
    this.onPinnedLessonTap,
    // ── Pills — a null onTap greys the pill ──
    this.lessonsCount = 0,
    this.onLessonsTap,
    this.prCount = 0,
    this.onPrTap,
    // ── Card chrome ──
    this.planned = false,
    // ── Sets grid ──
    required this.rows,
    this.onAddSet,
    // ── History view — a null list means no history: pill greyed, no
    // picker/banner ──
    this.history,
    this.historyDetailSubtitle = 'From a completed workout — tap a value to edit.',
    this.historyRowBuilder,
    this.onHistorySessionSelected,
  });

  /// Display names, in slot order.
  final List<String> exerciseNames;
  final int activeIndex;
  final void Function(int index) onSelect;

  /// Reorder: null greys the popover's arrows.
  final void Function(int index, int direction)? onMove;

  /// Null greys the popover's Add Exercise row.
  final VoidCallback? onAdd;

  /// Null hides the hold-to-delete X.
  final VoidCallback? onDeleteRequest;

  final PinnedLessonData? pinnedLesson;

  /// Null renders the lesson bar inert (no tap).
  final VoidCallback? onPinnedLessonTap;

  final int lessonsCount;
  final VoidCallback? onLessonsTap;

  final int prCount;

  /// Null greys the PRs pill (the live session's placeholder state).
  final VoidCallback? onPrTap;

  /// Planned outline on the outer card (live slot.planned / logs
  /// parentSessionId).
  final bool planned;

  /// The screen-built list of [SessionSetRow]s (keys live inside).
  final List<Widget> rows;

  /// Null hides the "+ ADD SET" button (logs view mode).
  final VoidCallback? onAddSet;

  final List<ExerciseHistorySession>? history;
  final String historyDetailSubtitle;

  /// Builds one history-detail row for [PastSetRow] (per-screen wiring —
  /// the live screen's editable-gated row vs the logs' read-only row).
  final Widget Function(PastSetRow set)? historyRowBuilder;

  /// Fired when the picker selects a session — the live screen resets its
  /// history-edit confirm gate here.
  final void Function(ExerciseHistorySession session)? onHistorySessionSelected;

  @override
  State<SessionExerciseCard> createState() => _SessionExerciseCardState();
}

class _SessionExerciseCardState extends State<SessionExerciseCard> {
  bool _historyOpen = false;
  ExerciseHistorySession? _viewingSession;

  void _exitHistory() => setState(() {
    _historyOpen = false;
    _viewingSession = null;
  });

  @override
  Widget build(BuildContext context) {
    final viewingHistory = _viewingSession != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: widget.planned
              ? AppColors.planned.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (viewingHistory) _historyBanner(_viewingSession!),
          // Top card: the exercise selector + pinned lesson + pills, inset
          // with space around it.
          Container(
            margin: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExerciseSelector(
                    exercises: widget.exerciseNames,
                    activeIndex: widget.activeIndex,
                    onSelect: widget.onSelect,
                    onMove: widget.onMove,
                    onAdd: widget.onAdd,
                    onDeleteRequest: widget.onDeleteRequest,
                  ),
                  const SizedBox(height: 6),
                  // The pinned lesson sits right under the exercise, just
                  // before the buttons — hidden while viewing history, where
                  // the banner owns the top of the card.
                  if (widget.pinnedLesson != null && !viewingHistory) ...[
                    _pinnedLessonBar(widget.pinnedLesson!),
                    const SizedBox(height: 6),
                  ],
                  // Lessons / History / PRs row — each button expands to
                  // share the available width. Null callbacks grey them.
                  Row(
                    children: [
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.menu_book_outlined,
                          label: widget.lessonsCount > 0
                              ? '${widget.lessonsCount} Lessons'
                              : 'Lessons',
                          active: widget.lessonsCount > 0,
                          enabled: widget.onLessonsTap != null,
                          onTap: widget.onLessonsTap,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.history,
                          label: 'History',
                          active: _historyOpen || viewingHistory,
                          enabled: widget.history != null &&
                              widget.history!.isNotEmpty,
                          onTap: widget.history == null ||
                                  widget.history!.isEmpty
                              ? null
                              : () {
                                  if (viewingHistory) {
                                    _exitHistory();
                                  } else {
                                    setState(
                                      () => _historyOpen = !_historyOpen,
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 6),
                      // PR = accent everywhere; null onPrTap renders the
                      // greyed placeholder state.
                      Expanded(
                        child: CardPillButton(
                          icon: Icons.emoji_events_outlined,
                          label: widget.prCount > 0
                              ? '${widget.prCount} PRs'
                              : 'PRs',
                          active: widget.prCount > 0,
                          color: AppColors.accent,
                          enabled: widget.onPrTap != null,
                          onTap: widget.onPrTap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Bottom card: the sets grid — a separate card with a gap above it.
          Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_historyOpen && !viewingHistory)
                  _historyPicker(widget.history ?? const []),
                Padding(
                  // Top spacing above the column headers (the history picker
                  // sits above when open).
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  child: viewingHistory
                      ? _historyDetail(_viewingSession!)
                      : _setsGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyBanner(ExerciseHistorySession session) {
    return Container(
      color: AppColors.surfaceHigh,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing — ${DateFormat('MMM d').format(session.date)}',
              style: AppFonts.mono(
                fontSize: 9,
                letterSpacing: 0.8,
                color: AppColors.muted,
              ),
            ),
          ),
          GlassButton(
            label: 'Back',
            color: AppColors.primary,
            compact: true,
            onPressed: _exitHistory,
          ),
        ],
      ),
    );
  }

  /// The pinned lesson bar, right under the exercise — recessed (bg fill)
  /// against the header's surfaceHigh container.
  Widget _pinnedLessonBar(PinnedLessonData lesson) {
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin, size: 10, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            'LESSON',
            style: AppFonts.mono(
              fontSize: 9,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lesson.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Text(
            DateFormat('MMM d').format(lesson.date),
            style: AppFonts.mono(fontSize: 9, color: AppColors.muted),
          ),
        ],
      ),
    );
    final onTap = widget.onPinnedLessonTap;
    if (onTap == null) return bar;
    return GestureDetector(onTap: onTap, child: bar);
  }

  Widget _historyPicker(List<ExerciseHistorySession> history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          Text(
            'PAST SESSIONS',
            style: AppFonts.mono(
              fontSize: 8,
              letterSpacing: 0.8,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final session = history[i];
                return GestureDetector(
                  onTap: () => setState(() {
                    _viewingSession = session;
                    _historyOpen = false;
                    widget.onHistorySessionSelected?.call(session);
                  }),
                  child: Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM d').format(session.date),
                          style: AppFonts.mono(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${session.sets.length} sets',
                          style: AppFonts.mono(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyDetail(ExerciseHistorySession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.historyDetailSubtitle,
          style: AppFonts.ui(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        ...session.sets.map(
          (s) => widget.historyRowBuilder?.call(s) ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _setsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 26),
              const SizedBox(width: 6),
              Expanded(child: _colLabel('REPS')),
              const SizedBox(width: 6),
              Expanded(child: _colLabel('KG')),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: _colLabel('VARIATION')),
              const SizedBox(width: 6),
              SizedBox(width: 32, child: _colLabel('NOTE')),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ...widget.rows,
        if (widget.onAddSet != null) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: widget.onAddSet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Text(
                  '+ ADD SET',
                  style: AppFonts.ui(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _colLabel(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: AppFonts.mono(
      fontSize: 8,
      letterSpacing: 0.6,
      color: AppColors.muted,
    ),
  );
}

/// One row in the history viewer's set list. [editable] false renders the
/// logs screen's read-only chrome; true renders the live screen's
/// edit-gated cells (fields stay read-only until the one-time "you're
/// editing past data" confirm flips [editConfirmed]).
class HistorySetRow extends StatefulWidget {
  const HistorySetRow({
    super.key,
    required this.set,
    this.editable = false,
    this.editConfirmed = false,
    this.onEditConfirmed,
    this.onCommit,
  });

  final PastSetRow set;
  final bool editable;
  final bool editConfirmed;
  final VoidCallback? onEditConfirmed;
  final Future<void> Function(String? weightText, String? repsText)? onCommit;

  @override
  State<HistorySetRow> createState() => _HistorySetRowState();
}

class _HistorySetRowState extends State<HistorySetRow> {
  TextEditingController? _weightCtrl;
  TextEditingController? _repsCtrl;
  FocusNode? _weightFocus;
  FocusNode? _repsFocus;

  @override
  void initState() {
    super.initState();
    if (widget.editable) {
      _seedControllers();
    }
  }

  void _seedControllers() {
    final s = widget.set;
    _weightCtrl ??= TextEditingController();
    _repsCtrl ??= TextEditingController();
    _weightFocus ??= FocusNode()
      ..addListener(() {
        if (!_weightFocus!.hasFocus) _commit();
      });
    _repsFocus ??= FocusNode()
      ..addListener(() {
        if (!_repsFocus!.hasFocus) _commit();
      });
    _weightCtrl!.text = s.weight != null ? _fmtNum(s.weight!) : '';
    _repsCtrl!.text = s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '';
  }

  @override
  void didUpdateWidget(HistorySetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching viewing sessions can reuse this element (history rows are
    // unkeyed) — re-seed so the cells never show a stale session's values.
    if (widget.editable && !identical(widget.set, oldWidget.set)) {
      _seedControllers();
    }
  }

  @override
  void dispose() {
    _weightCtrl?.dispose();
    _repsCtrl?.dispose();
    _weightFocus?.dispose();
    _repsFocus?.dispose();
    super.dispose();
  }

  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  Future<void> _commit() async {
    final weightText = _weightCtrl!.text.trim();
    final repsText = _repsCtrl!.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);
    final reps = repsText.isEmpty ? null : num.tryParse(repsText);
    final s = widget.set;
    final currentWeight = s.weight;
    final currentReps = s.reps.isNotEmpty ? s.reps.first : null;
    if (weight == currentWeight && reps == currentReps) return;
    await widget.onCommit?.call(weightText, repsText);
  }

  Future<void> _requestEdit(FocusNode focus) async {
    if (widget.editConfirmed) {
      focus.requestFocus();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Edit past data?',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Text(
          "You're about to update past data — this changes your historical record for this workout, including any PRs based on it.",
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Continue',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onEditConfirmed?.call();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.set;
    if (!widget.editable) {
      // The logs screen's read-only history chrome.
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${s.setNumber}',
                textAlign: TextAlign.center,
                style: AppFonts.mono(fontSize: 11, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                s.weight != null ? _fmtNum(s.weight!) : '—',
                textAlign: TextAlign.center,
                style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '—',
                textAlign: TextAlign.center,
                style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                s.variationName != null ? toProperCase(s.variationName!) : '—',
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The live screen's edit-gated history chrome.
    final confirmed = widget.editConfirmed;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${s.setNumber}',
              textAlign: TextAlign.center,
              style: AppFonts.mono(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(child: _editableCell(_weightCtrl!, _weightFocus!, confirmed)),
          Expanded(child: _editableCell(_repsCtrl!, _repsFocus!, confirmed)),
          Expanded(
            child: Text(
              s.variationName != null ? toProperCase(s.variationName!) : '—',
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableCell(
    TextEditingController ctrl,
    FocusNode focus,
    bool confirmed,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      readOnly: !confirmed,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
      onTap: () => _requestEdit(focus),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
