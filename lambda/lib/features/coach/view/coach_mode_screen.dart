import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/floating_bar.dart';
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
          aboveBar: CoachModeBanner(
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

/// The storey above the bar: whose account is on screen, and the way out.
///
/// It rides `ScrollShrinkNavBar.aboveBar`, so `FloatingBarOverlay` measures it
/// into `contentInset` and both tabs clear it without extra padding.
class CoachModeBanner extends StatelessWidget {
  const CoachModeBanner({super.key, required this.name, required this.onExit});

  final String name;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return FloatingGlass(
      radius: FloatingBar.cornerRadius,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Row(
          children: [
            Icon(
              Icons.sports_outlined,
              size: 16,
              color: AppColors.inkSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$name · coach mode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            HeaderIconButton(
              icon: Icons.close,
              semanticsLabel: 'Exit coach mode',
              glyphSize: 18,
              onPressed: onExit,
            ),
          ],
        ),
      ),
    );
  }
}
