import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/theme/lambda_theme.dart';
import 'package:lambda/features/profile/view/appearance_screen.dart';
import 'package:lambda/features/profile/view/profile_hub_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/readable_text.dart';

/// Profile → Appearance: the official theme picker (2026-10-22).
///
/// The dev Experimental screen still carries its own copy, so the picker
/// itself is covered once, here, through the surface a user actually opens.
/// The palette catalog is the single source for both surfaces, so covering
/// every [LambdaThemeVariant] here covers what the dev screen can offer too.

Finder _option(LambdaThemeVariant variant) =>
    find.byKey(ValueKey('theme-option-${variant.name}'));

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    themeNotifier.value = LambdaThemeVariant.primary;
  });

  testWidgets('every palette is offered exactly once', (tester) async {
    await _pump(tester, const AppearanceScreen());

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('DARK'), findsOneWidget);
    expect(find.text('LIGHT'), findsOneWidget);

    for (final variant in LambdaThemeVariant.values) {
      expect(_option(variant), findsOneWidget, reason: variant.name);
      expect(find.text(variant.label), findsOneWidget, reason: variant.name);
      expect(
        find.text(variant.description),
        findsOneWidget,
        reason: variant.name,
      );
    }
    expectReadableText(tester, find.byType(AppearanceScreen));
  });

  testWidgets('dark palettes sit above the LIGHT heading, light below', (
    tester,
  ) async {
    await _pump(tester, const AppearanceScreen());

    final headingY = tester.getTopLeft(find.text('LIGHT')).dy;
    for (final variant in LambdaThemeVariant.values) {
      final y = tester.getTopLeft(find.text(variant.label)).dy;
      if (variant.isLight) {
        expect(y, greaterThan(headingY), reason: variant.name);
      } else {
        expect(y, lessThan(headingY), reason: variant.name);
      }
    }
  });

  testWidgets('only the current palette is ticked', (tester) async {
    await _pump(tester, const AppearanceScreen());

    for (final variant in LambdaThemeVariant.values) {
      expect(
        find.descendant(
          of: _option(variant),
          matching: find.byIcon(Icons.check),
        ),
        variant == LambdaThemeVariant.primary ? findsOneWidget : findsNothing,
        reason: variant.name,
      );
    }
  });

  testWidgets('tapping a palette switches it at once and moves the tick', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const AppearanceScreen());

    await tester.ensureVisible(find.text('Ruby'));
    await tester.tap(find.text('Ruby'));
    await tester.pumpAndSettle();

    expect(themeNotifier.value, LambdaThemeVariant.ruby);
    expect(themeNotifier.colors.bg, LambdaColors.ruby.bg);
    expect(
      find.descendant(
        of: _option(LambdaThemeVariant.ruby),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _option(LambdaThemeVariant.primary),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );

    // The card announces itself as a radio, not a plain button: the tick is
    // drawn, so the group flag is what a screen reader hears.
    expect(
      tester.getSemantics(_option(LambdaThemeVariant.ruby)),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('every palette applies and keeps the page readable', (
    tester,
  ) async {
    await _pump(tester, const AppearanceScreen());

    for (final variant in LambdaThemeVariant.values) {
      themeNotifier.value = variant;
      await tester.pumpAndSettle();
      expect(themeNotifier.colors.bg, variant.colors.bg, reason: variant.name);
      expectReadableText(tester, find.byType(AppearanceScreen));
    }
  });

  testWidgets('the section headings follow a live switch', (tester) async {
    // The report that named this test: open the picker in a light palette and
    // switch to a dark one — the DARK/LIGHT headings kept their old ink and
    // sat dark-on-dark. They were const, so the rebuild skipped them.
    themeNotifier.value = LambdaThemeVariant.monoLight;
    await _pump(tester, const AppearanceScreen());

    Color? heading(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    expect(heading('DARK'), LambdaColors.monoLight.primary);
    expect(heading('LIGHT'), LambdaColors.monoLight.primary);

    themeNotifier.value = LambdaThemeVariant.ruby;
    await tester.pumpAndSettle();

    expect(heading('DARK'), LambdaColors.ruby.primary);
    expect(heading('LIGHT'), LambdaColors.ruby.primary);
  });

  testWidgets('the profile hub carries both pages', (tester) async {
    await _pump(tester, const ProfileHubScreen());

    expect(find.text('User Profile'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expectReadableText(tester, find.byType(ProfileHubScreen));
  });

  test('the catalog is six dark palettes then four light ones', () {
    final dark = [
      for (final variant in LambdaThemeVariant.values)
        if (!variant.isLight) variant.name,
    ];
    final light = [
      for (final variant in LambdaThemeVariant.values)
        if (variant.isLight) variant.name,
    ];

    expect(dark, [
      'primary',
      'midnight',
      'deepSea',
      'plum',
      'graphite',
      'ruby',
    ]);
    expect(light, ['monoLight', 'porcelain', 'sand', 'blush']);

    for (final variant in LambdaThemeVariant.values) {
      expect(variant.label.trim(), isNotEmpty, reason: variant.name);
      expect(variant.description.trim(), isNotEmpty, reason: variant.name);
    }
  });

  test('restore applies the stored palette', () async {
    SharedPreferences.setMockInitialValues({
      'lambda_theme_variant': 'monoLight',
    });
    final notifier = LambdaThemeNotifier();

    await notifier.restore();

    expect(notifier.value, LambdaThemeVariant.monoLight);
    expect(notifier.colors.bg, LambdaColors.monoLight.bg);
  });

  test('restore applies a palette added after the first two', () async {
    SharedPreferences.setMockInitialValues({'lambda_theme_variant': 'ruby'});
    final notifier = LambdaThemeNotifier();

    await notifier.restore();

    expect(notifier.value, LambdaThemeVariant.ruby);
    expect(notifier.colors.bg, LambdaColors.ruby.bg);
  });

  test('restore ignores a missing or retired palette', () async {
    SharedPreferences.setMockInitialValues({'lambda_theme_variant': 'neon'});
    final notifier = LambdaThemeNotifier();

    await notifier.restore();

    expect(notifier.value, LambdaThemeVariant.primary);
  });

  test('a choice is remembered for the next launch', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = LambdaThemeNotifier();

    notifier.value = LambdaThemeVariant.blush;
    // The write is fire-and-forget; let the preference future land.
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('lambda_theme_variant'), 'blush');
  });
}
