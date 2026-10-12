import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';

/// One row of the review picker: what it is, the lines under it, and whether it
/// is ticked.
///
/// Ticking is the same reading as the add-exercise modal — accent row and the
/// green tick, and nothing at all on a row that is not ticked — because it is
/// the same gesture: a page that stays put while the user builds a set by
/// tapping rows. The two pages that build a review's set wear it: the selection
/// screen a pass is started from, and the sheet an open pass's scope is
/// edited in.
class ReviewTickRow extends StatelessWidget {
  const ReviewTickRow({
    super.key,
    required this.title,
    required this.ticked,
    required this.onTap,
    this.caption,
    this.target,
  });

  final String title;
  final bool ticked;
  final VoidCallback onTap;

  /// The value on the title's line, right-aligned — a goal's target. The name
  /// and the target are the two elements they are, each drawn as its own, so
  /// the values line up in a column down the list instead of trailing the
  /// names in prose. Mono, because it is a numeric readout like the set
  /// grid's cells — the one place mono is at home here.
  final String? target;

  /// The lines under the title — what the row states about itself: the
  /// workout's window and its count. Prose, so it wears the UI face, never
  /// mono (2026-10-10). One [Text] per line, so a line too long for the sheet
  /// shortens on its own rather than wrapping into the one below it.
  final List<String>? caption;

  @override
  Widget build(BuildContext context) {
    // Bound to locals: public fields do not promote through null checks.
    final caption = this.caption;
    final target = this.target;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: glassBox(ticked ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: 14,
                            fontWeight: ticked
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: ticked
                                ? AppColors.accent
                                : AppColors.primary,
                          ),
                        ),
                      ),
                      if (target != null && target.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          target,
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  for (final line in caption ?? const <String>[])
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.xs,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            // The exercise selector's own tick, exactly: the green mark once
            // ticked, nothing on an unticked row.
            if (ticked) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, size: 14, color: AppColors.success),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a run of tick rows is: the mono header the two lists sit under.
class ReviewSectionLabel extends StatelessWidget {
  const ReviewSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      color: AppColors.muted,
      letterSpacing: 0.8,
    ),
  );
}
