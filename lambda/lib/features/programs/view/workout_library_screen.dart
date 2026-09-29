import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/planned_session.dart';
import '../../../../data/repositories/planned_session_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/archived_sheet.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/page_header.dart';
import '../viewmodel/workout_editor_viewmodel.dart';
import 'plan_session_screen.dart';

/// Library of standalone planned workouts (a single session, no program).
class WorkoutLibraryScreen extends StatefulWidget {
  const WorkoutLibraryScreen({super.key, this.showHeader = true});

  /// When embedded in a tab (Exercises hub), render content only — the hub
  /// owns the header, so a nested PageHeader would add empty top space and a
  /// dead back button.
  final bool showHeader;

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

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

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
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _create() async {
    final vm = WorkoutEditorViewModel();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          builder: (_) => PlanSessionScreen(viewModel: vm, standalone: true)),
    );
    vm.dispose();
    await _load();
  }

  Future<void> _edit(PlannedSession w) async {
    final vm = WorkoutEditorViewModel();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          builder: (_) => PlanSessionScreen(
              viewModel: vm, standaloneWorkoutId: w.sessionId)),
    );
    vm.dispose();
    await _load();
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
        title: Text(used ? 'Archive Session' : 'Delete Session',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text(
            used
                ? 'Archive "$name"? It has been used, so it can\'t be fully '
                  'deleted — it will disappear from this list, but the '
                  'sessions logged from it stay intact.'
                : 'Delete "$name"? This can\'t be undone.',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(used ? 'Archive' : 'Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (widget.showHeader)
            PageHeader(
              title: 'Workouts',
              right: GlassButton(
                label: '',
                icon: Icons.add,
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
                              Text('Could not load workouts.',
                                  style: AppFonts.ui(
                                      fontSize: AppTextStyles.md,
                                      color: AppColors.danger)),
                              const SizedBox(height: AppSpacing.sm),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: AppFonts.ui(
                                      fontSize: AppTextStyles.xs,
                                      color: AppColors.muted)),
                              const SizedBox(height: AppSpacing.lg),
                              GlassButton(
                                label: 'Retry',
                                onPressed: _load,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                    children: [
                      if (!widget.showHeader)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    color: AppColors.primary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search…',
                                    hintStyle:
                                        AppFonts.ui(color: AppColors.muted),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.md),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              GlassButton(
                                label: '',
                                icon: Icons.add,
                                onPressed: _create,
                                compact: true,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              GlassButton(
                                label: '',
                                icon: Icons.archive_outlined,
                                onPressed: _openArchived,
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _workouts.isEmpty
                            ? Center(
                                child: Text('No workouts yet — create one to get started.',
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.md, color: AppColors.muted)),
                              )
                            : _filtered.isEmpty
                                ? Center(
                                    child: Text(
                                      'No matches for "$_query".',
                                      style: AppFonts.ui(
                                        fontSize: AppTextStyles.sm,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) {
                          final w = _filtered[i];
                          return SwipeActions(
                            actions: [
                              SwipeAction(
                                icon: Icons.copy_rounded,
                                label: 'Duplicate',
                                color: AppColors.accent,
                                onTap: () => _duplicate(w),
                              ),
                              SwipeAction(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                color: AppColors.danger,
                                onTap: () => _delete(w),
                              ),
                            ],
                            child: AppCard(
                            onTap: () => _edit(w),
                            background: AppColors.plannedBg,
                            borderColor:
                                AppColors.planned.withValues(alpha: 0.35),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(toProperCase(w.name),
                                          style: AppFonts.ui(
                                              fontSize: AppTextStyles.md,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary)),
                                      if (w.notes?.isNotEmpty == true)
                                        Text(w.notes!,
                                            style: AppFonts.ui(
                                                fontSize: AppTextStyles.xs,
                                                color: AppColors.muted),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                    ],
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
          ),
        ],
      ),
    );
  }
}
