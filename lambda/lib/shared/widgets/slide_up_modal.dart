import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import 'dropdown_select.dart';

Future<T?> showLambdaModal<T>(
  BuildContext context, {
  required Widget child,
  bool fitContent = true,
  bool keyboardAware = false,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: fitContent,
    useSafeArea: true,
    backgroundColor: backgroundColor ?? AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) {
      // Every sheet hosts its own DropdownSheetHost, so any DropdownSelect
      // inside shows its picker confined to this sheet instead of stacking
      // a second independent bottom sheet on top of it.
      Widget content = DropdownSheetHost(child: child);
      if (keyboardAware) {
        content = Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: content,
        );
      }
      return content;
    },
  );
}
