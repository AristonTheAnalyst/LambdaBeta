import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/page_header.dart';

/// The still-empty screens behind the Friend Screen lab's rows (2026-11-03).
///
/// Variation, Goal, Workout and Review — the Session card opens the real
/// viewer's static mirror in `session_lab_screen.dart`, and an exercise opens
/// the dedicated screen in `exercise_lab_screen.dart`. The body here is
/// deliberately blank: these are placeholders to fill as the design settles.

class VariationLabScreen extends StatelessWidget {
  const VariationLabScreen({super.key, required this.name});

  final String name;

  static Route<void> route(String name) =>
      MaterialPageRoute(builder: (_) => VariationLabScreen(name: name));

  @override
  Widget build(BuildContext context) =>
      _LabScreen(kind: 'Variation', name: name);
}

class GoalLabScreen extends StatelessWidget {
  const GoalLabScreen({super.key, required this.name});

  final String name;

  static Route<void> route(String name) =>
      MaterialPageRoute(builder: (_) => GoalLabScreen(name: name));

  @override
  Widget build(BuildContext context) => _LabScreen(kind: 'Goal', name: name);
}

class WorkoutLabScreen extends StatelessWidget {
  const WorkoutLabScreen({super.key, required this.name});

  final String name;

  static Route<void> route(String name) =>
      MaterialPageRoute(builder: (_) => WorkoutLabScreen(name: name));

  @override
  Widget build(BuildContext context) =>
      _LabScreen(kind: 'Workout', name: name);
}

class ReviewLabScreen extends StatelessWidget {
  const ReviewLabScreen({super.key, required this.name});

  final String name;

  static Route<void> route(String name) =>
      MaterialPageRoute(builder: (_) => ReviewLabScreen(name: name));

  @override
  Widget build(BuildContext context) => _LabScreen(kind: 'Review', name: name);
}

/// The shared shell: the item's name in the header, its kind read as an
/// eyebrow, and nothing else — the empty body is the canvas to fill next.
class _LabScreen extends StatelessWidget {
  const _LabScreen({required this.kind, required this.name});

  final String kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: name,
            left: HeaderIconButton(
              icon: LucideIcons.arrowLeft,
              semanticsLabel: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${kind.toUpperCase()} · EMPTY',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
