import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/lambda_readout.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/segmented_control.dart';

/// DEV LAB — the read/edit visual language study (2026-10-28).
///
/// The ratings sheet flips a record between its stored answers and its
/// drafts, and today the stars and the text boxes barely change: a mode only
/// the box announces is no signal at all. This page draws the same
/// PRE-WORKOUT section in both modes under one rule per option, so the rule
/// can be felt before anything ships:
///
/// - **Today** — the production widgets as they stand (the size jump fixed).
/// - **A · Frame** — the control grows its frame when it can be written:
///   read is bare text, edit is the familiar bordered field; the stars wear
///   a glass strip only in edit.
/// - **C · Hollow** — one border in both modes, the fill is what the mode
///   changes: the box is literally the field with its background taken out
///   while reading, and the star pill follows the same rule. Nothing in the
///   section moves but the fill — not even the words' position.
///
/// Every piece here is a COPY, per the PR Lab rule: a layout experiment lives
/// in the lab file, never in a shared widget. Ink alone is deliberately not
/// an option — a mode told by tone reads as disabled, and hierarchy in this
/// app comes from size and weight, never opacity.
///
/// **C · Hollow shipped 2026-10-28.** The winning rule moved into the shared
/// widgets (`LambdaReadout` / `LambdaInput` / `FeelingRating`) once, so every
/// surface speaks it — including the "Today" card below, which draws the
/// production widgets and therefore now reads as C. The page stays as the
/// study's record, with A · Frame kept as the road not taken.
class VisualPairingsScreen extends StatelessWidget {
  const VisualPairingsScreen({super.key});

