import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/features/programs/view/program_workout_row.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/planned_banner.dart';
import 'package:lambda/shared/widgets/user_name_text.dart';

/// The one renderer for user-created names (2026-10-20).
///
/// The unit contract is small — one line, ellipsized, a tooltip only where
/// asked for. The rest of this file is the reason the widget exists: the three
/// surfaces that used to break under a long name are pumped at the narrowest
/// phone width with a 200-character name, and `takeException()` is asserted
/// null. A `RenderFlex` overflow throws inside the pump, so an unprotected
/// `Text` fails here rather than in a screenshot.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

const _long =
    'Elevated Unilateral Single-Leg Deficit Bulgarian Split Squat With A '
    'Paused Eccentric And A Two Second Isometric Hold At The Bottom';

void main() {
  group('the renderer', () {
    testWidgets('draws one line with an ellipsis', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 120,
            child: UserNameText(_long, style: const TextStyle(fontSize: 14)),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeats the whole value on long-press only when asked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          UserNameText(
            'Incline',
            tooltip: true,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
      expect(find.byTooltip('Incline'), findsOneWidget);

      await tester.pumpWidget(
        _host(UserNameText('Incline', style: const TextStyle(fontSize: 14))),
      );
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('an empty name still draws (the "still loading" row)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(UserNameText('', style: const TextStyle(fontSize: 14))),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('320px regressions — a name may not break its card', () {
    testWidgets('the workout card', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: ProgramWorkoutRow(
              workout: const PlannedSession(
                sessionId: 's1',
                userId: 'u1',
                name: _long,
                notes: 'A note that also must hold its line',
              ),
              badge: 'Session 3',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the planned-source banner over a session', (tester) async {
      await tester.pumpWidget(
        _host(const SizedBox(width: 320, child: PlannedBanner(name: _long))),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the set row\'s variation cell', (tester) async {
      // The compact dropdown is what `SessionSetRow` puts in the VARIATION
      // cell; its Row used to size to the label's intrinsic width and
      // overflow the cell (2026-10-20).
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 96,
            child: DropdownSelect<String>(
              compact: true,
              options: const [DropdownOption(label: _long, value: 'v1')],
              value: 'v1',
              onChange: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
