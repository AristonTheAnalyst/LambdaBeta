import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../data/models/exercise_usage.dart';
import '../../../../data/models/session.dart';
import '../../../../data/models/session_exercise_set.dart';
import '../../../../shared/widgets/confirm_delete_session_dialog.dart';
import '../../../../shared/widgets/logs_filter_bar.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../../core/utils/date_range.dart';
import '../../../../shared/widgets/date_range_selector.dart';
import '../../../../shared/widgets/header_icon_button.dart';
import '../../../../shared/widgets/session_log_card.dart';
import '../../../../shared/router/app_router.dart';
import '../viewmodel/logs_viewmodel.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    this.showHeader = true,
    this.onSessionDeleted,
    this.userId,
    this.readOnly = false,
    this.headerTitle = 'Training Logs',
    this.onBack,
    this.emptyMessage,
    this.emptyHint,
    this.sessionRouteBuilder,
    this.onOpenSession,
    this.canDelete = true,
  });

  /// Whether the header renders — false when the screen is embedded (the
  /// prep page's PREVIOUS SESSIONS section) so the host provides its own
  /// label.
  final bool showHeader;

  /// Called with the deleted session's id after its card's swipe-delete
  /// lands — the embedded host reloads the state that outlives the list
  /// (the session VM's reflection card and PR timeline). Null in the
  /// Training Logs tab, which owns nothing beyond this list.
  final ValueChanged<String>? onSessionDeleted;

  /// Whose sessions to list; null reads the signed-in user's own. The friend
  /// viewer passes the friend's id (2026-10-23).
  final String? userId;

  /// A friend's list: no delete drawer, no ownership actions — the list is
  /// somebody else's history.
  final bool readOnly;

  /// Whether a card's swipe offers Delete. A friend's list and coach mode
  /// both set this false; unlike [readOnly] it does not imply "no writes",
  /// so a coach acting as the athlete keeps every other action (2026-10-28).
  final bool canDelete;

  /// The header's name — 'Training Logs' for the own list, the friend's name
  /// for theirs.
  final String headerTitle;

  /// A back affordance in the header; null for the tab root, which has none.
  final VoidCallback? onBack;

  /// The empty state's copy; defaults are the own-list's.
  final String? emptyMessage;
  final String? emptyHint;

  /// The route a tapped card opens; defaults to the own viewer.
  final String Function(String sessionId)? sessionRouteBuilder;

  /// A tap's whole handling, when the host wants it rather than a route
  /// string. Coach mode pushes its own viewer with the two-tab bar
  /// (2026-10-28); when null the [sessionRouteBuilder] route is pushed.
  final void Function(String sessionId)? onOpenSession;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with RouteAware {
  late LogsViewModel _viewModel;
  String? _selectedExercise;
  String? _selectedVariation;

  /// The workout (planned session) filter — a `planned_session_id`, null for
  /// every session (2026-10-23).
  String? _selectedWorkoutId;

  /// The date filter — the same shared [DateRangeSelection] the exercises >
  /// insights page uses, defaulting to ALL (no filtering).
  DateRangeSelection _dateSelection = const DateRangeSelection.preset(
    DateRangePreset.all,
  );

  static const _defaultDateSelection = DateRangeSelection.preset(
    DateRangePreset.all,
  );

  /// Name-keyed comparator: most recently used first (nulls last, then name).
  static int _byNameRecency(
    String a,
    String b,
    Map<String, DateTime> lastUsed,
  ) {
    final da = lastUsed[a];
    final db = lastUsed[b];
    if (da != null && db != null) return db.compareTo(da);
    if (da != null) return -1;
    if (db != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    // Built here, not in a field initializer: the VM takes the widget's
    // userId, which only exists once the State is mounted (2026-10-23).
    _viewModel = LogsViewModel(userId: widget.userId);
    _viewModel.load();
  }

  @override
  void didUpdateWidget(covariant LogsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different friend's list under the same element: rebuild the VM so
    // every read switches users, and drop the filters scoped to the old one.
    if (widget.userId != oldWidget.userId) {
      _viewModel.dispose();
      _viewModel = LogsViewModel(userId: widget.userId);
      _viewModel.load();
      _selectedExercise = null;
      _selectedVariation = null;
      _selectedWorkoutId = null;
      _dateSelection = _defaultDateSelection;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer here — ModalRoute.of(context) depends on
    // inherited widgets that aren't available during initState.
    AppRouter.routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    AppRouter.routeObserver.unsubscribe(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Refresh when returning from workout detail so edits (added sets,
    // changed notes, deleted sets) are reflected immediately.
    _viewModel.load();
  }

  String get _dateLabel => _dateSelection.label(DateTime.now());

  bool get _dateActive => _dateSelection != _defaultDateSelection;

  void _clearFilters() => setState(() {
    _selectedExercise = null;
    _selectedVariation = null;
    _selectedWorkoutId = null;
    _dateSelection = _defaultDateSelection;
  });

  /// The card's ⋮ → Delete Session — shared confirmation first, then the
  /// cascading hard delete and a reload. Only completed sessions are ever
  /// listed (both list queries filter `end_datetime IS NOT NULL`), so the
  /// in-progress workout can never be deleted out from under the live
  /// session VM from here.
  Future<void> _confirmDeleteSession(SessionWithSets w) async {
    final ok = await confirmDeleteSession(context, setCount: w.sets.length);
    if (!ok || !mounted) return;
    await _viewModel.deleteSession(w.session.sessionId);
    if (!mounted) return;
    widget.onSessionDeleted?.call(w.session.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<LogsState>(
        valueListenable: _viewModel.state,
        builder: (context, state, _) {
          // ── derive filter options ─────────────────────────────────────────────
          // The list is sessions only (2026-10-23): the Sets tab is gone and
          // every filter reads the sets those sessions carry.
          final allSets = state.sessions.expand((w) => w.sets).toList();

          // The workouts (planned sessions) the listed sessions followed,
          // keyed by id — a rename keeps old snapshots under the same id, so
          // the newest session's name labels the whole group.
          final workouts = <String, String>{};
          for (final w in state.sessions) {
            final id = w.session.plannedSessionId;
            if (id == null) continue;
            workouts.putIfAbsent(
              id,
              () => w.session.plannedSessionName ?? 'Planned session',
            );
          }

          // Most recently used first (names derived from the dated timeline).
          final byId = lastUsedByEntity(state.pastSets);
          final lastUsed = <String, DateTime>{};
          for (final s in state.pastSets) {
            final exId = s.exerciseId;
            if (exId == null) continue;
            final exD = byId[exId];
            final exName = s.exerciseName ?? exId;
            if (exD != null &&
                (!lastUsed.containsKey(exName) ||
                    exD.isAfter(lastUsed[exName]!))) {
              lastUsed[exName] = exD;
            }
            final vName = s.variationName;
            if (vName != null && s.variationId != null) {
              final vD = byId[s.variationId!];
              if (vD != null &&
                  (!lastUsed.containsKey(vName) ||
                      vD.isAfter(lastUsed[vName]!))) {
                lastUsed[vName] = vD;
              }
            }
          }

          final exercises =
              allSets
                  .where((s) => s.exerciseId != null)
                  .map((s) => s.exerciseName ?? s.exerciseId!)
                  .toSet()
                  .toList()
                ..sort((a, b) => _byNameRecency(a, b, lastUsed));

          final variations =
              allSets
                  .where(
                    (s) =>
                        _selectedExercise == null ||
                        (s.exerciseName ?? s.exerciseId) == _selectedExercise,
                  )
                  .map((s) => s.variationName)
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort((a, b) => _byNameRecency(a, b, lastUsed));

          // ── client-side filtering ─────────────────────────────────────────────
          bool matchesExercise(SessionExerciseSet s) =>
              _selectedExercise == null ||
              (s.exerciseName ?? s.exerciseId) == _selectedExercise;

          bool matchesVariation(SessionExerciseSet s) =>
              _selectedVariation == null ||
              s.variationName == _selectedVariation;

          bool matchesWorkout(Session s) =>
              _selectedWorkoutId == null ||
              s.plannedSessionId == _selectedWorkoutId;

          bool matchesDate(DateTime dt) {
            // Days are local days — the same conversion the row's own date
            // reads with, so a session near midnight filters into the day it
            // is shown on.
            final w = _dateSelection.window(DateTime.now());
            final local = dt.toLocal();
            return !local.isBefore(w.from) && local.isBefore(w.to);
          }

          final filteredSessions = state.sessions.where((w) {
            if (!matchesDate(w.session.createdDatetime)) return false;
            if (!matchesWorkout(w.session)) return false;
            return w.sets.any((s) => matchesExercise(s) && matchesVariation(s));
          }).toList();

          return Column(
            children: [
              if (widget.showHeader)
                PageHeader(
                  title: widget.headerTitle,
                  left: widget.onBack == null
                      ? null
                      : HeaderIconButton(
                          icon: Icons.arrow_back,
                          semanticsLabel: 'Back',
                          onPressed: widget.onBack,
                          color: AppColors.primary,
                        ),
                ),
              LogsFilterBar(
                exercises: exercises,
                variations: variations,
                workouts: workouts,
                selectedExercise: _selectedExercise,
                selectedVariation: _selectedVariation,
                selectedWorkoutId: _selectedWorkoutId,
                dateLabel: _dateLabel,
                dateActive: _dateActive,
                onExerciseChanged: (v) => setState(() {
                  _selectedExercise = v;
                  _selectedVariation = null;
                }),
                onVariationChanged: (v) =>
                    setState(() => _selectedVariation = v),
                onWorkoutChanged: (v) =>
                    setState(() => _selectedWorkoutId = v),
                onDateTap: () async {
                  // The shared date-range selector — the same custom filter
                  // the exercises > insights page uses.
                  final sel = await showDateRangeSelector(
                    context,
                    initial: _dateSelection,
                  );
                  if (sel != null && mounted) {
                    setState(() => _dateSelection = sel);
                  }
                },
                onClear:
                    (_selectedExercise != null ||
                        _selectedVariation != null ||
                        _selectedWorkoutId != null ||
                        _dateActive)
                    ? _clearFilters
                    : null,
              ),
              if (state.isLoading)
                Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else
                Expanded(
                  child: _SessionsPanel(
                    workouts: filteredSessions,
                    isRefreshing: state.isRefreshing,
                    onRefresh: _viewModel.refresh,
                    onTap: (id) {
                      final open = widget.onOpenSession;
                      if (open != null) {
                        open(id);
                        return;
                      }
                      context.push(
                        widget.sessionRouteBuilder?.call(id) ?? '/logs/$id',
                      );
                    },
                    // A friend's history has no delete: the drawer is the
                    // list's edit path, and there is none (2026-10-23).
                    onDelete: widget.readOnly || !widget.canDelete
                        ? null
                        : _confirmDeleteSession,
                    emptyMessage: widget.emptyMessage,
                    emptyHint: widget.emptyHint,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({
    required this.workouts,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onTap,
    required this.onDelete,
    this.emptyMessage,
    this.emptyHint,
  });

  final List<SessionWithSets> workouts;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onTap;

  /// Null when the list is read-only (a friend's history) — every card then
  /// draws without its delete drawer.
  final ValueChanged<SessionWithSets>? onDelete;

  final String? emptyMessage;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    if (workouts.isEmpty) {
      return _EmptyState(
        onRefresh: onRefresh,
        message: emptyMessage ?? 'No sessions yet',
        hint: emptyHint ?? 'Start a session from the header to see it here.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView.builder(
        // Zero unless this list is the Session tab's Home, where the shell's
        // bar floats over it.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
        ),
        itemCount: workouts.length,
        itemBuilder: (_, i) {
          final w = workouts[i];
          // THE session card — the same one the all-sessions sheet shows.
          // onDelete renders the card's ⋮; null on a friend's read-only list,
          // where the card draws without it.
          return SessionLogCard(
            workout: w,
            onTap: () => onTap(w.session.sessionId),
            onDelete: onDelete == null ? null : () => onDelete!(w),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onRefresh,
    required this.message,
    required this.hint,
  });

  final Future<void> Function() onRefresh;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  message,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      height: 1.4,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
