// LAB COPY — the /dev/pr-lab layout sandbox's own copy of the session
// ratings sheet. Never import this from a production screen. Edit freely:
// nothing here can reach the real session, planner, logs or PR History demo
// (2026-10-22).

import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import 'pr_lab_date_bar.dart';

/// One session's pre/post questionnaire, lab-owned and in memory.
///
/// The wizard pages are still the place the answers are entered; this is the
/// reading the action bar's pencil opens — another door to the same four
/// values (2026-10-22). Every edit returns a new value so the screen holds
/// one entry per date and a reopen reads what the last edit wrote.
class PrLabRatings {
  const PrLabRatings({
    this.preFeeling,
    this.preNotes = '',
    this.postFeeling,
    this.postNotes = '',
  });

  final int? preFeeling;
  final String preNotes;
  final int? postFeeling;
  final String postNotes;

  // Explicit copy methods rather than a `copyWith`: a feeling clears to
  // null when its star is tapped twice, and null-coalescing would keep the
  // old value instead of clearing it.
  PrLabRatings withPreFeeling(int? value) => PrLabRatings(
    preFeeling: value,
    preNotes: preNotes,
    postFeeling: postFeeling,
    postNotes: postNotes,
  );

  PrLabRatings withPostFeeling(int? value) => PrLabRatings(
    preFeeling: preFeeling,
    preNotes: preNotes,
    postFeeling: value,
    postNotes: postNotes,
  );

  PrLabRatings withPreNotes(String value) => PrLabRatings(
    preFeeling: preFeeling,
    preNotes: value,
    postFeeling: postFeeling,
    postNotes: postNotes,
  );

  PrLabRatings withPostNotes(String value) => PrLabRatings(
    preFeeling: preFeeling,
    preNotes: preNotes,
    postFeeling: postFeeling,
    postNotes: value,
  );
}

/// One session as the ratings sheet reads it — which entry of the date bar's
/// list is on the desk, the date and state the bar names, the four answers,
/// and which way the arrows may still walk.
///
/// The stage builds these, so the sheet and the stage's own date bar speak
/// from one source: stepping the sheet's arrows steps the stage behind it.
class PrLabRatingsPage {
  const PrLabRatingsPage({
    required this.index,
    required this.date,
    required this.isToday,
    required this.ratings,
    required this.canGoOlder,
    required this.canGoNewer,
  });

  final int index;
  final DateTime date;
  final bool isToday;
  final PrLabRatings ratings;
  final bool canGoOlder;
  final bool canGoNewer;

  /// Today's session is the one being filled in, so its answers are the
  /// reader's to change; a recorded session's belong to its record.
  bool get editable => isToday;
}

/// The pencil's sheet: both bookends on one page, over the same date changer
/// the stage carries at its floor.
///
/// [workoutName] names the session above the title — the date lives in the
/// bar at the bottom, where stepping it re-reads every section (2026-10-22).
/// The sections repeat the wizard pages' wording so the sheet and the pages
/// read as one feature, not two. A past session opens read-only, exactly as
/// the production viewer treats a recorded answer.
Future<void> showPrLabRatingsSheet(
  BuildContext context, {
  required String workoutName,
  required PrLabRatingsPage page,
  required PrLabRatingsPage? Function(int index) pageAt,
  required ValueChanged<int> onIndexChanged,
  required void Function(int index, PrLabRatings ratings) onChanged,
}) {
  return showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _PrLabRatingsSheetContent(
      workoutName: workoutName,
      page: page,
      pageAt: pageAt,
      onIndexChanged: onIndexChanged,
      onChanged: onChanged,
    ),
  );
}

class _PrLabRatingsSheetContent extends StatefulWidget {
  const _PrLabRatingsSheetContent({
    required this.workoutName,
    required this.page,
    required this.pageAt,
    required this.onIndexChanged,
    required this.onChanged,
  });

  final String workoutName;
  final PrLabRatingsPage page;
  final PrLabRatingsPage? Function(int index) pageAt;
  final ValueChanged<int> onIndexChanged;
  final void Function(int index, PrLabRatings ratings) onChanged;

  @override
  State<_PrLabRatingsSheetContent> createState() =>
      _PrLabRatingsSheetContentState();
}

class _PrLabRatingsSheetContentState extends State<_PrLabRatingsSheetContent> {
  late PrLabRatingsPage _page = widget.page;
  late PrLabRatings _ratings = _page.ratings;
  late final _preCtrl = TextEditingController(text: _page.ratings.preNotes);
  late final _postCtrl = TextEditingController(text: _page.ratings.postNotes);

  @override
  void dispose() {
    _preCtrl.dispose();
    _postCtrl.dispose();
    super.dispose();
  }

  void _update(PrLabRatings next) {
    setState(() => _ratings = next);
    widget.onChanged(_page.index, next);
  }

  /// Same rule as the session viewmodel's rating setters: tapping the star
  /// that is already selected clears the rating.
  int? _toggled(int? current, int n) => current == n ? null : n;

