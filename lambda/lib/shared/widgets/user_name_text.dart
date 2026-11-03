import 'package:flutter/material.dart';

/// THE way a user-created name is drawn (2026-10-20).
///
/// Exercise, variation, workout, program, block, goal and review names are all
/// typed by the user, so any of them can be longer than the place it lands. A
/// bare `Text` in a `Row` does not shrink — it overflows the row and paints
/// the yellow-and-black warning over its neighbours, or stretches the card
/// that holds it. Ellipsizing each one by hand is a rule nobody remembers at
/// the fortieth site, so the rule is a widget instead.
///
/// One line by default: a name is an identifier, not prose. Callers that share
/// a `Row` still need an `Expanded`/`Flexible` around it — a `Text` cannot
/// shrink inside a `Row` that hands it unbounded width, ellipsis or not.
///
/// [tooltip] repeats the full value on long-press/hover, for the screens where
/// the name is the thing being *chosen* and a truncated one is not enough to
/// choose by. The recipe is [SessionSetRow]'s variation cell, promoted.
class UserNameText extends StatelessWidget {
  const UserNameText(
    this.value, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.tooltip = false,
    this.textAlign,
  });

  /// The user-typed string. May be anything; this widget makes it fit.
  final String value;

  /// The caller's type style — styles stay per-site, only the fitting rule is
  /// shared.
  final TextStyle style;

  /// Lines before ellipsis. One everywhere a name identifies something; a
  /// caller drawing a name as a heading may allow two.
  final int maxLines;

  /// Repeat the whole value on long-press. Off by default: a tooltip on every
  /// name in a list is noise, and most names fit.
  final bool tooltip;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );

    // An empty message would still claim the long-press gesture, so an empty
    // name draws bare.
    if (!tooltip || value.isEmpty) return text;
    return Tooltip(message: value, child: text);
  }
}
