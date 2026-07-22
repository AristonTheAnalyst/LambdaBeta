import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/page_header.dart';

class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

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
                    _Section(label: 'Colors', c: c, children: [
                      _ColorGrid(c: c),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(label: 'Typography', c: c, children: [
                      _TypeRow('xxl · 28', AppTextStyles.xxl, c),
                      _TypeRow('xl · 20',  AppTextStyles.xl,  c),
                      _TypeRow('lg · 17',  AppTextStyles.lg,  c),
                      _TypeRow('md · 15',  AppTextStyles.md,  c),
                      _TypeRow('sm · 13',  AppTextStyles.sm,  c),
                      _TypeRow('xs · 11',  AppTextStyles.xs,  c),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(label: 'Spacing', c: c, children: [
                      _SpacingRow('xs · 4',   AppSpacing.xs,  c),
                      _SpacingRow('sm · 8',   AppSpacing.sm,  c),
                      _SpacingRow('md · 12',  AppSpacing.md,  c),
                      _SpacingRow('lg · 16',  AppSpacing.lg,  c),
                      _SpacingRow('xl · 24',  AppSpacing.xl,  c),
                      _SpacingRow('xxl · 32', AppSpacing.xxl, c),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(label: 'Surfaces & Borders', c: c, children: [
                      _SurfaceRow('bg',          c.bg,          c),
                      _SurfaceRow('surface',     c.surface,     c),
                      _SurfaceRow('surfaceHigh', c.surfaceHigh, c),
                      _SurfaceRow('border',      c.border,      c),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(label: 'State Colors', c: c, children: [
                      _SurfaceRow('danger',       c.danger,       c),
                      _SurfaceRow('dangerBg',     c.dangerBg,     c),
                      _SurfaceRow('dangerBorder', c.dangerBorder, c),
                      _SurfaceRow('accentBg',     c.accentBg,     c),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _Section(label: 'Interactive', c: c, children: [
                      _ButtonShowcase(c: c),
                    ]),
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

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.c, required this.children});
  final String label;
  final LambdaColors c;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w700,
                color: c.muted,
                letterSpacing: 1.2)),
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
  const _ColorGrid({required this.c});
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    final swatches = [
      ('primary',    c.primary),
      ('muted',      c.muted),
      ('accent',     c.accent),
      ('accentText', c.accentText),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: swatches.map((s) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: s.$2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(s.$1,
                      style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }).toList(),
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
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted)),
          ),
          Expanded(
            child: Text('The quick brown fox',
                style: TextStyle(
                    fontSize: size,
                    color: c.primary,
                    fontWeight: FontWeight.w400)),
          ),
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
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted)),
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
          Text('${size.toInt()}px',
              style: TextStyle(fontSize: AppTextStyles.xs, color: c.muted)),
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
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style:
                    TextStyle(fontSize: AppTextStyles.sm, color: c.primary)),
          ),
          Text(hex,
              style: TextStyle(
                  fontSize: AppTextStyles.xs,
                  color: c.muted,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _ButtonShowcase extends StatelessWidget {
  const _ButtonShowcase({required this.c});
  final LambdaColors c;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.accentText,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {},
              child: const Text('Primary Button'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Outline button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.primary,
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {},
              child: const Text('Outline Button'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Danger button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.dangerBg,
                foregroundColor: c.danger,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {},
              child: const Text('Danger Button'),
            ),
          ),
        ],
      ),
    );
  }
}