  /// Steps the date bar: +1 is the previous workout (older), -1 the next one
  /// (newer). The stage behind follows, so closing the sheet never leaves
  /// the card naming a different session than the ratings just read.
  void _walk(int delta) {
    final next = widget.pageAt(_page.index + delta);
    if (next == null) return;
    setState(() {
      _page = next;
      _ratings = next.ratings;
    });
    // Each session keeps its own notes: the fields are reseeded from the
    // answers the date bar just walked onto, not left holding the last one.
    _seed(_preCtrl, next.ratings.preNotes);
    _seed(_postCtrl, next.ratings.postNotes);
    widget.onIndexChanged(next.index);
  }

  void _seed(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('pr-lab-ratings-sheet'),
      child: ConstrainedBox(
        // Two bookends plus the date bar can outgrow the screen; the sheet
        // stays under a ceiling and scrolls its body instead.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The workout the answers belong to, as an eyebrow
                        // over the title — the lab sheets' shared header
                        // recipe. The date moved into the bar below, where
                        // it can be stepped (2026-10-22).
                        Text(
                          widget.workoutName.toUpperCase(),
                          key: const ValueKey('pr-lab-ratings-workout'),
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.caption,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'Session Ratings',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlassButton(
                    key: const ValueKey('pr-lab-ratings-close'),
                    label: '',
                    icon: Icons.close,
                    semanticsLabel: 'Close ratings',
                    compact: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(
                        key: const ValueKey('pr-lab-ratings-pre'),
                        ratingKey: const ValueKey('pr-lab-pre-rating'),
                        notesKey: const ValueKey('pr-lab-pre-notes'),
                        label: 'PRE-WORKOUT',
                        question: "How well do you think you're going to do",
                        notesLabel: 'Why do you feel that way',
                        feeling: _ratings.preFeeling,
                        notes: _ratings.preNotes,
                        controller: _preCtrl,
                        placeholder: 'Sleep and eat well?...',
                        emptyNotes: 'No pre-workout notes',
                        onFeelingChanged: (n) => _update(
                          _ratings.withPreFeeling(
                            _toggled(_ratings.preFeeling, n),
                          ),
                        ),
                        onNotesChanged: (v) =>
                            _update(_ratings.withPreNotes(v)),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _section(
                        key: const ValueKey('pr-lab-ratings-post'),
                        ratingKey: const ValueKey('pr-lab-post-rating'),
                        notesKey: const ValueKey('pr-lab-post-notes'),
                        label: 'POST-WORKOUT',
                        question: 'How well did you do this session',
                        notesLabel: 'What could have made this session better',
                        feeling: _ratings.postFeeling,
                        notes: _ratings.postNotes,
                        controller: _postCtrl,
                        placeholder: 'What went well? What would you change?',
                        emptyNotes: 'No post-workout notes',
                        onFeelingChanged: (n) => _update(
                          _ratings.withPostFeeling(
                            _toggled(_ratings.postFeeling, n),
                          ),
                        ),
                        onNotesChanged: (v) =>
                            _update(_ratings.withPostNotes(v)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // The same date changer the stage carries at its floor: the
              // sheet can walk the exercise's sessions without closing, and
              // the stage follows so the two never disagree (2026-10-22).
              PrLabDateBar(
                keys: PrLabDateBarKeys.ratings,
                isToday: _page.isToday,
                date: _page.date,
                canGoOlder: _page.canGoOlder,
                canGoNewer: _page.canGoNewer,
                onOlder: () => _walk(1),
                onNewer: () => _walk(-1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One bookend in its own panel, drawn with the shared `SessionBookend`'s
  /// composition: the label, the question, the stars, then the notes under
  /// their own label. The panel is a bare outline — no fill, just a rim — so
  /// the two halves read as two groups without a second ground stacking on
  /// the sheet's (2026-10-22). It wears [ContainerTone.outlineBright], not
  /// the house [ContainerTone.outline]: the sheet's ground is `surface`, one
  /// step off `border`, so the standard hairline is all but invisible here —
  /// the same reason the review add tile steps up (2026-10-22).
  ///
  /// Read-only passes null callbacks, so the stars go inert and the notes
  /// become a readout — the same switch the production widget makes.
  Widget _section({
    Key? key,
    required Key ratingKey,
    required Key notesKey,
    required String label,
    required String question,
    required String notesLabel,
    required int? feeling,
    required String notes,
    required TextEditingController controller,
    required String placeholder,
    required String emptyNotes,
    required ValueChanged<int> onFeelingChanged,
    required ValueChanged<String> onNotesChanged,
  }) {
    final editable = _page.editable;
    return LambdaContainer(
      key: key,
      // Transparent fill, the floating layer's brighter rim: on the sheet's
      // surface the house hairline (#383838 on #2E2E2E) is a 10/255 step.
      tone: ContainerTone.outlineBright,
      radius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          question,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FeelingRating(
          key: ratingKey,
          value: feeling,
          onChanged: editable ? onFeelingChanged : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          notesLabel,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (editable)
          LambdaInput(
            key: notesKey,
            controller: controller,
            placeholder: placeholder,
            minLines: 2,
            maxLines: 6,
            // The panel is only an outline, so the sheet's surface is the
            // ground; `elevated` lifts the field one tier above it — the
            // text-box rule (2026-10-22).
            elevated: true,
            onChanged: onNotesChanged,
          )
        else if (notes.trim().isNotEmpty)
          LambdaReadout(key: notesKey, value: notes)
        else
          Text(
            emptyNotes,
            key: notesKey,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
