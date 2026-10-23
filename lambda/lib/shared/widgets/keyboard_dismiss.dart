import 'package:flutter/material.dart';

/// Dismisses the keyboard when a tap lands on empty space.
///
/// Wired once, at the app root (`lib/app.dart`), so every text field in the
/// app — the shared text boxes, the set grid's raw cells, and any field added
/// later — gets the behavior with no per-field wiring. The framework's own
/// `EditableTextTapOutsideIntent` deliberately does nothing for touch on
/// mobile, so without this a field's keyboard could only be lowered by
/// opening a sheet or leaving the screen (2026-10-20).
///
/// A tap that operates a control is not empty space: the control wins the
/// gesture arena (it is deeper in the tree) and its action runs with the
/// keyboard untouched. A tap on another text field likewise wins and transfers
/// focus directly — the old field never takes a trip through "no focus", so
/// the keyboard does not blink between adjacent cells. Drags never count as
/// taps, so scrolling a page while typing does not dismiss.
///
/// `excludeFromSemantics` is deliberate: dismissal is a convenience gesture,
/// not an accessibility affordance, and a root handler must not become a
/// full-screen tappable semantics node for VoiceOver.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// Dismisses the keyboard when the user scrolls.
///
/// Opt-in per screen — today only the profile page uses it. The session page
/// deliberately does not: scrolling to read a later set must not lower the
/// keyboard (2026-10-20, moved here from the profile screen).
class KeyboardDismissOnScroll extends StatelessWidget {
  const KeyboardDismissOnScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        // Only user drags dismiss the keyboard — the framework's own
        // ensureVisible scroll (revealing a focused field above the
        // keyboard) is programmatic, has null dragDetails, and must not
        // steal focus from the field being edited.
        if (notification.dragDetails == null) return false;
        FocusScope.of(context).unfocus();
        return false;
      },
      child: child,
    );
  }
}
