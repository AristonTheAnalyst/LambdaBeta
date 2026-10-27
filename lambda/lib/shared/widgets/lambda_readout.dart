import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_text_styles.dart';
import './container_styles.dart';

/// THE read-only text box — the display half of [LambdaInput].
///
/// Where an input is where text is written, a readout is where it is read
/// back: the same label above (a note reads under the header it was typed
/// under), then **the very field it stands in for, with its fill taken out**
/// (2026-10-28, the C · Hollow rule). One border in both modes, so what the
/// box takes from the user's eye is nothing; only the fill moves — tinted
/// while the box can be written, hollow while it only reads. The read side
/// therefore reproduces the field's own geometry exactly: 16 × 14 padding,
/// `AppColors.border` hairline at radius 8, `md` primary text at the field's
/// weight, [minLines] at rest and [maxLines] before the note scrolls inside
/// (matching `LambdaInput(minLines:, maxLines:)` for the same box).
///
/// Text shown rather than written wears this — never a bare `Text` on a
/// card, never a dead field. The past-session viewer's display is the
/// reference; the exercise review note's record state is the same box.
///
/// The empty case is the caller's, in one of three shapes: the box is not
/// drawn (the review note on a snapshot), the surrounding section speaks
/// instead (the bookend), or [placeholder] answers inside the box — secondary
/// ink in the value's own place, so a record that left no note still shows
/// the box it would have filled (the review note while Compare is up, where
/// dropping the row mid-flip would move the card under the eye that just
/// tapped it).
class LambdaReadout extends StatelessWidget {
  const LambdaReadout({
    super.key,
    this.label,
    required this.value,
    this.placeholder,
    this.minLines = 2,
    this.maxLines = 6,
  });

  /// Same slot and styling as [LambdaInput.label]; null for a box the
  /// surrounding section already names.
  final String? label;

  final String value;

  /// What the box reads when [value] is blank — `inkSecondary`, like
  /// [LambdaInput]'s own placeholder: readable, but one step down from a
  /// real note. Null leaves a blank box blank.
  final String? placeholder;

  /// The field's own sizing, so a read/edit pair never jumps: the default is
  /// the reference notes box (two lines at rest, six before it scrolls).
  /// A readout standing in for a field with different numbers passes them —
  /// the pair must agree, or the toggle moves the words. Null [maxLines]
  /// grows with the note, exactly like an unbounded field.
  final int minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final isBlank = value.trim().isEmpty;
    // The field's own type: LambdaInput writes at md, w400 — but a TextField
    // merges its style onto the theme's `bodyLarge` (which carries the line
    // height and tracking), so the readout merges exactly the same way. That
    // is what makes the two boxes one geometry, not just one font size.
    final style = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
        .merge(
          AppFonts.ui(
            fontSize: AppTextStyles.md,
            fontWeight: FontWeight.w400,
            color: isBlank && placeholder != null
                ? AppColors.inkSecondary
                : AppColors.primary,
          ),
        );
    // The box is as tall as the field would be for these words: the field's
    // padding plus its line count at this type. Measured, not guessed — the
    // two boxes must land on the same height in both modes.
    final lineHeight = _lineHeight(context, style);
    const padV = 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        // The edge is painted OUTSIDE the padding, not by a Container's own
        // decoration: a decoration's border dimensions become extra padding
        // inside a Container, and the field's OutlineInputBorder carries
        // none — 2px the pair could not afford (2026-10-28).
        DecoratedBox(
          // The field's edge, no fill: read is edit hollowed (2026-10-28).
          decoration: lambdaBox(ContainerTone.outline, radius: AppRadius.md),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              minHeight: padV * 2 + lineHeight * minLines,
              maxHeight: maxLines == null
                  ? double.infinity
                  : padV * 2 + lineHeight * maxLines!,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: padV),
            child: SingleChildScrollView(
              child: Text(
                isBlank ? (placeholder ?? value) : value,
                style: style,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One line of [style] at the ambient text scale — the same metric the
  /// field lays its own lines out with.
  static double _lineHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
