import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/page_header.dart';

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
                  icon: Icon(Icons.arrow_back_ios_new,
                      size: 18, color: c.primary),
                  onPressed: () => context.pop(),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
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
                    width: 28,
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
                  Text(label,
                      style: TextStyle(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: current.primary)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          fontSize: AppTextStyles.sm, color: current.muted)),
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
                  ? Icon(Icons.check,
                      size: 12, color: current.accentText)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
