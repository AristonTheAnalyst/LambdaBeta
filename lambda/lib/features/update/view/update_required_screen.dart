import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/glass_button.dart';

// Fill in once the app is published to each store.
const _androidStoreUrl =
    'https://play.google.com/store/apps/details?id=com.rockyzubiri.lambda';
const _iosStoreUrl = 'https://apps.apple.com/app/idXXXXXXXXXX';

/// Full-screen, non-dismissible gate shown when the installed app version is
/// below app_config.min_version. There is no way out of this screen except
/// updating — no back button, no close affordance.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _openStore() async {
    final url = Platform.isIOS ? _iosStoreUrl : _androidStoreUrl;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.system_update_alt,
                    size: 56, color: AppColors.accent),
                const SizedBox(height: AppSpacing.lg),
                Text('Update Required',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppTextStyles.xxl,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This version of the app is no longer supported. Please update to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppTextStyles.md, color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.xl),
                GlassButton(
                  label: 'Update Now',
                  onPressed: _openStore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
