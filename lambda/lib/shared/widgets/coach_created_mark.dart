import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';

/// “Added by your coach” — the provenance mark (2026-10-28).
///
/// Coach mode writes rows owned by the athlete (`user_id`) with the coach as
/// `created_by_user_id`. The owner's device should see that authorship; the
/// coach's own device should not — the coach already knows, and everything on
/// their screen is under the coach-mode bar. The signed-in account answers
/// both cases without threading the acting identity down every tile: on the
/// athlete's device `auth.uid()` is the owner, so a coach-authored row differs
/// and the mark draws; on the coach's device it equals the author, so it does
/// not. Rows the owner wrote (NULL) never draw.
///
/// One line, quiet ink — this is a fact about the row, not a control.
class CoachCreatedMark extends StatelessWidget {
  const CoachCreatedMark({
    super.key,
    this.createdByUserId,
    this.updatedByUserId,
  });

  /// Who created the row. NULL = the owner.
  final String? createdByUserId;

  /// Who last edited it. Shown only when the creation was not the coach's —
  /// a row the coach added stays “Added by your coach” even if they later
  /// edited it (2026-10-29).
  final String? updatedByUserId;

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final added = createdByUserId != null && createdByUserId != me;
    final edited =
        !added && updatedByUserId != null && updatedByUserId != me;
    if (!added && !edited) return const SizedBox.shrink();
    return Text(
      added ? 'Added by your coach' : 'Edited by your coach',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppFonts.ui(
        fontSize: AppTextStyles.xs,
        color: AppColors.inkSecondary,
      ),
    );
  }
}
