import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/exercise_tab_chip.dart';
import '../../../../shared/widgets/feeling_rating.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/lambda_readout.dart';
import '../../../../shared/widgets/lambda_search_field.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/stats_row.dart';
import '../../../../shared/widgets/swipe_actions.dart';

/// The living style catalog — every design token, translucent recipe, and
/// shared component in one scrollable reference. Dev-tab only.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // Interactive-demo state.
  int? _feeling;
  String _segmentValue = 'Weekly';
  String _segmentSubtle = 'View';
  String? _variationValue;
  final _inputCtrl = TextEditingController();
  final _requiredCtrl = TextEditingController();
  final _errorCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _requiredCtrl.dispose();
    _errorCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

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
                title: 'Style Gallery',
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
                    _Section(
                      label: 'Colors',
                      c: c,
                      children: [_ColorGrid(c: c, entries: _allColors(c))],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Token Hex Values',
                      c: c,
                      children: [
                        for (final (label, color) in _allColors(c))
                          _SurfaceRow(label, color, c),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Translucent Recipes',
                      c: c,
                      children: [
                        _GlassRecipeRow(
                          label:
                              'Glass · fill withAlpha(26) + border withAlpha(77) '
                              '— buttons, pills, note button',
                          fill: c.primary.withAlpha(26),
                          outline: c.primary.withAlpha(77),
                          ink: c.primary,
                          c: c,
                        ),
                        _GlassRecipeRow(
                          label:
                              'Chip · fill 0.1 + border 0.3 (accent) '
                              '— pill buttons, program chips',
                          fill: c.accent.withValues(alpha: 0.1),
                          outline: c.accent.withValues(alpha: 0.3),
                          ink: c.accent,
                          c: c,
                        ),
                        _GlassRecipeRow(
                          label:
                              'Soft highlight (accent) · accentBg fill + '
                              'accent 0.35 border — PR badges, arrows',
                          fill: c.accentBg,
                          outline: c.accent.withValues(alpha: 0.35),
                          ink: c.accent,
                          c: c,
                        ),
                        _GlassRecipeRow(
                          label:
                              'Soft highlight (planned) · plannedBg fill + '
                              'planned 0.35 border — planned containers, '
                              'ghost cells',
                          fill: c.plannedBg,
                          outline: c.planned.withValues(alpha: 0.35),
                          ink: c.planned,
                          c: c,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Typography',
                      c: c,
                      children: [
                        _TypeRow('xxl · 28', AppTextStyles.xxl, c),
                        _TypeRow('xl · 20', AppTextStyles.xl, c),
                        _TypeRow('lg · 17', AppTextStyles.lg, c),
                        _TypeRow('md · 15', AppTextStyles.md, c),
                        _TypeRow('sm · 13', AppTextStyles.sm, c),
                        _TypeRow('xs · 11', AppTextStyles.xs, c),
                        _MonoRow(
                          label: 'mono · 12',
                          sample: '105kg × 5 @ 8 RPE',
                          style: AppFonts.mono(fontSize: 14, color: c.primary),
                          c: c,
                        ),
                        _MonoRow(
                          label: 'micro · 9',
                          sample: 'SECTION LABEL',
                          style: AppFonts.mono(
                            fontSize: 13,
                            letterSpacing: 0.8,
                            color: c.muted,
                          ),
                          c: c,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Spacing',
                      c: c,
                      children: [
                        _SpacingRow('xs · 4', AppSpacing.xs, c),
                        _SpacingRow('sm · 8', AppSpacing.sm, c),
                        _SpacingRow('md · 12', AppSpacing.md, c),
                        _SpacingRow('lg · 16', AppSpacing.lg, c),
                        _SpacingRow('xl · 24', AppSpacing.xl, c),
                        _SpacingRow('xxl · 32', AppSpacing.xxl, c),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Radius',
                      c: c,
                      children: [
                        _RadiusRow('md · 8', AppRadius.md, c),
                        _RadiusRow('lg · 12', AppRadius.lg, c),
                        _RadiusRow('pill · 999', 999, c),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Buttons',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              GlassButton(label: 'Glass', onPressed: () {}),
                              GlassButton(
                                label: 'Solid CTA',
                                solid: true,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Accent',
                                color: c.accent,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Success',
                                color: c.success,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Danger',
                                color: c.danger,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Glass compact',
                                compact: true,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Solid compact',
                                solid: true,
                                compact: true,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Disabled',
                                disabled: true,
                                onPressed: () {},
                              ),
                              GlassButton(
                                label: 'Loading',
                                loading: true,
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Inputs',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LambdaInput(
                                controller: _inputCtrl,
                                label: 'Standard field',
                                placeholder: 'Placeholder…',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              LambdaInput(
                                controller: _requiredCtrl,
                                label: 'Required field',
                                placeholder: 'Required…',
                                required: true,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              LambdaInput(
                                controller: _errorCtrl,
                                label: 'Field with error',
                                error: 'Something went wrong',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              LambdaInput(
                                controller: _inputCtrl,
                                label: 'Disabled field',
                                enabled: false,
                              ),
                              // The text-box rule's other halves: a dense
                              // search box, and a box that is read rather
                              // than written (frontend-design §6).
                              const SizedBox(height: AppSpacing.md),
                              LambdaSearchField(
                                controller: _searchCtrl,
                                showIcon: true,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const LambdaReadout(
                                label: 'Read-only box',
                                value: 'Text that is shown rather than '
                                    'written wears this.',
                              ),
                              // The ground rule: the fill is always one tier
                              // above what the box stands on, so the same
                              // field on a surface card steps up
                              // (frontend-design §6).
                              const SizedBox(height: AppSpacing.md),
                              AppCard(
                                child: LambdaInput(
                                  controller: _inputCtrl,
                                  label: 'Field on a card',
                                  placeholder: 'Steps up on surface…',
                                  elevated: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Cards',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppCard(
                                child: Text(
                                  'Static card',
                                  style: TextStyle(
                                    fontSize: AppTextStyles.sm,
                                    color: c.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AppCard(
                                onTap: () {},
                                child: Text(
                                  'Pressable card (squash on tap)',
                                  style: TextStyle(
                                    fontSize: AppTextStyles.sm,
                                    color: c.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Chips & Pills',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ExerciseTabChip(
                                    label: 'Active pill',
                                    isActive: true,
                                    count: 5,
                                    onTap: () {},
                                  ),
                                  ExerciseTabChip(
                                    label: 'Inactive pill',
                                    isActive: false,
                                    onTap: () {},
                                  ),
                                  ExerciseTabChip(
                                    label: 'Removable',
                                    isActive: true,
                                    onTap: () {},
                                    onRemove: () {},
                                  ),
                                  AddExerciseButton(onTap: () {}),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              // Pill-button treatment (accent tint) used by the
                              // exercise-card header actions.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: c.accent.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.history,
                                      size: 11,
                                      color: c.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'History',
                                      style: AppFonts.mono(
                                        fontSize: 13,
                                        letterSpacing: 0.4,
                                        color: c.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Stats Bar',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: StatsRow(
                            tiles: [
                              const StatsTile(label: 'SETS', value: '12'),
                              const StatsTile(
                                label: 'PRS',
                                value: '3',
                                accent: true,
                              ),
                              const StatsTile(label: 'EXERCISES', value: '4'),
                              const StatsTile(label: 'AVG REST', value: '1:45'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Feeling Rating',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Interactive — tap a square to select/toggle.
                              FeelingRating(
                                value: _feeling,
                                onChanged: (n) => setState(
                                  () => _feeling = _feeling == n ? null : n,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              // Read-only — fills cumulatively up to the value.
                              FeelingRating(value: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Segmented Control',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedControl<String>(
                                options: const [
                                  SegmentOption(
                                    label: 'Weekly',
                                    value: 'Weekly',
                                  ),
                                  SegmentOption(
                                    label: 'Calendar',
                                    value: 'Calendar',
                                  ),
                                ],
                                value: _segmentValue,
                                onChange: (v) =>
                                    setState(() => _segmentValue = v),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              SegmentedControl<String>(
                                options: const [
                                  SegmentOption(label: 'View', value: 'View'),
                                  SegmentOption(label: 'Edit', value: 'Edit'),
                                ],
                                value: _segmentSubtle,
                                subtle: true,
                                onChange: (v) =>
                                    setState(() => _segmentSubtle = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Dropdown',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.bg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.border, width: 0.5),
                            ),
                            child: DropdownSelect<String?>(
                              placeholder: 'No Variation',
                              options: [
                                const DropdownOption<String?>(
                                  label: 'No Variation',
                                  value: null,
                                ),
                                const DropdownOption(
                                  label: 'Incline',
                                  value: 'incline',
                                ),
                                const DropdownOption(
                                  label: 'Paused',
                                  value: 'paused',
                                ),
                                const DropdownOption(
                                  label: 'Close Grip',
                                  value: 'close-grip',
                                ),
                              ],
                              value: _variationValue,
                              compact: true,
                              valueColor: c.primary,
                              createNewLabel: 'New Variation',
                              onCreateNew: (_) async {},
                              onChange: (v) =>
                                  setState(() => _variationValue = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Section Divider',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(height: 1, color: c.border),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: Text(
                                  'PREVIOUS SESSION',
                                  style: AppFonts.mono(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    color: c.primary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(height: 1, color: c.border),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Banners',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Banner(
                                icon: Icons.check_circle_outline,
                                text:
                                    'Session complete, rest well and see you soon',
                                fill: c.successBg,
                                border: c.success,
                                ink: c.success,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _Banner(
                                icon: Icons.event_outlined,
                                text: 'Chest Day — planned session',
                                fill: c.plannedBg,
                                border: c.planned,
                                ink: c.planned,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _Banner(
                                icon: Icons.error_outline,
                                text: 'Something went wrong',
                                fill: c.dangerBg,
                                border: c.dangerBorder,
                                ink: c.danger,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'PR Card & Lesson Row',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // PR-set style: accentBg fill with the accent
                              // outline.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: c.accentBg,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(
                                    color: c.accent,
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.emoji_events_outlined,
                                      size: 16,
                                      color: c.accent,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        '5RM: 100kg  →  105kg',
                                        style: AppFonts.mono(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: c.accent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              // Lesson row: surfaceHigh fill + hairline border.
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: c.surfaceHigh,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(color: c.border),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.menu_book_outlined,
                                      size: 16,
                                      color: c.primary,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'Keep your elbows tucked on the press.',
                                        style: TextStyle(
                                          fontSize: AppTextStyles.sm,
                                          color: c.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(
                      label: 'Set Row + Swipe Actions',
                      c: c,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: SwipeActions(
                            borderRadius: AppRadius.md,
                            actions: [
                              SwipeAction(
                                icon: Icons.copy_rounded,
                                label: 'Duplicate',
                                color: c.accent,
                                onTap: () {},
                              ),
                              SwipeAction(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                color: c.danger,
                                onTap: () {},
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: c.surfaceHigh,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                border: Border.all(color: c.border, width: 0.5),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: Text(
                                      '1',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.mono(
                                        fontSize: 13,
                                        color: c.muted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '105',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.mono(
                                        fontSize: 15,
                                        color: c.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '5',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.mono(
                                        fontSize: 15,
                                        color: c.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '—',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: AppTextStyles.xs,
                                        color: c.muted,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // The note-button indicator — pill glass
                                  // when a set has a note — the neutral
                                  // glass treatment.
                                  Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.primary.withAlpha(26),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: c.primary.withAlpha(77),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.sticky_note_2_outlined,
                                      size: 15,
                                      color: c.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

List<(String, Color)> _allColors(LambdaColors c) => [
  ('primary', c.primary),
  ('muted', c.muted),
  ('accent', c.accent),
  ('accentText', c.accentText),
  ('bg', c.bg),
  ('surface', c.surface),
  ('surfaceHigh', c.surfaceHigh),
  ('surfaceLow', c.surfaceLow),
  ('border', c.border),
  ('planned', c.planned),
  ('plannedBg', c.plannedBg),
  ('success', c.success),
  ('successBg', c.successBg),
  ('danger', c.danger),
  ('dangerBg', c.dangerBg),
  ('dangerBorder', c.dangerBorder),
  ('accentBg', c.accentBg),
];

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.c,
    required this.children,
  });
  final String label;
  final LambdaColors c;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            color: c.muted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.c, required this.entries});
  final LambdaColors c;
  final List<(String, Color)> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (var row = 0; row * 4 < entries.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, color) in entries.skip(row * 4).take(4))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: AppTextStyles.xs,
                                color: c.muted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
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

class _TypeRow extends StatelessWidget {
  const _TypeRow(this.label, this.size, this.c);
  final String label;
  final double size;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
            ),
          ),
          Expanded(
            child: Text(
              'The quick brown fox',
              style: TextStyle(
                fontSize: size,
                color: c.primary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonoRow extends StatelessWidget {
  const _MonoRow({
    required this.label,
    required this.sample,
    required this.style,
    required this.c,
  });
  final String label;
  final String sample;
  final TextStyle style;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
            ),
          ),
          Expanded(child: Text(sample, style: style)),
        ],
      ),
    );
  }
}

class _SpacingRow extends StatelessWidget {
  const _SpacingRow(this.label, this.size, this.c);
  final String label;
  final double size;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
            ),
          ),
          Container(
            width: size * 3,
            height: 12,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${size.toInt()}px',
            style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _RadiusRow extends StatelessWidget {
  const _RadiusRow(this.label, this.radius, this.c);
  final String label;
  final double radius;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
            ),
          ),
          Container(
            width: 56,
            height: 40,
            decoration: BoxDecoration(
              color: c.surfaceHigh,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: c.border),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceRow extends StatelessWidget {
  const _SurfaceRow(this.label, this.color, this.c);
  final String label;
  final Color color;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.sm, color: c.primary),
            ),
          ),
          Text(
            hex,
            style: TextStyle(
              fontSize: AppTextStyles.xs,
              color: c.muted,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassRecipeRow extends StatelessWidget {
  const _GlassRecipeRow({
    required this.label,
    required this.fill,
    required this.outline,
    required this.ink,
    required this.c,
  });

  final String label;
  final Color fill;
  final Color outline;
  final Color ink;
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: outline),
            ),
            child: Text(
              'Sample',
              style: TextStyle(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.fill,
    required this.border,
    required this.ink,
  });

  final IconData icon;
  final String text;
  final Color fill;
  final Color border;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
