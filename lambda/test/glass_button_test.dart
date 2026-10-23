import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The one button, in its glyph-only form — what most of the app's chrome
/// became on 2026-10-20.
///
/// Two contracts worth pinning, because both are invisible when they break:
/// a lone glyph must still *say* something (semantics for a screen reader,
/// tooltip for a sighted user meeting the shape for the first time), and it
/// must be at least 40×40 to tap (the design skill's floor). The third — a
/// labelled button still drawing its word — is a regression guard on the same
/// widget, since the glyph path sits beside it.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('icon-only', () {
    testWidgets('carries its word as both tooltip and semantics label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          GlassButton(
            label: '',
            icon: Icons.arrow_back_ios_new,
            semanticsLabel: 'Back',
            compact: true,
            onPressed: () {},
          ),
        ),
      );

      // One string, two audiences: hover/long-press for the eye, the
      // semantics tree for a screen reader.
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('stands on the 40px target floor, compact or not', (
      tester,
    ) async {
      for (final compact in [true, false]) {
        await tester.pumpWidget(
          _host(
            GlassButton(
              label: '',
              icon: Icons.check,
              semanticsLabel: 'Save',
              compact: compact,
              onPressed: () {},
            ),
          ),
        );
        final size = tester.getSize(find.byType(GlassButton));
        expect(
          size.height,
          greaterThanOrEqualTo(40),
          reason: 'compact: $compact',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(40),
          reason: 'compact: $compact',
        );
      }
    });

    testWidgets('a disabled glyph still names itself and does not fire', (
      tester,
    ) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          GlassButton(
            label: '',
            icon: Icons.close,
            semanticsLabel: 'Cancel',
            disabled: true,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
      await tester.tap(find.byType(GlassButton), warnIfMissed: false);
      expect(taps, 0);
      handle.dispose();
    });
  });

  group('with a label', () {
    testWidgets('the word is the reading — no tooltip is invented for it', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GlassButton(
            label: 'Save',
            icon: Icons.check,
            onPressed: () => taps++,
          ),
        ),
      );

      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      await tester.tap(find.byType(GlassButton));
      expect(taps, 1);
    });
  });
}
