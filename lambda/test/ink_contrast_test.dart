import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/theme/lambda_theme.dart';

/// The ink-role contract, measured (2026-10-22).
///
/// `primary` is content, `inkSecondary` is secondary text that must be read,
/// `muted` is decoration/disabled only. This test is why the split exists:
/// `muted` measures below WCAG AA for text on the dark palette, and the
/// numbers below are the ones the `accessibility` skill quotes.

/// WCAG relative-contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// `glassBox(color)` is `color.withAlpha(26)` painted over what is beneath —
/// a card, i.e. `surface`. That composite is the "primary glass" ground the
/// ink was measured against.
Color _glass(Color color, Color under) =>
    Color.alphaBlend(color.withAlpha(26), under);

void main() {
  // Every palette the picker offers, measured with the same gates. The
  // documented numbers below stay pinned to the default dark palette.
  final palettes = [
    for (final variant in LambdaThemeVariant.values)
      (variant.name, variant.colors),
  ];

  for (final (name, p) in palettes) {
    group(name, () {
      final grounds = <String, Color>{
        'bg': p.bg,
        'surface': p.surface,
        'surfaceHigh': p.surfaceHigh,
        'primary glass': _glass(p.primary, p.surface),
        'accent glass': _glass(p.accent, p.surface),
      };

      test('inkSecondary clears AA (4.5:1) on every ground', () {
        grounds.forEach((ground, color) {
          expect(
            _ratio(p.inkSecondary, color),
            greaterThanOrEqualTo(4.5),
            reason:
                'inkSecondary on $ground measured '
                '${_ratio(p.inkSecondary, color).toStringAsFixed(2)}:1',
          );
        });
      });

      test('primary clears AA on every ground', () {
        grounds.forEach((ground, color) {
          expect(
            _ratio(p.primary, color),
            greaterThanOrEqualTo(4.5),
            reason:
                'primary on $ground measured '
                '${_ratio(p.primary, color).toStringAsFixed(2)}:1',
          );
        });
      });

      test('muted carries decoration only', () {
        // On the dark palette it fails AA on all four text grounds — the
        // measured reason it may never carry informational text. (monoLight's
        // muted happens to clear 4.5:1, but the role is palette-independent.)
        if (name != 'primary') return;
        for (final ground in ['bg', 'surface', 'surfaceHigh']) {
          expect(
            _ratio(p.muted, grounds[ground]!),
            lessThan(4.5),
            reason: 'muted on $ground must stay below AA for text',
          );
        }
        expect(_ratio(p.muted, grounds['primary glass']!), lessThan(4.5));
      });

      test('every dark palette fails muted as text on its card grounds', () {
        // The comment above generalises: a dark palette's muted is a
        // decoration ink on the surfaces text actually sits on. (Some of the
        // new palettes' muted happens to clear 4.5 on the page ground; the
        // role follows the surfaces, where it never does.)
        if (p.bg.computeLuminance() >= 0.5) return;
        for (final ground in ['surface', 'surfaceHigh']) {
          expect(
            _ratio(p.muted, grounds[ground]!),
            lessThan(4.5),
            reason: 'muted on $ground must stay below AA for text',
          );
        }
      });

      test('danger text is readable on a solid danger fill', () {
        // The danger button paints `dangerText` on `danger`, not accentText:
        // accentText goes dark on the bright-accent palettes.
        expect(_ratio(p.dangerText, p.danger), greaterThanOrEqualTo(4.5));
      });

      test('accent ink is readable on the accentBg chip', () {
        // Chips filled with accentBg ink their label in accent (moved there
        // from accentText, which is white and invisible on light chips).
        expect(_ratio(p.accent, p.accentBg), greaterThanOrEqualTo(4.5));
      });

      test('planned chip ink is readable on a solid planned fill', () {
        // The white-on-blue chip (2026-10-23): a real value that IS the plan.
        // The fill is deeper than `planned` wherever `planned` is a light
        // blue, so white clears AA on it in every palette.
        expect(
          _ratio(p.plannedText, p.plannedFill),
          greaterThanOrEqualTo(4.5),
          reason:
              'plannedText on plannedFill measured '
              '${_ratio(p.plannedText, p.plannedFill).toStringAsFixed(2)}:1',
        );
      });
    });
  }

  test('dark accent keeps AA everywhere except primary glass', () {
    final p = LambdaColors.dark;
    for (final ground in [p.surface, p.surfaceHigh, p.accentBg]) {
      expect(_ratio(p.accent, ground), greaterThanOrEqualTo(4.5));
    }
    // Accent text on primary glass is the one failing pair; accent *icons*
    // there still clear the 3:1 non-text bar, which is why the chrome keeps
    // accent glyphs and moves accent words.
    final onGlass = _ratio(p.accent, _glass(p.primary, p.surface));
    expect(onGlass, lessThan(4.5));
    expect(onGlass, greaterThanOrEqualTo(3.0));
  });

  test('ruby separates the brand rose from the destructive brick', () {
    final p = LambdaColors.ruby;
    // Same utility red as every other palette — the brand colour is the one
    // that moved, so `danger` keeps meaning danger everywhere.
    expect(p.danger, LambdaColors.dark.danger);
    // A bright rose against the dark brick: a luminance step a reader can
    // see, without leaving the red family.
    expect(_ratio(p.accent, p.danger), greaterThan(1.8));
    expect(_ratio(p.accentText, p.accent), greaterThanOrEqualTo(4.5));
  });

  test('the documented dark numbers still hold', () {
    // Pinned so the `accessibility` skill and the palette cannot drift apart.
    final p = LambdaColors.dark;
    final glass = _glass(p.primary, p.surface);
    expect(_ratio(p.inkSecondary, p.surface), closeTo(6.03, 0.02));
    expect(_ratio(p.inkSecondary, p.surfaceHigh), closeTo(5.37, 0.02));
    expect(_ratio(p.inkSecondary, glass), closeTo(4.73, 0.02));
    expect(_ratio(p.accent, p.surface), closeTo(5.57, 0.02));
    expect(_ratio(p.accent, p.surfaceHigh), closeTo(4.96, 0.02));
    expect(_ratio(p.accent, glass), closeTo(4.37, 0.02));
    expect(_ratio(p.muted, p.surface), closeTo(3.87, 0.02));
  });
}
