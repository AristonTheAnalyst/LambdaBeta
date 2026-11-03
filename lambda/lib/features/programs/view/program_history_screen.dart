import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/header_icon_button.dart';
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
            left: HeaderIconButton(
              icon: LucideIcons.chevronLeft,
              semanticsLabel: 'Back',
              glyphSize: 18,
              onPressed: () => Navigator.of(context).pop(),
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
