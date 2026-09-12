import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/theme/lambda_theme.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.titleWidget,
    this.left,
    this.right,
  });

  final String title;

  /// Replaces the plain [title] text when provided — e.g. a tappable
  /// variation selector.
  final Widget? titleWidget;
  final Widget? left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final topPadding = MediaQuery.of(context).padding.top;
        return Container(
          padding: EdgeInsets.only(top: topPadding),
          decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (left != null)
                  Positioned(left: 16, child: left!),
                Positioned(
                  left: 88,
                  right: 88,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: titleWidget ??
                        Text(
                          title,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                ),
                if (right != null)
                  Positioned(right: 16, child: right!),
              ],
            ),
          ),
        );
      },
    );
  }
}
