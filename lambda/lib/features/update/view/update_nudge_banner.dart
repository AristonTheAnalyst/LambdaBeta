import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';

const _androidStoreUrl =
    'https://play.google.com/store/apps/details?id=com.rockyzubiri.lambda';
const _iosStoreUrl = 'https://apps.apple.com/app/idXXXXXXXXXX';

/// Dismissible nudge shown when a newer (but not mandatory) version is
/// available. The caller is responsible for hiding this once dismissed —
/// it doesn't block anything underneath it.
class UpdateNudgeBanner extends StatelessWidget {
  const UpdateNudgeBanner({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  Future<void> _openStore() async {
    final url = Platform.isIOS ? _iosStoreUrl : _androidStoreUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
            child: Row(
              children: [
                Icon(Icons.system_update_alt,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'A new version is available.',
                    style: TextStyle(
                        fontSize: AppTextStyles.sm, color: AppColors.primary),
                  ),
                ),
                GestureDetector(
                  onTap: _openStore,
                  child: Text('Update',
                      style: TextStyle(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent)),
                ),
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close, size: 16, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
