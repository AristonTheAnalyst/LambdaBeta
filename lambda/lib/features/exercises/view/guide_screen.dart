import 'package:flutter/material.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../shared/widgets/page_header.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'User Guide',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: AppColors.accent),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Section('Overview',
                      'Lambda is a workout tracker built around custom exercises, variations, and sets. Everything you log belongs to you and syncs to the cloud.'),
                  _Section('Exercises',
                      'An exercise is a movement pattern (e.g. "Bench Press"). Each exercise has a volume type: Reps (you track weight + rep counts) or Duration (you track seconds).'),
                  _Section('Variations',
                      'A variation is a modifier for an exercise (e.g. "Wide Grip", "Paused"). You assign variations to exercises. When logging a set you can optionally pick which variation you used.'),
                  _Section('Logging a workout',
                      '1. Go to the Session tab.\n2. Optionally choose a template and rate how you expect to feel.\n3. Tap "Start Workout".\n4. Tap "Log Set" to record each set. Select the exercise, optionally a variation, enter weight and reps.\n5. When finished, tap "End" in the header and add any post-workout notes.'),
                  _Section('Volume formula',
                      'Total volume = weight × sum of all reps across sets. For duration exercises, volume = sum of all seconds. This is shown in the Statistics tab.'),
                  _Section('Last updated', 'March 2026'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Text(body,
              style: TextStyle(
                  fontSize: AppTextStyles.md,
                  color: AppColors.muted,
                  height: 1.5)),
        ],
      ),
    );
  }
}
