import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../exercises/view/exercise_hub_screen.dart';
import '../../logs/view/logs_screen.dart';
import '../../logs/view/session_detail_screen.dart';
import '../model/acting_identity.dart';

/// The coach's two tabs — Session and Library — and nothing else (2026-10-28).
///
/// A two-item bar of its own, drawn outside the main tab shell: the coach-mode
/// page is pushed over the shell, and a page that draws its own bar lives
/// outside it (the `/nav-bar-demo` precedent). The bar's items are the main
/// bar's first two, element for element, so the two surfaces read as one app.
const coachModeNavItems = [
  ScrollShrinkNavItem(
    icon: Icons.play_circle_outline,
    activeIcon: Icons.play_circle,
    label: 'Session',
  ),
  ScrollShrinkNavItem(
    icon: Icons.local_library_outlined,
    activeIcon: Icons.local_library,
    label: 'Library',
  ),
];

/// Coach mode: the athlete's Session and Library as if they were signed in
/// (2026-10-28). Phase 1 is browse-only — the athlete's logs, records and
/// library lists, with every write and delete hidden. The identity is scoped
/// to this subtree ([CoachModeScope]), so the coach's own tabs underneath keep
/// resolving their real user.
class CoachModeScreen extends StatefulWidget {
  const CoachModeScreen({
    super.key,
    required this.athleteId,
    required this.athleteName,
  });

  final String athleteId;
  final String athleteName;

  @override
  State<CoachModeScreen> createState() => _CoachModeScreenState();
}

class _CoachModeScreenState extends State<CoachModeScreen> {
  int _tab = 0;

  /// The Library is built on first visit and kept mounted afterwards: the
  /// Session tab is the landing page, and mounting both at once reads the
  /// athlete's whole catalog, history and library before anything is shown.
  bool _libraryVisited = false;

  String get _authUserId => Supabase.instance.client.auth.currentUser!.id;

  ActingIdentity get _identity => ActingIdentity(
    authUserId: _authUserId,
    ownerUserId: widget.athleteId,
    createdByUserId: _authUserId,
    ownerName: widget.athleteName,
  );

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
      if (index == 1) _libraryVisited = true;
    });
  }

  void _exit() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/profile/coach');
    }
  }

  /// The bar's exit, from a record pushed over the shell: close the record,
  /// then leave coach mode once the stack has settled.
  void _exitFromRecord() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _exit();
    });
  }

  /// A record from the athlete's logs: the viewer, read-only, wearing the
  /// coach-mode two-tab bar. Its bar taps return here and pick the tab.
  void _openRecord(String sessionId) {
    final identity = _identity;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachModeScope(
          identity: identity,
          child: SessionDetailScreen(
            sessionId: sessionId,
            userId: widget.athleteId,
            readOnly: true,
            canCoach: true,
            navItems: coachModeNavItems,
            navIndex: 0,
            navTrailing: CoachModeIdentity(
              name: widget.athleteName,
              onExit: _exitFromRecord,
            ),
            onNavTap: (i) {
              Navigator.of(context).pop();
              _selectTab(i);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CoachModeScope(
      identity: _identity,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: ScrollShrinkNavBar(
          currentIndex: _tab,
          onTap: _selectTab,
          items: coachModeNavItems,
          trailing: CoachModeIdentity(
            name: widget.athleteName,
            onExit: _exit,
          ),
          child: IndexedStack(
            index: _tab,
            children: [
              LogsScreen(
                userId: widget.athleteId,
                readOnly: true,
                headerTitle: 'Training Logs',
                emptyMessage: 'No sessions yet',
                emptyHint:
                    '${widget.athleteName} has not logged a session yet.',
                onOpenSession: _openRecord,
              ),
              // Built on first visit, kept mounted: switching back to Session
              // must not throw the library away, and switching to Library the
              // first time is the only moment it loads.
              _libraryVisited
                  ? ExerciseHubScreen(
                      userId: widget.athleteId,
                      readOnly: true,
                      showReviews: false,
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar's right half (2026-10-28): `COACHING` over the athlete's name, and
/// the way out.
///
/// The banner that used to carry this spent a whole storey above the bar; the
/// identity belongs in the bar itself, beside the tabs, with the exit control
/// as its trailing glyph. The eyebrow is the app's mono micro-label; the name
/// is one ellipsized line.
class CoachModeIdentity extends StatelessWidget {
  const CoachModeIdentity({
    super.key,
    required this.name,
    required this.onExit,
  });

  final String name;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        // The half's two contents — the identity and the way out — share it
        // evenly: equal air at the divider, between them and at the trailing
        // edge (2026-10-28).
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COACHING',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          HeaderIconButton(
            // A chevron, not a door: the bar's trailing edge is where this
            // app leaves a place from, and the glyph says "on, out of here"
            // without borrowing the destructive vocabulary (2026-10-28).
            icon: Icons.chevron_right,
            semanticsLabel: 'Exit coach mode',
            glyphSize: 22,
            onPressed: onExit,
          ),
        ],
      ),
    );
  }
}
