import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';

/// Mixin for any [State] that needs to confirm before discarding unsaved
/// changes. Handles back-button taps and iOS back-swipe gestures.
///
/// Usage:
/// ```dart
/// class MyScreenState extends State<MyScreen> with UnsavedChangesGuard<MyScreen> {
///   @override
///   bool get hasUnsavedChanges => _hasDirtyFields;
///
///   Future<void> onSave() async { ... }
///   void onDiscard() { ... }
///
///   Widget build(BuildContext context) {
///     return buildGuardedScaffold(scaffold: Scaffold(...));
///   }
/// }
/// ```
mixin UnsavedChangesGuard<T extends StatefulWidget> on State<T> {
  /// Override to return true when there are unsaved changes.
  bool get hasUnsavedChanges => false;

  /// Override to perform the save. Called when the user taps "Save".
  Future<void> onSave() async {}

  /// Override to perform cleanup after discard. Called when the user
  /// taps "Discard" — e.g., reset editing state.
  void onDiscard() {}

  /// Wraps [scaffold] in a [PopScope] that intercepts back navigation
  /// when there are unsaved changes. After save/discard, pops the screen.
  Widget buildGuardedScaffold({required Widget scaffold}) {
    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAndPop();
      },
      child: scaffold,
    );
  }

  /// Shows the confirmation dialog. Returns true when the caller should
  /// proceed with navigation (no unsaved changes, or user saved/discarded).
  Future<bool> confirmBack() async {
    if (!hasUnsavedChanges) return true;
    await _showUnsavedDialog();
    return !hasUnsavedChanges;
  }

  void _confirmAndPop() async {
    if (!hasUnsavedChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _showUnsavedDialog();
    if (!hasUnsavedChanges && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showUnsavedDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Unsaved Changes',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
        content: Text('Save changes before leaving?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('discard'),
              child: Text('Discard', style: AppFonts.ui(color: AppColors.danger))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: Text('Stay', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text('Save',
                  style: AppFonts.ui(
                      color: AppColors.accent, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'cancel') return;
    if (choice == 'save') {
      await onSave();
    }
    onDiscard();
  }
}
