import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import './container_styles.dart';

/// The session floor's control size (2026-10-22) — one row of 48px squares:
/// undo, redo, the trash, the ratings pencil — and the height the stats tiles
/// stand at beside them. The PR Lab's bar recipe, carried into production so
/// the two floors (live and viewed) read at the nav bar's scale.
const double kSessionBarControlSize = 48;

/// One square control of a session bar (2026-10-22): the undo/redo boxes'
/// recipe, named so the pencil and the trash draw from the same one.
///
/// The bar's controls are a row of equal squares — 48 at the session floor's
/// height with a 24px glyph (the nav bar's own icon size, the PR Lab's
/// recipe since 2026-10-21), 32/16 compact where the control lives in a page
/// header or a toolbar rather than the floor — wearing the glass treatment
/// when live and a transparent hairline when not. A disabled control still
/// claims its tap: a dead spot in a bar is a hole in the layout.
///
/// [color] is what the control means: neutral chrome is primary (undo, redo,
/// trash), a door to session content is [AppColors.accent] (the ratings
/// pencil) — the same accent the tiles beside it wear.
///
/// The glyph is the control; the word travels as [semanticsLabel] (tooltip
/// and screen-reader label), which is what makes an icon-only button legal
/// here — the glyph-or-word rule is frontend-design §5.
class BarIconButton extends StatelessWidget {
  const BarIconButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onPressed,
    this.enabled = true,
    this.compact = false,
    this.color,
  });

  final IconData icon;
  final String semanticsLabel;

  /// The tap. Only fires while [enabled]; a disabled button swallows it.
  final VoidCallback onPressed;

  final bool enabled;
  final bool compact;

  /// The glass tint and the glyph ink while live. Null (the default) is
  /// neutral chrome; the session floors pass the accent for the ratings
  /// pencil.
  final Color? color;

  double get _size => compact ? 32 : kSessionBarControlSize;
  double get _iconSize => compact ? 16 : 24;

  /// The floor control's 8 corner; a compact header control keeps its
  /// near-square 2.
  double get _radius => compact ? AppRadius.md - 6 : AppRadius.md;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : () {},
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: enabled
              ? glassBox(effectiveColor, radius: _radius)
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Icon(
            icon,
            size: _iconSize,
            color: enabled ? effectiveColor : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
