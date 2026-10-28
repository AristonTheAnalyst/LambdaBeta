import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/planned_session.dart';
import '../../../../data/repositories/planned_session_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/archived_sheet.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../../../../shared/widgets/user_name_text.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_search_field.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/coach_created_mark.dart';
import '../../../shared/widgets/name_history_sheet.dart';
import '../viewmodel/workout_editor_viewmodel.dart';
import 'plan_session_screen.dart';

/// Library of standalone planned workouts (a single session, no program).
class WorkoutLibraryScreen extends StatefulWidget {
  const WorkoutLibraryScreen({
    super.key,
    this.showHeader = true,
    this.userId,
    this.readOnly = false,
    this.canDelete = true,
  });

  /// When embedded in a tab (Exercises hub), render content only — the hub
  /// owns the header, so a nested PageHeader would add empty top space and a
  /// dead back button.
  final bool showHeader;

  /// Whose workouts to read. Null = the signed-in user (the normal mount); a
  /// coach's read of an athlete's passes their id (2026-10-28).
  final String? userId;

  /// Browse only (2026-10-28): no +, no archived sheet, no swipe drawer and
  /// a card that does not open the editor — coach mode reads, it never
  /// writes.
  final bool readOnly;

  /// Whether a workout's swipe offers Delete. Coach mode creates, edits and
  /// duplicates as the athlete and never removes (2026-10-28).
  final bool canDelete;

  @override
  State<WorkoutLibraryScreen> createState() => _WorkoutLibraryScreenState();
}

class _WorkoutLibraryScreenState extends State<WorkoutLibraryScreen> {
  final _repo = PlannedSessionRepository();
  final _searchController = TextEditingController();
  List<PlannedSession> _workouts = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  String get _userId =>
      widget.userId ?? Supabase.instance.client.auth.currentUser!.id;

