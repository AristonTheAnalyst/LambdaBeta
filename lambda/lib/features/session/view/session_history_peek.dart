import 'package:flutter/material.dart';
import '../../logs/view/session_detail_screen.dart';
import '../../logs/viewmodel/session_detail_viewmodel.dart';

/// The live Training page's history peek (2026-10-22).
///
/// The date bar's steps are **in place** on both session surfaces: the page,
/// its route and its header stay exactly where they are, and the sets under
/// them swap to the record stepped onto. The live page hosts the viewer's own
/// reading ([SessionDetailView]) for that record — the same flat card, the
/// same floor, the same `PREVIOUSLY` date bar — and hands its walk back here:
///
/// - older/newer step through completed records (`SessionDetailViewModel
///   .walkTo` — no spinner, no route, the sets replace);
/// - the newest record's right arrow steps forward onto **today**, which is
///   the live page still mounted underneath — not a navigation.
///
/// The record is read-only by construction: the peek never enters edit mode
/// (only the /logs route's header carries the Edit glyph), so the card greys
/// its write controls exactly as the viewer does in view mode.
class SessionHistoryPeek extends StatelessWidget {
  const SessionHistoryPeek({
    super.key,
    required this.viewModel,
    required this.state,
    required this.onExit,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  /// The newest record's right arrow — back onto today's live sets.
  final VoidCallback onExit;

  void _walkOlder() {
    final id = state.walk?.olderId;
    if (id != null) viewModel.walkTo(id);
  }

  void _walkNewer() {
    final walk = state.walk;
    if (walk == null) return;
    final id = walk.newerId;
    if (id != null) {
      viewModel.walkTo(id);
    } else {
      // The top of the stack: today's live session is this very page.
      onExit();
    }
  }

  @override
  Widget build(BuildContext context) => SessionDetailView(
    viewModel: viewModel,
    state: state,
    onWalkOlder: _walkOlder,
    onWalkNewer: _walkNewer,
  );
}
