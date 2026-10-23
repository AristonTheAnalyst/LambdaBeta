import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/shared/widgets/info_button.dart';

import 'support/readable_text.dart';

/// The Library header's ⓘ: one button, one tab's explanation, and a way out.
///
/// The content is the host's — the hub swaps it per tab — so what this pins is
/// the contract: the button opens a sheet naming what it explains, the sheet
/// carries the body, and "Got it" puts it away without navigating anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont(AppFonts.uiFamily, const [
      'assets/fonts/Manrope-400.ttf',
      'assets/fonts/Manrope-600.ttf',
      'assets/fonts/Manrope-800.ttf',
    ]);
    await _loadFont(AppFonts.monoFamily, const [
      'assets/fonts/JetBrainsMono-400.ttf',
      'assets/fonts/JetBrainsMono-700.ttf',
    ]);
  });

  testWidgets('opens the tab\'s explanation and dismisses with Got it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: const [
              InfoButton(
                title: 'Goals',
                body: 'A weight × reps target on one exercise.',
                icon: Icons.flag_outlined,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsOneWidget);
    expect(
      find.text('A weight × reps target on one exercise.'),
      findsOneWidget,
    );
    expectReadableText(tester, find.byType(MaterialApp));

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('A weight × reps target on one exercise.'), findsNothing);
  });
}

/// Registers a bundled typeface under the family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}
