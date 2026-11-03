import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/core/styles/app_text_styles.dart';

/// Every [Text] under [within] must be readable: at or above the 12px label
/// floor, and never full-opacity `muted` — which measures 3.04–3.87:1 on the
/// dark grounds, below WCAG AA for text.
///
/// This is the guard for the 2026-10-21/22 readability rollout. If it fails,
/// a label slipped back below the floor or to decorative ink.
///
/// Two allowances keep the guard honest rather than noisy:
/// - **Alpha-muted is allowed.** Disabled chrome draws `muted.withValues(...)`
///   and is not informational text; only the full-opacity token is rejected.
/// - **[allowMuted] names absence glyphs** — the numeric `—` set-cell hint is
///   deliberately quiet (see the `accessibility` skill, §8).
///
/// `Text` whose style is null inherits from `DefaultTextStyle` and is not
/// inspected; the surfaces this guards draw explicit styles.
void expectReadableText(
  WidgetTester tester,
  Finder within, {
  Set<String> allowMuted = const {},
}) {
  for (final element
      in find.descendant(of: within, matching: find.byType(Text)).evaluate()) {
    final text = element.widget as Text;
    final style = text.style;
    if (style == null) continue;
    final label = text.data ?? '<rich>';
    if (allowMuted.contains(text.data)) continue;
    expect(
      style.color,
      isNot(AppColors.muted),
      reason: '"$label" is drawn in muted ink',
    );
    if (style.fontSize != null) {
      expect(
        style.fontSize,
        greaterThanOrEqualTo(AppTextStyles.xs),
        reason: '"$label" is below the 12px label floor',
      );
    }
  }
}
