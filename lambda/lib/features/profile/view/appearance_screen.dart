import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/header_icon_button.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';

/// Profile → Appearance: the official theme picker (2026-10-22).
///
/// The dev Experimental screen keeps a copy for flipping while building; this
/// is the user-facing surface, so it follows the production ink roles — no
/// `muted` text, the 12px floor, and every description in `inkSecondary`.
/// The choice persists in local preferences (`LambdaThemeNotifier`).
///
/// Every option comes from the catalog in `lambda_theme.dart`, and the two
/// sections split on the palette's own ground — dark palettes first, light
/// ones under their own heading.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final dark = [
          for (final variant in LambdaThemeVariant.values)
            if (!variant.isLight) variant,
        ];
        final light = [
          for (final variant in LambdaThemeVariant.values)
            if (variant.isLight) variant,
        ];
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              PageHeader(
                title: 'Appearance',
                left: HeaderIconButton(
                  icon: Icons.arrow_back_ios_new,
                  semanticsLabel: 'Back',
                  glyphSize: 18,
                  onPressed: () => context.pop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  // The shell's bar floats over this page, so the note at the
                  // bottom has to be able to scroll clear of it.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    ScrollShrinkNavBar.contentInset(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel('DARK', color: AppColors.primary),
                      const SizedBox(height: AppSpacing.sm),
                      _group(dark),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionLabel('LIGHT', color: AppColors.primary),
                      const SizedBox(height: AppSpacing.sm),
                      _group(light),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Your choice is saved on this device.',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.inkSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _group(List<LambdaThemeVariant> variants) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < variants.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _ThemeOption(
            variant: variants[i],
            selected: themeNotifier.value == variants[i],
          ),
        ],
      ],
    );
  }
}

/// The uppercase heading over one group, in the app's mono label voice.
///
/// The ink is passed in, not read from `AppColors` here: a const instance
/// would be the same widget on every rebuild, Flutter would skip it, and the
/// heading would keep the palette it was first built under — a dark heading
/// left sitting on a light ground after the user switched (2026-10-22). The
/// caller resolves the token on each build, so the instance is always new.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// One palette, offered as a radio card.
///
/// [selected] is passed in rather than read from the notifier inside the
/// widget: an identical instance would otherwise be skipped on rebuild and the
/// tick would never move.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({required this.variant, required this.selected});

  final LambdaThemeVariant variant;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final preview = variant.colors;
    // The card is a radio; the group flag is what a screen reader announces,
    // since the tick is drawn rather than built from a Radio widget.
    // [MergeSemantics] is outermost so the label, the flag and the tap action
    // all land on ONE node — with it inside, the flag sat on a node the
    // screen reader could not activate.
    return MergeSemantics(
      child: Semantics(
        key: ValueKey('theme-option-${variant.name}'),
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: PressSquash(
          onTap: () => themeNotifier.value = variant,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                // The palette in miniature — three bars on the offered
                // theme's own ground, drawn from that palette rather than the
                // one currently applied.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: preview.bg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
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
                        variant.label,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        variant.description,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.inkSecondary,
                          height: 1.4,
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
                    color: selected ? AppColors.accent : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 12, color: AppColors.accentText)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
