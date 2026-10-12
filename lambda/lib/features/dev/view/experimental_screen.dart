import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/exercise_selector.dart';
import '../../../../shared/widgets/lambda_search_field.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../../shared/widgets/slide_up_modal.dart';

class ExperimentalScreen extends StatelessWidget {
  const ExperimentalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final c = themeNotifier.colors;
        return Scaffold(
          backgroundColor: c.bg,
          body: Column(
            children: [
              PageHeader(
                title: 'Experimental',
                left: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: c.primary,
                  ),
                  onPressed: () => context.pop(),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(
                child: ListView(
                  // The shell's bar floats over this page, so the last
                  // section has to be able to scroll clear of it.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    ScrollShrinkNavBar.contentInset(context),
                  ),
                  children: [
                    Text(
                      'THEME',
                      style: TextStyle(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ThemeOption(
                      variant: LambdaThemeVariant.primary,
                      label: 'Primary Theme',
                      description: 'Dark warm palette with amber accent',
                      preview: LambdaColors.dark,
                      current: c,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ThemeOption(
                      variant: LambdaThemeVariant.monoLight,
                      label: 'Mono Light',
                      description: 'Clean white background with dark grey text',
                      preview: LambdaColors.monoLight,
                      current: c,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'EXERCISE SELECTOR',
                      style: TextStyle(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w700,
                        color: c.muted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // G sits at the top so its expanded list is fully
                    // visible without the page scrolling.
                    _SelectorOption(
                      label: 'A — Dropdown menu',
                      description:
                          'A simple select field: tap to open a pop-up '
                          'menu over the screen. The selected exercise '
                          'shows highlighted in the menu; up/down arrows '
                          'reorder, Add Exercise is pinned at the bottom, '
                          'and holding the X for 1s asks before deleting '
                          'the exercise and its sets.',
                      child: _DropdownMenuSelector(
                        exercises: _sampleExercises,
                        c: c,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _SelectorOption(
                      label: 'C — Pager with dots',
                      description:
                          'One exercise at a time: chevrons page through, '
                          'dots show the position. Tap to open the exercise '
                          'menu — tap a row to jump, drag to reorder, and '
                          'add exercises from the bottom picker.',
                      child: _PagerExerciseSelector(
                        exercises: _sampleExercises,
                        c: c,
                      ),
                    ),
                  ],
                ),
              ),
              // Empty sections at the bottom keep the expanded menus fully
              // visible above the fold.
              const SizedBox(height: AppSpacing.xxl * 3),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.variant,
    required this.label,
    required this.description,
    required this.preview,
    required this.current,
  });

  final LambdaThemeVariant variant;
  final String label;
  final String description;
  final LambdaColors preview;
  final LambdaColors current;

  bool get _isSelected => themeNotifier.value == variant;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => themeNotifier.value = variant,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: current.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isSelected ? current.accent : current.border,
            width: _isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            // Mini preview swatch
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: preview.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: current.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(
                      color: preview.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 20,
                    height: 6,
                    decoration: BoxDecoration(
                      color: preview.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 4,
                    decoration: BoxDecoration(
                      color: preview.muted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppTextStyles.md,
                      fontWeight: FontWeight.w600,
                      color: current.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: AppTextStyles.sm,
                      color: current.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSelected ? current.accent : Colors.transparent,
                border: Border.all(
                  color: _isSelected ? current.accent : current.border,
                  width: 2,
                ),
              ),
              child: _isSelected
                  ? Icon(Icons.check, size: 12, color: current.accentText)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

const _sampleExercises = [
  'Benchpress',
  'Squat',
  'Deadlift',
  'Overhead Press',
  'Barbell Row',
  'Pull Up',
];

/// Non-interactive card presenting one selector experiment.
class _SelectorOption extends StatelessWidget {
  const _SelectorOption({
    required this.label,
    required this.description,
    required this.child,
  });

  final String label;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w600,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(fontSize: AppTextStyles.sm, color: c.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// C — paged selector: chevrons + dot indicators, no scrolling at all.
class _PagerExerciseSelector extends StatefulWidget {
  const _PagerExerciseSelector({required this.exercises, required this.c});

  final List<String> exercises;
  final LambdaColors c;

  @override
  State<_PagerExerciseSelector> createState() => _PagerExerciseSelectorState();
}

class _PagerExerciseSelectorState extends State<_PagerExerciseSelector> {
  late final List<String> _exercises = [...widget.exercises];
  int _index = 0;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final canPrev = _index > 0;
    final canNext = _index < _exercises.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tap anywhere (name, chevrons, dots) to open the exercise menu.
        GestureDetector(
          key: const ValueKey('c-pager'),
          onTap: () => setState(() => _menuOpen = !_menuOpen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _chevron(
                    Icons.chevron_left,
                    canPrev,
                    () => setState(() => _index--),
                    c,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 160,
                    child: Text(
                      _exercises[_index],
                      textAlign: TextAlign.center,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w700,
                        color: c.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _chevron(
                    Icons.chevron_right,
                    canNext,
                    () => setState(() => _index++),
                    c,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _exercises.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? c.accent : c.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_menuOpen) ...[
          const SizedBox(height: AppSpacing.md),
          // The menu: tap a row to jump to it, drag the handle to reorder.
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              final selected = _exercises[_index];
              setState(() {
                final item = _exercises.removeAt(oldIndex);
                var insertAt = newIndex;
                if (insertAt > oldIndex) insertAt--;
                _exercises.insert(insertAt, item);
                _index = _exercises.indexOf(selected);
              });
            },
            itemCount: _exercises.length,
            itemBuilder: (context, i) => _menuRow(i),
          ),
          _newExerciseRow(),
        ],
      ],
    );
  }

  Widget _menuRow(int i) {
    final c = widget.c;
    final selected = i == _index;
    return Padding(
      key: ValueKey(_exercises[i]),
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => setState(() {
          _index = i;
          _menuOpen = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.primary.withAlpha(26) : c.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? c.primary.withAlpha(77) : c.border,
            ),
          ),
          child: Row(
            children: [
              Text(
                '${i + 1}',
                style: AppFonts.mono(
                  fontSize: 13,
                  color: selected ? c.primary : c.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _exercises[i],
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.primary : c.muted,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.check, size: 16, color: c.primary),
              ],
              const SizedBox(width: AppSpacing.sm),
              ReorderableDragStartListener(
                index: i,
                child: Icon(Icons.drag_handle, size: 18, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The menu's last row — opens the choose-exercise sheet; the picked (or
  /// created) exercise is appended and selected.
  Widget _newExerciseRow() {
    final c = widget.c;
    return GestureDetector(
      onTap: _openExercisePicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: c.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 16, color: c.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'New Exercise',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: c.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExercisePicker() async {
    final picked = await showLambdaModal<String>(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _ExercisePickerSheet(
        existing: _exercises,
        available: const [
          'Chest Fly',
          'Leg Press',
          'Dumbbell Curl',
          'Hip Thrust',
          'Lat Pulldown',
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _exercises.add(picked);
      _menuOpen = false;
      _index = _exercises.length - 1;
    });
  }

  Widget _chevron(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
    LambdaColors c,
  ) {
    return GestureDetector(
      // Disabled chevrons still claim the tap with a no-op handler.
      onTap: enabled ? onTap : () {},
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? c.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.border, width: enabled ? 1.0 : 0.5),
        ),
        child: Icon(icon, size: 16, color: enabled ? c.primary : c.muted),
      ),
    );
  }
}

/// A — simple select dropdown with reorder arrows and a delete option.
class _DropdownMenuSelector extends StatefulWidget {
  const _DropdownMenuSelector({required this.exercises, required this.c});

  final List<String> exercises;
  final LambdaColors c;

  @override
  State<_DropdownMenuSelector> createState() => _DropdownMenuSelectorState();
}

class _DropdownMenuSelectorState extends State<_DropdownMenuSelector> {
  late final List<String> _exercises = [...widget.exercises];
  int _active = 0;

  @override
  Widget build(BuildContext context) {
    return ExerciseSelector(
      exercises: _exercises,
      activeIndex: _active,
      onSelect: (i) => setState(() => _active = i),
      onMove: (i, dir) => setState(() {
        final e = _exercises.removeAt(i);
        _exercises.insert(i + dir, e);
      }),
      onAdd: _openExercisePicker,
    );
  }

  Future<void> _openExercisePicker() async {
    final picked = await showLambdaModal<String>(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _ExercisePickerSheet(
        existing: _exercises,
        available: const [
          'Chest Fly',
          'Leg Press',
          'Dumbbell Curl',
          'Hip Thrust',
          'Lat Pulldown',
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _exercises.add(picked);
      _active = _exercises.length - 1;
    });
  }

}

/// The demo's choose-exercise sheet — search the available list or create a
/// new name; returns the picked name.
///
/// Deliberately NOT the shared `showAddExerciseModal` (2026-09-29), unlike
/// every real screen: this demo drives a local `List<String>` with no
/// repository behind it, so it picks a *name* and hides rows already in the
/// list, where the real picker takes ids, shows additions ticked, and stays
/// open. Wiring it up would mean inventing a name→id adapter for a screen that
/// has no data layer — the drift is the honest state of a dev harness, and it
/// is noted here rather than papered over.
class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({required this.existing, required this.available});

  final List<String> existing;
  final List<String> available;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  String _query = '';

  List<String> get _filtered => widget.available
      .where(
        (e) =>
            !widget.existing.any((x) => x.toLowerCase() == e.toLowerCase()) &&
            e.toLowerCase().contains(_query.toLowerCase()),
      )
      .toList();

  bool get _canCreate {
    final q = _query.trim();
    if (q.length <= 1) return false;
    final lower = q.toLowerCase();
    return !widget.existing.any((x) => x.toLowerCase() == lower) &&
        !widget.available.any((e) => e.toLowerCase() == lower);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose exercise',
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
            LambdaSearchField(
              autofocus: true,
              showIcon: true,
              hint: 'Search exercises…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ..._filtered.map(
                    (e) => _resultRow(
                      e,
                      () => Navigator.of(context, rootNavigator: true).pop(e),
                    ),
                  ),
                  if (_canCreate)
                    _resultRow(
                      '+ Create "${_query.trim()}"',
                      () => Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop(_query.trim()),
                      accent: true,
                    ),
                  if (_filtered.isEmpty &&
                      !_canCreate &&
                      _query.trim().isNotEmpty)
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
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, VoidCallback onTap, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: accent
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppFonts.ui(
              fontSize: 14,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
