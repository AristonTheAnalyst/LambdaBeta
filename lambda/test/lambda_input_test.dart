import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_search_field.dart';

/// The ground rule on the app's text boxes (2026-10-08).
///
/// A box's fill is always one tier above what it stands on: `surface` on the
/// page ground — the Pre-Evaluation reference look — and `surfaceHigh` on a
/// `surface` ground (a card, a default modal sheet, the variation picker).
/// On a surface ground the usual fill vanishes, and a box that vanishes into
/// its ground reads as dead text however editable it actually is; the
/// Exercise Review Note was exactly that when the rule was written down.
void main() {
  Future<Color?> fillOf(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: field)));
    return tester
        .widget<TextField>(find.byType(TextField))
        .decoration!
        .fillColor;
  }

  testWidgets('on the page ground a box keeps the reference fill', (
    tester,
  ) async {
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    expect(
      await fillOf(tester, LambdaInput(controller: ctrl)),
      AppColors.surface,
      reason: 'the page ground is bg; surface sits one tier above it',
    );
  });

  testWidgets('on a surface ground a box steps up to surfaceHigh', (
    tester,
  ) async {
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    final fill = await fillOf(tester, LambdaInput(controller: ctrl, elevated: true));
    expect(fill, AppColors.surfaceHigh);
    expect(
      fill,
      isNot(AppColors.surface),
      reason: 'a fill matching the ground is the uneditable look the rule '
          'exists to prevent',
    );
  });

  testWidgets('the search twin steps up by the same rule', (tester) async {
    expect(
      await fillOf(tester, const LambdaSearchField(elevated: true)),
      AppColors.surfaceHigh,
    );
    expect(
      await fillOf(tester, const LambdaSearchField()),
      AppColors.surface,
      reason: 'a toolbar search box stands on the page and keeps the base '
          'fill',
    );
  });
}
