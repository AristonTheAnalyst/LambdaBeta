import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import './container_styles.dart';

/// The gap between the trigger's edge and the panel's.
const double _gap = 4;

/// The panel's width. The triggers are compact icon buttons; the labels are
/// not, so the panel sizes itself rather than borrowing the trigger's width
/// (the exercise selector's trick, which would clip these).
const double _panelWidth = 220;

/// The panel never grows past this — four criteria and their padding.
const double _panelMaxHeight = 280;

/// Under this much room the panel flips to the trigger's other side.
const double _minRoom = 140;

/// The app's anchored menu: a small panel hung off its trigger in the
/// Overlay — the toolbar's answer to the now-retired sort/filter sheets
/// (2026-10-10).
///
/// The trigger is the caller's own control — [trigger] wires the `open`
/// callback into it — and the rows are the caller's too: [contentBuilder]
/// draws them and closes the menu through the `dismiss` it is handed. A tap
/// anywhere else lands on this widget's own scrim, which puts the menu away
/// and nothing else: the panel paints above the owning route's barrier
/// (OverlayPortal's own ordering), so a menu opened inside a bottom sheet
/// closes alone and the sheet underneath keeps its state.
///
/// The panel hangs under the trigger, right edges aligned — every toolbar it
/// serves stands its buttons at the row's end — and flips above the trigger
/// when there is no room below, its height clamped to the room that is
/// actually visible (the keyboard's claim subtracted: the review scope sheet
/// lifts for its search fields, and the panel must not hide behind one).
class MenuPopover extends StatefulWidget {
  const MenuPopover({
    super.key,
    required this.trigger,
    required this.contentBuilder,
    this.tone = ContainerTone.surface,
    this.semanticsLabel,
  });

  /// Builds the control the menu hangs from. `open` opens the menu; the
  /// trigger itself sits under the scrim while the menu is up, so it cannot
  /// be tapped into a second panel.
  final Widget Function(BuildContext context, VoidCallback open) trigger;

  /// Builds the panel's rows. `dismiss` puts the menu away — rows that
  /// answer their one question close first, so no answer lands under a
  /// scrim.
  final Widget Function(BuildContext context, VoidCallback dismiss)
      contentBuilder;

  /// The panel's fill: `surface` on the page, `ghost` (surfaceHigh) when the
  /// trigger stands on a `surface` ground — a default sheet — the one-tier-up
  /// rule every container follows.
  final ContainerTone tone;

  /// What the trigger is called, for the screen reader: every current trigger
  /// is an icon with no label of its own.
  final String? semanticsLabel;

  @override
  State<MenuPopover> createState() => _MenuPopoverState();
}

class _MenuPopoverState extends State<MenuPopover> {
  final _triggerKey = GlobalKey();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _open = false;
  bool _opensUp = false;
  double _maxHeight = _panelMaxHeight;

  void _close() {
    _portal.hide();
    if (_open) setState(() => _open = false);
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    _openMenu();
  }

  void _openMenu() {
    // The menu opening is the answer a focused search box was waiting for;
    // leaving the keyboard up would put it where the panel is going (the
    // review scope sheet is the sheet that lifts for one).
    FocusManager.instance.primaryFocus?.unfocus();
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final media = MediaQuery.of(context);
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final triggerBottom = origin.dy + (box?.size.height ?? 0);
    // What is actually visible: subtracting the keyboard's claim is the same
    // answer the sheet gives when it lifts.
    final visibleBottom = media.size.height - media.viewInsets.bottom;
    final below = visibleBottom - triggerBottom - _gap;
    final above = origin.dy - _gap;
    final opensUp = below < _minRoom && above > below;
    setState(() {
      _opensUp = opensUp;
      _maxHeight = (opensUp ? above : below)
          .clamp(_minRoom, _panelMaxHeight)
          .toDouble();
      _open = true;
    });
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => !_open
          ? const SizedBox.shrink()
          : Stack(
              children: [
                // The tap-catcher. It hit-tests before the owning route's
                // barrier, so an outside tap closes the menu alone — the
                // sheet under it never even hears the tap.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                CompositedTransformFollower(
                  link: _link,
                  targetAnchor:
                      _opensUp ? Alignment.topRight : Alignment.bottomRight,
                  followerAnchor:
                      _opensUp ? Alignment.bottomRight : Alignment.topRight,
                  offset: Offset(0, _opensUp ? -_gap : _gap),
                  child: _panel(context),
                ),
              ],
            ),
      child: CompositedTransformTarget(
        key: _triggerKey,
        link: _link,
        child: Semantics(
          button: true,
          label: widget.semanticsLabel,
          child: Builder(
            builder: (context) => widget.trigger(context, _toggle),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: _panelWidth,
      maxWidth: _panelWidth,
      maxHeight: _maxHeight,
    ),
    child: Container(
      // The floating shadow is what stops the panel reading as a dead slab
      // when it opens over a sheet of the same fill.
      decoration: lambdaBox(
        widget.tone,
        radius: AppRadius.md,
      ).copyWith(boxShadow: floatingShadow),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: widget.contentBuilder(context, _close),
      ),
    ),
  );
}

/// One row in a menu that asks "which one": the accent-glass row, ticked —
/// or wearing [trailing] instead, for a row whose answer has a direction.
/// The sort and filter menus are siblings and draw the same control.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// The mark a chosen row wears. Null keeps the tick; the sort menu passes
  /// the direction arrow, which says "chosen" and "which way" in one mark.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        // The glass recipe in the active row's accent — the same
        // selected-state treatment as every other chip in the app.
        decoration: glassBox(active ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accent : AppColors.primary,
                ),
              ),
            ),
            if (active)
              trailing ?? Icon(Icons.check, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
