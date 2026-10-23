import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_text_styles.dart';
import 'package:lambda/core/theme/lambda_theme.dart';

/// Stock Material chrome is themed once in [LambdaColors.toThemeData].
/// These tests pin the ink split there, so a stock dialog, date picker or
/// text button can never quietly reintroduce `muted` informational text
/// (2026-10-22).
void main() {
  // Every palette themes the stock chrome through the same code path; running
  // them all catches a palette that forgets a token the chrome reads.
  final palettes = [
    for (final variant in LambdaThemeVariant.values)
      (variant.name, variant.colors),
  ];

  for (final (name, p) in palettes) {
    group(name, () {
      final theme = p.toThemeData();

      test('dialog content is secondary ink at the prose height', () {
        final content = theme.dialogTheme.contentTextStyle!;
        expect(content.color, p.inkSecondary);
        expect(content.fontSize, AppTextStyles.sm);
        expect(content.height, 1.4);
      });

      test('date-picker chrome: help/weekday/Cancel quiet, OK accent', () {
        final picker = theme.datePickerTheme;
        expect(picker.headerHelpStyle?.color, p.inkSecondary);
        expect(picker.weekdayStyle?.color, p.inkSecondary);
        expect(
          picker.cancelButtonStyle?.foregroundColor?.resolve(const {}),
          p.inkSecondary,
        );
        expect(
          picker.confirmButtonStyle?.foregroundColor?.resolve(const {}),
          p.accent,
        );
      });

      test('disabled date-picker days stay decorative (alpha muted)', () {
        final picker = theme.datePickerTheme;
        final disabled = p.muted.withValues(alpha: 0.4);
        expect(
          picker.dayForegroundColor?.resolve(const {WidgetState.disabled}),
          disabled,
        );
        expect(
          picker.yearForegroundColor?.resolve(const {WidgetState.disabled}),
          disabled,
        );
      });

      test('ColorScheme text slots never carry muted', () {
        final scheme = theme.colorScheme;
        expect(scheme.onSurface, p.primary);
        expect(scheme.secondary, p.inkSecondary);
        expect(scheme.tertiary, p.inkSecondary);
        expect(scheme.outline, p.border);
        expect(scheme.outlineVariant, p.border);
        // Error chrome inks with the danger token, never with accentText —
        // which is dark on the bright-accent palettes.
        expect(scheme.error, p.danger);
        expect(scheme.onError, p.dangerText);
      });

      test('a stock text button is accent, never muted', () {
        expect(
          theme.textButtonTheme.style?.foregroundColor?.resolve(const {}),
          p.accent,
        );
      });
    });
  }
}
