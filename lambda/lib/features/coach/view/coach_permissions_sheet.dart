import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';

/// “What coaching allows” (2026-10-29).
///
/// The grant is one switch that opens a defined, one-way door: read the
/// athlete's completed training and library, add new rows, and touch only
/// what the coach themselves created. This sheet states both halves before
/// the grant and stays reachable from the friend's profile afterwards (2026-10-30).
///
/// With [accepting] true it is the accept step's confirmation and returns
/// `true` for Accept, `false` for anything else.
Future<bool> showCoachPermissionsSheet(
  BuildContext context, {
  String? coachName,
  bool accepting = false,
}) async {
  final result = await showLambdaModal<bool>(
    context,
    fitContent: true,
    backgroundColor: AppColors.bg,
    child: _CoachPermissionsSheet(
      coachName: coachName,
      accepting: accepting,
    ),
  );
  return result ?? false;
}

class _CoachPermissionsSheet extends StatelessWidget {
  const _CoachPermissionsSheet({
    required this.coachName,
    required this.accepting,
  });

  final String? coachName;
  final bool accepting;

  @override
  Widget build(BuildContext context) {
    final name = coachName?.trim();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'What coaching allows',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.lg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  HeaderIconButton(
                    icon: LucideIcons.x,
                    semanticsLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              Text(
                name == null || name.isEmpty
                    ? 'A coach you accept can do these things — and cannot do these.'
                    : '$name can do these things — and cannot do these.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  height: 1.45,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading('CAN'),
                      _bullet(
                        'See your completed sessions, the sets you logged and '
                        'their notes.',
                        allowed: true,
                      ),
                      _bullet(
                        'See your exercise notes, your goals and your workouts.',
                        allowed: true,
                      ),
                      _bullet(
                        'Add exercises, variations, workouts, goals and '
                        'sessions to your library.',
                        allowed: true,
                      ),
                      _bullet(
                        'Rename or edit only the rows they created.',
                        allowed: true,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _heading('CANNOT'),
                      _bullet(
                        'Edit, rename, archive or delete anything you created.',
                        allowed: false,
                      ),
                      _bullet(
                        'See your bodyweight or your profile.',
                        allowed: false,
                      ),
                      _bullet(
                        'Keep access after you remove them.',
                        allowed: false,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'You can remove coaching at any time; access stops on '
                        'the next sync. Rows a coach already added stay in '
                        'your library.',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.xs,
                          height: 1.45,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (accepting)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GlassButton(
                      label: 'Accept coaching',
                      solid: true,
                      color: AppColors.success,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    GlassButton(
                      label: 'Not now',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                )
              else
                GlassButton(
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.primary,
      ),
    ),
  );

  static Widget _bullet(String text, {required bool allowed}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          allowed
              ? LucideIcons.circleCheck
              : LucideIcons.circleMinus,
          size: 16,
          color: allowed ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              height: 1.4,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}
