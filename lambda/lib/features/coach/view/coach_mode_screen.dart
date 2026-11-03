import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../data/models/custom_exercise.dart';
import '../../exercises/view/exercise_detail_screen.dart';
import '../../exercises/view/exercise_hub_screen.dart';
import '../../logs/view/session_detail_screen.dart';
import '../../session/view/session_screen.dart';
import '../../session/viewmodel/session_viewmodel.dart';
import '../model/acting_identity.dart';

/// The coach's two tabs — Session and Library — and nothing else (2026-10-28).
///
/// A two-item bar of its own, drawn outside the main tab shell: the coach-mode
/// page is pushed over the shell, and a page that draws its own bar lives
/// outside it (the `/nav-bar-demo` precedent). The bar's items are the main
/// bar's first two, element for element, so the two surfaces read as one app.
const coachModeNavItems = [
  ScrollShrinkNavItem(
    icon: LucideIcons.circlePlay,
    activeIcon: LucideIcons.circlePlay,
    label: 'Session',
  ),
  ScrollShrinkNavItem(
    icon: LucideIcons.library,
    activeIcon: LucideIcons.library,
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

  /// The athlete's session VM, owned by the shell for as long as coach mode
  /// is open (2026-10-28). The Session tab is the real wizard — start, log,
  /// end — with `canDelete: false`, so its removals and cancel are refused.
  late final SessionViewModel _sessionVm;

  /// Re-tapping Session inside coach mode is a wizard re-tap — a local
  /// signal, never the main shell's global one.
  final _reselect = ValueNotifier<int>(0);

  String get _authUserId => Supabase.instance.client.auth.currentUser!.id;

  ActingIdentity get _identity => ActingIdentity(
    authUserId: _authUserId,
    ownerUserId: widget.athleteId,
    createdByUserId: _authUserId,
    ownerName: widget.athleteName,
  );

  @override
  void initState() {
    super.initState();
    _sessionVm = SessionViewModel(
      userId: widget.athleteId,
      canDelete: false,
    );
  }

  @override
  void dispose() {
    _sessionVm.dispose();
    _reselect.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _tab) {
      // Re-tapping Session is the wizard's own re-tap (2026-10-23) — inside
      // coach mode it must not reach the main shell's signal.
      if (index == 0) _reselect.value++;
      return;
    }
    setState(() {
      _tab = index;
      if (index == 1) _libraryVisited = true;
    });
  }

  void _exit() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // The roster lives in the Social tab's Coach panel (2026-10-29); the
      // hub stays mounted under this page, so its tab survives the landing.
      context.go('/friends');
    }
  }

  /// The way out, standing to the left of the tabs (2026-10-28): a left
  /// chevron at the bar's leading edge.
  Widget _exitButton(VoidCallback onExit) => HeaderIconButton(
    icon: LucideIcons.chevronLeft,
    semanticsLabel: 'Exit coach mode',
    glyphSize: 22,
    onPressed: onExit,
  );

  /// The bar's exit, from a record pushed over the shell: close the record,
  /// then leave coach mode once the stack has settled.
  void _exitFromRecord() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _exit();
    });
  }

  /// An exercise from her library: the detail scoped to her — her history,
  /// notes and PRs — with rename but no delete. Pushed over the shell like
  /// the workout editor, so it never escapes into the coach's own library
  /// (2026-10-28).
  void _openExercise(CustomExercise exercise) {
    final identity = _identity;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachModeScope(
          identity: identity,
          child: ExerciseDetailScreen(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.name,
            userId: widget.athleteId,
            canDelete: false,
            // Rename only what this coach created; the PR-axis settings are
            // never a coach write (2026-10-29).
            canEdit: exercise.createdByUserId != null,
            canEditViewSettings: false,
          ),
        ),
      ),
    );
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
            // Her records are read-only to the coach (2026-10-29): the
            // server only lets a coach edit rows they created, and a session
            // she logged is hers. Coach-logged sessions stay read-only here
            // for now — the next pass can open the ones this coach created.
            readOnly: true,
            canCoach: true,
            navItems: coachModeNavItems,
            navIndex: 0,
            navLeading: _exitButton(_exitFromRecord),
            navTrailing: CoachModeIdentity(name: widget.athleteName),
            viewerId: _authUserId,
            canDelete: false,
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
        // The Session tab pins its floor the way the main shell pins
        // `/session`; the Library lifts for the keyboard the way `/exercises`
        // does (2026-10-28).
        resizeToAvoidBottomInset: _tab != 0,
        body: ScrollShrinkNavBar(
          currentIndex: _tab,
          onTap: _selectTab,
          items: coachModeNavItems,
          leading: _exitButton(_exit),
          trailing: CoachModeIdentity(name: widget.athleteName),
          child: IndexedStack(
            index: _tab,
            children: [
              // The real wizard, scoped to the athlete (2026-10-28): start,
              // log, end — no delete. Its shell signals are off; coach mode
              // owns its own reselect signal and must never touch the main
              // tab's notice.
              SessionScreen(
                viewModel: _sessionVm,
                sessionShellSignals: false,
                reselectSignal: _reselect,
                openRecord: _openRecord,
              ),
              // Built on first visit, kept mounted: switching back to Session
              // must not throw the library away, and switching to Library the
              // first time is the only moment it loads.
              _libraryVisited
                  ? ExerciseHubScreen(
                      userId: widget.athleteId,
                      // Phase 3: the coach creates and edits as her; delete
                      // stays off (2026-10-28). Phase 4: her completed review
                      // records browse read-only.
                      readOnly: false,
                      canDelete: false,
                      showReviews: true,
                      openExercise: _openExercise,
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
  });

  final String name;

  @override
  Widget build(BuildContext context) {
    // The right half holds one block — the way out moved to the leading
    // edge — so the identity sits in the middle of its half: the role's glyph
    // beside `COACHING` over the name (2026-10-28). The glyph is decorative;
    // the words are what a screen reader reads.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
          ],
        ),
      ),
    );
  }
}
