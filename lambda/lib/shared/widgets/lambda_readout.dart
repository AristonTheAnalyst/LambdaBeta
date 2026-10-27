import 'dart:math' as math;

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
/// while the box can be written, hollow while it only reads.
///
/// The read side therefore reproduces the field's own geometry, not just its
/// font: the outline border's content inset (20 = the decoration's 16 plus
/// the outline's 4pt gap, where `InputDecorator` seats the input), the md
/// type at the field's merged metrics, [minLines] at rest and [maxLines]
/// before the note scrolls inside. **And the hint's height**: a field
/// reserves its placeholder's height even while a value is present
/// (`InputDecorator.maintainHintSize` defaults true), so a pair passes the
/// field's own placeholder as [fieldHint] and the hollow box is never
/// shorter than the field it replaces.
///
/// Text shown rather than written wears this — never a bare `Text` on a
/// card, never a dead field. The past-session viewer's display is the
/// reference; the exercise review note's record state is the same box.
///
/// The empty case is the caller's, in one of three shapes: the box is not
/// drawn (the review note on a snapshot), the surrounding section speaks
/// instead, or [placeholder] answers inside the box — secondary ink in the
/// value's own place, so a record that left no note still shows the box it
/// would have filled.
class LambdaReadout extends StatelessWidget {
  const LambdaReadout({
    super.key,
    this.label,
    required this.value,
    this.placeholder,
    this.fieldHint,
    this.minLines = 2,
    this.maxLines = 6,
  });

  /// The outline field's horizontal content inset: the decoration's 16 plus
  /// the outline border's 4pt gap. `InputDecorator` seats the input at
  /// `contentPadding.start + inputGap`, so the field's words begin 20 in —
  /// the hollow box must put them in the same place.
  static const double _fieldInsetX = 20;

  /// The field's own vertical content padding (`LambdaInput`'s 14).
  static const double _fieldPadV = 14;

  /// Same slot and styling as [LambdaInput.label]; null for a box the
  /// surrounding section already names.
  final String? label;

  final String value;

  /// What the box reads when [value] is blank — `inkSecondary`, like
  /// [LambdaInput]'s own placeholder: readable, but one step down from a
  /// real note. Null leaves a blank box blank.
  final String? placeholder;

  /// The placeholder the paired field draws, when it differs from
  /// [placeholder] — the wizard's prompt beside the record's "no notes"
  /// line, say. A field reserves its hint's height even with a value in it,
  /// so a read/edit pair passes it here and the hollow box is the field's
  /// height in both modes (2026-10-28). Null means [placeholder] is the
  /// field's hint too.
  final String? fieldHint;

  /// The field's own sizing, so a read/edit pair never jumps: the default is
  /// the reference notes box (two lines at rest, six before it scrolls).
  /// A readout standing in for a field with different numbers passes them.
  /// Null [maxLines] grows with the note, exactly like an unbounded field.
  final int minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final isBlank = value.trim().isEmpty;
    final shown = isBlank ? (placeholder ?? value) : value;
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
        LayoutBuilder(
          builder: (context, constraints) {
            // The words wrap at the field's content width, so the two boxes
            // wrap identically — a box measured at the wrong width is a line
            // count the other one does not have.
            final contentWidth = constraints.hasBoundedWidth
                ? math.max(0.0, constraints.maxWidth - _fieldInsetX * 2)
                : double.infinity;
            final lineHeight = _textHeight(context, style, 'M', contentWidth);
            final valueHeight = _textHeight(context, style, shown, contentWidth);
            final hintHeight = fieldHint == null
                ? 0.0
                : _textHeight(context, style, fieldHint!, contentWidth);
            final restHeight = math.max(valueHeight, lineHeight * minLines);
            final visibleHeight = maxLines == null
                ? restHeight
                : math.min(restHeight, lineHeight * maxLines!);
            // The field reserves its hint's height in both modes; the read
            // box is only the field's shape if it does the same.
            final contentHeight = math.max(visibleHeight, hintHeight);
            // The edge is painted OUTSIDE the padding, not by a Container's
            // own decoration: a decoration's border dimensions become extra
            // padding inside a Container, and the field's OutlineInputBorder
            // carries none (2026-10-28).
            return DecoratedBox(
              // The field's edge, no fill: read is edit hollowed.
              decoration: lambdaBox(ContainerTone.outline, radius: AppRadius.md),
              child: Container(
                width: double.infinity,
                height: contentHeight + _fieldPadV * 2,
                padding: const EdgeInsets.symmetric(
                  horizontal: _fieldInsetX,
                  vertical: _fieldPadV,
                ),
                child: SingleChildScrollView(
                  child: Text(shown, style: style),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// The height [text] takes at [maxWidth] in [style], at the ambient text
  /// scale — the same metric the field lays its own lines out with.
  static double _textHeight(
    BuildContext context,
    TextStyle style,
    String text,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
