import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/styles/app_radius.dart';

/// One action button exposed in a [SwipeActions] drawer: an icon in a
/// **circle**, the way Apple Notes draws a swipe (2026-10-23 — promoted from
/// the PR Lab, where it was designed). Icon only — the glyph alone is the
/// reading; a label under it read as clutter the user asked to drop
/// (2026-10-13).
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;

  /// The circle's fill — a solid token, never an alpha. The drawer carries no
  /// opacity anywhere; the card in front is what hides a resting action.
  final Color color;

  /// The glyph's ink on the filled circle: `AppColors.dangerText` over
  /// `danger`, `AppColors.accentText` over `accent` (dark wherever the accent
  /// is bright), and `AppColors.bg` over the cream `primary`, where white
  /// would disappear into the fill.
  final Color foreground;

  final VoidCallback onTap;
}

/// The width one action claims in the drawer. Circles float inside their
/// slot; the slot is what the swipe measures, so the drawer's travel is the
/// same whatever the circle's size. 52 puts 12 between neighbouring 40
/// circles — 64 left 24, which read as separate controls rather than one
/// cluster of buttons (2026-10-22, the PR Lab).
const double _slotWidth = 52;

/// The circle's ceiling. Shorter rows shrink it — an action is never taller
/// than the row it belongs to.
const double _maxCircle = 40;

