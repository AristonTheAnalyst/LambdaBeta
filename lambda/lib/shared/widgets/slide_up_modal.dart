import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';

Future<T?> showLambdaModal<T>(
  BuildContext context, {
  required Widget child,
  bool fitContent = true,
  bool keyboardAware = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: fitContent,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
    ),
    builder: (ctx) {
      Widget content = child;
      if (keyboardAware) {
        content = Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: child,
        );
      }
      return content;
    },
  );
}