  static const _note = 'Slept 8h. Felt strong on the first sets.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Visual Pairings'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                ScrollShrinkNavBar.contentInset(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _IntroCard(),
                  const SizedBox(height: AppSpacing.lg),
                  _PairingCard(
                    key: const ValueKey('pairing-today'),
                    title: 'Today (now C · Hollow)',
                    rule:
                        'The production widgets as they stand. Since the sweep '
                        'they draw C · Hollow too, so this card and the C card '
                        'below now agree — kept as the pair that shows what '
                        'shipping the rule changed.',
                    sample: _todaySample,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PairingCard(
                    key: const ValueKey('pairing-a'),
                    title: 'A · Frame',
                    rule:
                        'The control grows its frame when it can be written. '
                        'Reading is bare text where the field would be; '
                        'editing draws the box — and the stars wear a glass '
                        'strip only while they take a tap.',
                    sample: _frameSample,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _PairingCard(
                    key: const ValueKey('pairing-c'),
                    title: 'C · Hollow',
                    rule:
                        'The border never moves — only the background tells '
                        'the modes apart. The box is the very field it '
                        'becomes, with the fill taken out while reading, and '
                        'the star pill works the same way.',
                    sample: _hollowSample,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _FootnoteCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SampleBuilder =
    Widget Function(_PairMode mode, TextEditingController notes);

// ── The sample's shared bones ───────────────────────────────────────────────

/// The bookend's own shape, copied from `SessionBookend`: mono eyebrow, the
/// question, the stars, the notes label, the notes box. Each option swaps
/// only the stars and the box inside it.
Widget _bookend({required Widget stars, required Widget box}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      'PRE-WORKOUT',
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.primary,
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    Text(
      "How well do you think you're going to do",
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    stars,
    const SizedBox(height: AppSpacing.sm),
    Text(
      'Why do you feel that way',
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
    const SizedBox(height: 6),
    box,
  ],
);

/// The editable field, exactly as the bookend draws it.
Widget _input(TextEditingController ctrl) => LambdaInput(
  controller: ctrl,
  placeholder: 'Sleep and eat well?\nHydrated?\nGoals today?',
  minLines: 2,
  maxLines: 6,
  elevated: true,
  onChanged: (_) {},
);

/// Bare text where the field would stand — no fill, no stroke, the same
/// padding so the line begins where the field's text does.
Widget _bareBox(String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  child: Text(
    text,
    style: AppFonts.ui(fontSize: AppTextStyles.md, color: AppColors.primary),
  ),
);

/// The app's glass recipe around the star row — primary tint, 26 fill / 77
/// border, pill radius. Option A's "this takes a tap" strip in edit.
Widget _glassStrip(Widget child) => Container(
  padding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  decoration: BoxDecoration(
    color: AppColors.primary.withAlpha(26),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: AppColors.primary.withAlpha(77)),
  ),
  child: child,
);

/// Option C's star pill: the stroke is the mode's constant, only the fill
/// moves — hollow while reading, tinted while editing.
Widget _pill({required Widget child, required bool filled}) => Container(
  padding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  decoration: BoxDecoration(
    color: filled ? AppColors.primary.withAlpha(26) : Colors.transparent,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: AppColors.primary.withAlpha(77)),
  ),
  child: child,
);

/// Option C's box: literally the field, with only its background taken out
/// (2026-10-28). The first cut drew the read side as a separate hollow box
/// and the words shifted between modes; this one wraps the same TextField in
/// both states — held inert while reading — so the fill is the only thing
/// the toggle can move.
Widget _hollowField(TextEditingController ctrl, {required bool filled}) =>
    IgnorePointer(
      ignoring: !filled,
      child: TextField(
        controller: ctrl,
        readOnly: !filled,
        showCursor: filled,
        minLines: 2,
        maxLines: 6,
        style: AppFonts.ui(
          fontSize: AppTextStyles.md,
          color: AppColors.primary,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: filled ? AppColors.surfaceHigh : Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.border),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );

// ── The three rules ─────────────────────────────────────────────────────────

Widget _todaySample(_PairMode mode, TextEditingController notes) {
  final editing = mode == _PairMode.edit;
  return _bookend(
    stars: FeelingRating(value: 4, onChanged: editing ? (_) {} : null),
    box: editing
        ? _input(notes)
        : LambdaReadout(value: VisualPairingsScreen._note),
  );
}

Widget _frameSample(_PairMode mode, TextEditingController notes) {
  final editing = mode == _PairMode.edit;
  final stars = FeelingRating(value: 4, onChanged: editing ? (_) {} : null);
  return _bookend(
    stars: editing ? Center(child: _glassStrip(stars)) : stars,
    box: editing ? _input(notes) : _bareBox(VisualPairingsScreen._note),
  );
}

Widget _hollowSample(_PairMode mode, TextEditingController notes) {
  final editing = mode == _PairMode.edit;
  final stars = FeelingRating(value: 4, onChanged: editing ? (_) {} : null);
  return _bookend(
    stars: Center(
      child: _pill(filled: editing, child: stars),
    ),
    // The read box IS the edit field — same widget, same words, same seat —
    // with the background taken out. The toggle has nothing left to move
    // but the fill.
    box: _hollowField(notes, filled: editing),
  );
}

// ── Furniture ───────────────────────────────────────────────────────────────

enum _PairMode {
  read('READ'),
  edit('EDIT');

  const _PairMode(this.label);
  final String label;
}

/// One option: its name, its one rule, a READ | EDIT switch, and the same
/// section drawn in the mode picked.
class _PairingCard extends StatefulWidget {
  const _PairingCard({
    super.key,
    required this.title,
    required this.rule,
    required this.sample,
  });

  final String title;
  final String rule;
  final _SampleBuilder sample;

  @override
  State<_PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends State<_PairingCard> {
  late final TextEditingController _notes = TextEditingController(
    text: VisualPairingsScreen._note,
  );
  _PairMode _mode = _PairMode.read;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.rule,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedControl<_PairMode>(
            options: [
              for (final m in _PairMode.values)
                SegmentOption(label: m.label, value: m),
            ],
            value: _mode,
            subtle: true,
            onChange: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: AppSpacing.md),
          widget.sample(_mode, _notes),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Read vs edit, one language',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Every card draws the same PRE-WORKOUT section under one rule. '
            'Flip READ | EDIT and watch what moves — the cue has to be the '
            'same everywhere it appears, because the ratings sheet, the '
            'viewer and the planner all flip between these two states. '
            'C · Hollow won and shipped on 2026-10-28; the comparison stays '
            'as the record of why.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ink alone is not on the menu: a mode told by tone reads as '
            'disabled, and this app keeps hierarchy in size and weight.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FootnoteCard extends StatelessWidget {
  const _FootnoteCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Picking one',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Picked: C · Hollow, shipped 2026-10-28. LambdaReadout is the '
            'field with its fill taken out, and FeelingRating\'s pill fills '
            'only while it takes a tap — one rule in the shared widgets, so '
            'every surface speaks it without a per-screen change. The rule '
            'is documented in frontend-design §6; this page is kept as the '
            'record of the decision.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
