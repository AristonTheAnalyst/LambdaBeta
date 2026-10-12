import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/page_header.dart';
import 'program_history_panel.dart';

/// A program's history as a screen of its own.
///
/// Reached from a block editor, which links to the phase's own record. The
/// program screen reads the same history inline, as its Reviews tab — both
/// hosts show one [ProgramHistoryPanel], so the two can never drift.
class ProgramHistoryScreen extends StatelessWidget {
  const ProgramHistoryScreen({
    super.key,
    required this.programId,
    this.initialBlockId,
  });

  final String programId;
  final String? initialBlockId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'History',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.accent,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              // The panel carries no header of its own, so the screen insets
              // it the way the header used to sit above it.
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: ProgramHistoryPanel(
                programId: programId,
                initialBlockId: initialBlockId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
