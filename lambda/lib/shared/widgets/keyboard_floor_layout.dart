import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A page with a floor that keeps its place under the keyboard (2026-10-25).
///
/// The floor — the session's date bar and PR/notes tiles, the viewer's copy of
/// the same bar — stands at the screen's bottom where the design puts it, and
/// the keyboard paints over it instead of lifting it. The page above it is the
/// only thing the keyboard moves: its box ends at the keyboard's top, so a
/// focused field is revealed above the keyboard rather than behind it.
///
/// The page's HEIGHT is what does that job, not a scroll padding.
/// [EditableText] reveals a caret inside the viewport it can see, and a
/// viewport still running under the keyboard is a viewport that thinks the
/// caret is visible. Padding the content only adds room to scroll to.
///
/// The floor is laid out FIRST, so its own height is known when the page's
/// height is decided. That is what keeps this exact: the keyboard only eats
/// into the page once it has painted past the floor's band, and the page never
/// reserves a band of empty page where the floor used to be. The usual
/// "shrink by the whole keyboard inset" recipe cannot know that, and gives up
/// the floor's height twice — half the visible page, on a phone.
///
/// The caller's scaffold must opt out of resizing
/// (`resizeToAvoidBottomInset: false`), or the body's own MediaQuery would
/// have the bottom viewInsets stripped before this widget could read them.
class KeyboardFloorLayout extends StatelessWidget {
  const KeyboardFloorLayout({
    super.key,
    required this.floor,
    required this.page,
  });

  /// Pinned to the screen's bottom. The keyboard paints over it.
  final Widget floor;

  /// The page above the floor — given exactly the height the keyboard leaves.
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _KeyboardFloorDelegate(
        keyboard: MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        LayoutId(id: _Slot.floor, child: floor),
        LayoutId(id: _Slot.page, child: page),
      ],
    );
  }
}

enum _Slot { floor, page }

class _KeyboardFloorDelegate extends MultiChildLayoutDelegate {
  _KeyboardFloorDelegate({required this.keyboard});

  /// The keyboard's height, in logical pixels (`viewInsets.bottom`).
  final double keyboard;

  @override
  void performLayout(Size size) {
    // The floor first: the page's height is computed from what it measures.
    final floorSize = layoutChild(
      _Slot.floor,
      BoxConstraints.tightFor(width: size.width),
    );
    positionChild(
      _Slot.floor,
      Offset(0, math.max(0, size.height - floorSize.height)),
    );

    // The page ends where the floor begins, less whatever part of the
    // keyboard reaches above the floor's band. A keyboard shorter than the
    // floor moves nothing: it is entirely behind the floor already.
    final coveredByKeyboard = math.max(0.0, keyboard - floorSize.height);
    layoutChild(
      _Slot.page,
      BoxConstraints.tightFor(
        width: size.width,
        height: math.max(0, size.height - floorSize.height - coveredByKeyboard),
      ),
    );
    positionChild(_Slot.page, Offset.zero);
  }

  @override
  bool shouldRelayout(_KeyboardFloorDelegate oldDelegate) =>
      keyboard != oldDelegate.keyboard;
}
