import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'glass_button.dart';
import 'slide_up_modal.dart';

/// The ⓘ that explains a screen: a bare icon in a header's right slot, opening
/// a short sheet about what is on the page.
///
/// One content per tab is the point (2026-10-19): the Library's six tabs each
/// describe themselves, so the button always explains what is in front of the
/// user rather than a generic guide. The same widget serves any screen that
/// needs to say what it is.
class InfoButton extends StatelessWidget {
  const InfoButton({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
    this.size = 22,
  });

  /// The heading of the sheet — the tab or screen's own name.
  final String title;

  /// The explanation, one short paragraph.
  final String body;

  /// The glyph beside the heading, naming the screen at a glance.
  final IconData icon;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'About $title',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            showInfoSheet(context, title: title, body: body, icon: icon),
        // A header slot sized like the compact buttons beside it: the glyph is
        // small, but the target it answers to is not.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.info_outline, size: size, color: AppColors.accent),
        ),
      ),
    );
  }
}

/// Opens the information sheet: a heading with its glyph, the explanation, and
/// the one button that puts it away.
Future<void> showInfoSheet(
  BuildContext context, {
  required String title,
  required String body,
  IconData icon = Icons.info_outline,
}) => showLambdaModal<void>(
  context,
  fitContent: true,
  child: SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.lg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              color: AppColors.inkSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          GlassButton(
            label: 'Got it',
            solid: true,
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    ),
  ),
);