  /// Search-filtered view of the loaded workouts.
  List<PlannedSession> get _filtered => _query.isEmpty
      ? _workouts
      : _workouts
            .where((w) => w.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _query = _searchController.text),
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final w = await _repo.fetchPlannedSessions(_userId);
      if (mounted) {
        setState(() {
          _workouts = w;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _create() async {
    // The editor writes as the library's owner — the athlete in coach mode
    // (2026-10-28); the server stamps the author.
    final vm = WorkoutEditorViewModel(userId: widget.userId, canDelete: widget.canDelete);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlanSessionScreen(
          viewModel: vm,
          standalone: true,
          canDelete: widget.canDelete,
          // The editor disposes it, after its own dispose has committed the
          // name and notes (2026-10-28).
          ownsViewModel: true,
        ),
      ),
    );
    await _load();
  }

  Future<void> _edit(PlannedSession w) async {
    final vm = WorkoutEditorViewModel(userId: widget.userId, canDelete: widget.canDelete);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlanSessionScreen(
          viewModel: vm,
          standaloneWorkoutId: w.sessionId,
          canDelete: widget.canDelete,
          ownsViewModel: true,
        ),
      ),
    );
    await _load();
  }

  /// The owner's rename history for this workout (2026-10-29); restoring a
  /// name is a normal rename, which records itself.
  Future<void> _openNameHistory(PlannedSession w) async {
    await showNameHistorySheet(
      context,
      userId: _userId,
      entityType: 'workout',
      entityId: w.sessionId,
      currentName: w.name,
      onRestore: (name) async {
        await _repo.updatePlannedSession(
          w.sessionId,
          name: name,
          userId: _userId,
        );
        await _load();
      },
    );
  }

  Future<void> _duplicate(PlannedSession w) async {
    await _repo.duplicatePlannedSession(_userId, w);
    await _load();
  }

  void _openArchived() {
    showLambdaModal(
      context,
      fitContent: true,
      child: ArchivedSheet(
        title: 'Archived Sessions',
        emptyText: 'No archived sessions.',
        fetch: () async => [
          for (final s in await _repo.fetchArchivedPlannedSessions(_userId))
            (id: s.sessionId, name: s.name),
        ],
        onRestore: (id) async {
          await _repo.reactivatePlannedSession(id);
          await _load();
        },
      ),
    );
  }

  /// Deletes a never-used template outright; archives a used one. The dialog
  /// copy follows the usage state so the user always knows which happened.
  Future<void> _delete(PlannedSession w) async {
    final used = await _repo.plannedSessionUsageCount(w.sessionId) > 0;
    if (!mounted) return;
    final name = toProperCase(w.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          used ? 'Archive Session' : 'Delete Session',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          used
              ? 'Archive "$name"? It has been used, so it can\'t be fully '
                    'deleted — it will disappear from this list, but the '
                    'sessions logged from it stay intact.'
              : 'Delete "$name"? This can\'t be undone.',
          style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppFonts.ui(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              used ? 'Archive' : 'Delete',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (used) {
        await _repo.deletePlannedSession(w.sessionId);
      } else {
        await _repo.hardDeletePlannedSession(w.sessionId);
      }
      await _load();
    }
  }

  /// One workout's card, the list's only row shape.
  ///
  /// A read-only surface draws it bare (2026-10-28): the tap opens the
  /// editor, so it is spent on nothing, and the drawer that duplicates and
  /// deletes is not wrapped around it.
  Widget _card(PlannedSession w) => AppCard(
    // Her own workouts are read-only to the coach; the ones this coach
    // created are theirs to edit (2026-10-29).
    onTap: widget.readOnly || (widget.userId != null && w.createdByUserId == null)
        ? null
        : () => _edit(w),
    background: AppColors.plannedBg,
    borderColor: AppColors.planned.withValues(alpha: 0.35),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One line, ellipsized — the notes under it already hold
              // their own, and a wrapping name moves the card's shape
              // (2026-10-20).
              UserNameText(
                toProperCase(w.name),
                tooltip: true,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (w.notes?.isNotEmpty == true)
                Text(
                  w.notes!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (w.createdByUserId != null || w.updatedByUserId != null) ...[
                const SizedBox(height: 2),
                CoachCreatedMark(
                  createdByUserId: w.createdByUserId,
                  updatedByUserId: w.updatedByUserId,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (widget.showHeader)
            PageHeader(
              title: 'Workouts',
              // Coach mode browses only (2026-10-28): the + is absent when
              // nothing may be created.
              right: widget.readOnly
                  ? null
                  : GlassButton(
                      label: '',
                      icon: Icons.add,
                      semanticsLabel: 'New workout',
                      compact: true,
                      onPressed: _create,
                    ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load workouts.',
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.md,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.xs,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GlassButton(label: 'Retry', onPressed: _load),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      if (!widget.showHeader)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            0,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: LambdaSearchField(
                                  controller: _searchController,
                                ),
                              ),
                              // Coach mode browses only (2026-10-28): no +,
                              // and no archived sheet — restoring writes.
                              if (!widget.readOnly) ...[
                                const SizedBox(width: AppSpacing.sm),
                                GlassButton(
                                  label: '',
                                  icon: Icons.add,
                                  semanticsLabel: 'New workout',
                                  onPressed: _create,
                                  compact: true,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                GlassButton(
                                  label: '',
                                  icon: Icons.archive_outlined,
                                  semanticsLabel: 'Archived workouts',
                                  onPressed: _openArchived,
                                  compact: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      Expanded(
                        child: _workouts.isEmpty
                            ? Center(
                                child: Text(
                                  'No workouts yet — create one to get started.',
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    color: AppColors.inkSecondary,
                                  ),
                                ),
                              )
                            : _filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No matches for "$_query".',
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    color: AppColors.inkSecondary,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                // Zero unless the shell's bar is floating over this
                                // list, which is where the Library's Workouts tab
                                // lives.
                                padding: EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.lg +
                                      ScrollShrinkNavBar.contentInset(context),
                                ),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: AppSpacing.md),
                                itemBuilder: (context, i) {
                                  final w = _filtered[i];
                                  final card = _card(w);
                                  // Coach mode edits and duplicates as the
                                  // athlete and never deletes (2026-10-28):
                                  // the drawer keeps its copy, loses its trash.
                                  if (widget.readOnly) return card;
                                  return SwipeActions(
                                    actions: [
                                      // The owner's rename history
                                      // (2026-10-29); a coach's device never
                                      // receives it.
                                      if (widget.userId == null)
                                        SwipeAction(
                                          icon: Icons.history,
                                          color: AppColors.primary,
                                          foreground: AppColors.bg,
                                          onTap: () => _openNameHistory(w),
                                        ),
                                      SwipeAction(
                                        icon: Icons.copy_rounded,
                                        color: AppColors.accent,
                                        foreground: AppColors.accentText,
                                        onTap: () => _duplicate(w),
                                      ),
                                      if (widget.canDelete)
                                        SwipeAction(
                                          icon: Icons.delete_outline,
                                          color: AppColors.danger,
                                          foreground: AppColors.dangerText,
                                          onTap: () => _delete(w),
                                        ),
                                    ],
                                    child: card,
                                  );
                                },
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