/// Wraps [child] with a left-swipe-to-reveal action drawer drawn the way
/// Apple Notes draws one (2026-10-23 — promoted from the PR Lab; beforehand
/// this widget drew solid full-height blocks that faded in with the swipe).
///
/// Each action is a filled circle on the page's own ground, and the circles
/// **scale from zero one at a time** as their slot is uncovered — the
/// trailing action first, then the one before it, each arriving exactly as
/// the card clears its place.
///
/// Nothing fades. The old drawer wrapped every button in an `Opacity` and
/// filled each slot with a solid block, so a partial swipe read as a
/// rectangle sliding out from under the row rather than as buttons arriving.
/// Here the drawer paints at full strength from the first pixel; what hides
/// an action at rest is the opaque card in front of it — and the scale, which
/// is zero until the swipe uncovers the slot.
///
/// Mechanics: release past 50 % or a fast-enough flick snaps fully open;
/// otherwise it closes; a tap on the card closes it when open; a tap on an
/// action closes the drawer and fires it.
///
/// Two rules came over with the circle (2026-10-22, the PR Lab):
///
/// * **One drawer at a time, app-wide.** Opening a drawer closes whichever
///   was open — the notes sheet's rows and the set rows share the rule.
/// * **A tap anywhere else puts the row back.** While a drawer is open, any
///   tap on the screen that is not on its action circles closes it — another
///   row, a field inside the open row, the page around them. The test is a
///   tap (a pointer that went down and up without travelling past the touch
///   slop), so the drag that opened the drawer, and the drag that adjusts
///   it, never trip it.
///
/// **The clip radius must be the child's own** — a larger radius cuts more of
/// the corner away than the child paints, shaving the child's rounded border
/// down to its straight runs (the goal card's green outline turned up with
/// open corners that way, 2026-10-20). Defaults to [AppRadius.lg] (12), the
/// `AppCard` radius; a child built at [AppRadius.md] (8) — set rows, goal
/// cards — passes its own.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.borderRadius = AppRadius.lg,
  });

  final Widget child;
  final List<SwipeAction> actions;

  /// Clip radius for the whole widget — keeps the circles from showing
  /// through the child's rounded corners.
  final double borderRadius;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  /// The one drawer currently open — the constraint lives here, not in the
  /// screens, so every row obeys it without any wiring (2026-10-22).
  static _SwipeActionsState? _openDrawer;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 0,
  );

  /// Tear-off held in a field: `addGlobalRoute` and `removeGlobalRoute` must
  /// receive the same route, and instance-method tear-offs are only equal by
  /// value, which is too subtle to lean on.
  late final PointerRoute _pointerRoute = _routePointer;

  bool _watchingPointers = false;
  Offset? _downAt;
  bool _moved = false;

  double get _drawerWidth => widget.actions.length * _slotWidth;

  @override
  void initState() {
    super.initState();
    // Dismissed = back at rest by any route (animation, drag returned home),
    // which is the one place that hands the "open drawer" slot back.
    _ctrl.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _deactivate();
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _deactivate();
  }

  /// Claims the one-open-drawer slot: closes whatever was open, and starts
  /// listening for the tap that will put this row back.
  void _activate() {
    if (_openDrawer == this) return;
    final previous = _openDrawer;
    _openDrawer = this;
    if (!_watchingPointers) {
      _watchingPointers = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerRoute);
    }
    previous?._close();
  }

  void _deactivate() {
    if (identical(_openDrawer, this)) _openDrawer = null;
    if (_watchingPointers) {
      _watchingPointers = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerRoute);
    }
    _downAt = null;
    _moved = false;
  }

  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);

  // ---------------------------------------------------------------------------
  // Gesture handlers
  // ---------------------------------------------------------------------------

  /// Global pointer feed while this drawer is open: closes the drawer on a
  /// tap anywhere that is not one of its action circles.
  ///
  /// Only a **tap** counts — down and up without moving past [kTouchSlop] —
  /// so the drag that opened the drawer (whose pointer went down before the
  /// drawer was open, or which travels) and any later adjustment never close
  /// it from under the finger.
  void _routePointer(PointerEvent event) {
    if (!mounted || _ctrl.value == 0) return;
    if (event is PointerDownEvent) {
      _downAt = event.position;
      _moved = false;
    } else if (event is PointerMoveEvent) {
      final downAt = _downAt;
      if (downAt != null && (event.position - downAt).distance > kTouchSlop) {
        _moved = true;
      }
    } else if (event is PointerUpEvent) {
      final downAt = _downAt;
      _downAt = null;
      // The swipe that opened this drawer released a pointer that went down
      // while it was still closed: no down recorded, nothing to judge.
      if (downAt == null || _moved) return;
      // On an action circle the slot's own tap handler closes the drawer and
      // fires the action — closing here too would race it for no gain.
      if (!_isOverActions(event.position)) _close();
    } else if (event is PointerCancelEvent) {
      _downAt = null;
      _moved = false;
    }
  }

  /// Whether [globalPosition] falls on the strip the action circles claim.
  /// The strip does not move — only the card in front of it does — so the
  /// widget's own box is the right frame however far the swipe has opened.
  bool _isOverActions(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final local = box.globalToLocal(globalPosition);
    final stripLeft = box.size.width - _drawerWidth;
    return local.dx >= stripLeft &&
        local.dx <= box.size.width &&
        local.dy >= 0 &&
        local.dy <= box.size.height;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.actions.isEmpty) return;
    _ctrl.value = (_ctrl.value - details.delta.dx / _drawerWidth).clamp(
      0.0,
      1.0,
    );
    // Leaving rest is the moment this drawer takes the slot — the card under
    // the finger moves at once, and any other open drawer closes with it.
    if (_ctrl.value > 0) _activate();
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      _activate();
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else if (velocity > 300) {
      _close();
    } else if (_ctrl.value > 0.5) {
      _activate();
      _ctrl.animateTo(1, curve: Curves.easeOut);
    } else {
      _close();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // One clip on the whole widget keeps every layer inside the child's
        // rounded corners — without it the circles bleed through the card's
        // corners when the drawer is open.
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Stack(
            children: [
              // ── Action circles (behind the card) ─────────────────────
              Positioned.fill(child: _actions()),

              // ── Card (slides as a unit) ──────────────────────────────
              Transform.translate(
                offset: Offset(-_ctrl.value * _drawerWidth, 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: _handleDragUpdate,
                  onHorizontalDragEnd: _handleDragEnd,
                  onTap: _ctrl.value > 0 ? _close : null,
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The drawer's actions, trailing-aligned. The circle sizes itself to the
  /// row (a 52pt set row draws 40pt circles; a short row draws smaller ones)
  /// so an action can never outgrow the surface revealing it.
  Widget _actions() {
    final count = widget.actions.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final circle = (constraints.maxHeight - 8).clamp(16.0, _maxCircle);
        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < count; i++) _action(i, circle)],
          ),
        );
      },
    );
  }

  /// Slot [i]'s circle, scaled by how much of its slot the card has cleared.
  ///
  /// The drawer opens from the row's trailing edge, so slot n-1 is uncovered
  /// by the first slot-width of travel, n-2 by the second, and so on. Driving
  /// each scale off its own slot's reveal is what makes the icons arrive one
  /// at a time — and what seats them in list order once fully open. Formula
  /// is in slots, not pixels, so a one-action drawer (the history viewer's
  /// Note) behaves the same as a three-action one.
  Widget _action(int i, double circle) {
    final count = widget.actions.length;
    final action = widget.actions[i];
    final uncovered = (_ctrl.value * count - (count - 1 - i)).clamp(0.0, 1.0);
    final scale = Curves.easeOutCubic.transform(uncovered);
    return SizedBox(
      width: _slotWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _close();
          action.onTap();
        },
        child: Center(
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: circle,
              height: circle,
              decoration: BoxDecoration(
                color: action.color,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              // Half the circle: the 40 circle keeps the old drawer's 20pt
              // glyph, and a shrunk circle's glyph shrinks with it.
              child: Icon(
                action.icon,
                size: circle * 0.5,
                color: action.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
