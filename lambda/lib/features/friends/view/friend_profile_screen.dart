import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/coach_assignment.dart';
import '../../../data/models/friend.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/lambda_avatar.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../../coach/view/assign_workout_sheet.dart';
import '../../coach/view/coach_activity_sheet.dart';
import '../../coach/view/coach_permissions_sheet.dart';
import '../viewmodel/friend_profile_viewmodel.dart';
import 'friends_screen.dart';

/// One friend's profile (2026-10-30): the page a Social row opens.
///
/// It is the friendship's one home for verbs. The top is who they are — the
/// placeholder picture, their name, and the **COACH** / **CLIENT** pill when
/// an accepted coaching edge connects you. Under it, their training; then
/// coaching (ask, accept, decline, end — either direction, because coaching
/// is a permission that rides on a friendship); then the friendship's own
/// settings (nickname, the note tier); then the way out, removing them.
///
/// All three coaching states are drawn from one edge: accepted (they coach
/// you, or you coach them), pending (either side asked — the other side
/// accepts), none (both asks are offered).
class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    super.key,
    required this.friendId,
    this.initialName,
    this.viewModel,
  });

  final String friendId;

  /// The name the row that opened this page already had, shown until the
  /// friend's row syncs (and on a deep link, until it does).
  final String? initialName;

  /// A caller-supplied state holder (host tests); null builds its own.
  final FriendProfileViewModel? viewModel;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  late final FriendProfileViewModel _vm =
      widget.viewModel ??
      FriendProfileViewModel(
        me: currentUserId(),
        friendId: widget.friendId,
      );

  /// Whether [_vm] is this screen's to dispose.
  late final bool _ownsVm = widget.viewModel == null;

  @override
  void initState() {
    super.initState();
    _vm.start();
  }

  @override
  void dispose() {
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _back() {
    // A host test pumps the page without a router; there is nothing to pop,
    // so the verb is spent rather than asserting.
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (router.canPop()) {
      context.pop();
    } else {
      context.go('/friends');
    }
  }

  // ── Coaching ───────────────────────────────────────────────────────────────

  Future<void> _ask(String name) async {
    final ok = await _vm.requestCoaching();
    if (!mounted) return;
    _toast(
      ok ? 'Asked $name to coach you' : (_vm.state.value.error ?? 'Could not ask.'),
    );
  }

  Future<void> _offer(String name) async {
    final ok = await _vm.offerCoaching();
    if (!mounted) return;
    _toast(
      ok
          ? 'Offered to coach $name'
          : (_vm.state.value.error ?? 'Could not offer.'),
    );
  }

  /// Accepts the pending ask. When the friend OFFERED to coach the caller,
  /// this is the athlete's consent, so the permissions sheet is the accept
  /// step (the same statement the old roster used, 2026-10-29).
  Future<void> _accept(String name, {required bool asAthlete}) async {
    if (asAthlete) {
      final allowed = await showCoachPermissionsSheet(
        context,
        coachName: name,
        accepting: true,
      );
      if (!allowed || !mounted) return;
    }
    final ok = await _vm.acceptCoaching();
    if (!mounted) return;
    if (!ok) {
      _toast(_vm.state.value.error ?? 'Could not accept that.');
    }
  }

  Future<void> _endCoaching(String name, {required bool pending}) async {
    final ok = await _confirm(
      context,
      title: pending ? 'Cancel Request' : 'End Coaching',
      message: pending
          ? 'Withdraw your request? $name will not be asked again.'
          : 'End coaching with $name? They stop seeing your training, and '
                'you stop seeing theirs.',
      confirm: pending ? 'Withdraw' : 'End coaching',
    );
    if (!ok || !mounted) return;
    final done = await _vm.endCoaching();
    if (!mounted) return;
    if (!done) _toast(_vm.state.value.error ?? 'Could not end that.');
  }

  Future<void> _decline() async {
    final ok = await _confirm(
      context,
      title: 'Decline Coaching',
      message: 'Decline the request? Nothing is shared either way.',
      confirm: 'Decline',
    );
    if (!ok || !mounted) return;
    final done = await _vm.endCoaching();
    if (!mounted) return;
    if (!done) _toast(_vm.state.value.error ?? 'Could not decline that.');
  }

  // ── Assignments ────────────────────────────────────────────────────────────

  Future<void> _assign(String name) async {
    final sent = await showAssignWorkoutSheet(
      context,
      vm: _vm,
      athleteName: name,
    );
    if (sent == true && mounted) _toast('Workout sent to $name');
  }

  Future<void> _acceptAssignment(CoachAssignment assignment) async {
    final ok = await _vm.acceptAssignment(assignment);
    if (!mounted) return;
    _toast(
      ok
          ? '${assignment.name} added to your workouts'
          : (_vm.state.value.error ?? 'Could not accept that workout.'),
    );
  }

  Future<void> _declineAssignment(CoachAssignment assignment) async {
    final ok = await _confirm(
      context,
      title: 'Decline Workout',
      message:
          'Decline ${assignment.name}? It stays out of your library, and '
          'your coach is not told why.',
      confirm: 'Decline',
    );
    if (!ok || !mounted) return;
    final done = await _vm.declineAssignment(assignment);
    if (!mounted) return;
    if (!done) _toast(_vm.state.value.error ?? 'Could not decline that.');
  }

  Future<void> _withdrawAssignment(CoachAssignment assignment) async {
    final ok = await _confirm(
      context,
      title: 'Withdraw Workout',
      message:
          "Withdraw ${assignment.name}? They won't see it anymore, and "
          'nothing is left behind.',
      confirm: 'Withdraw',
    );
    if (!ok || !mounted) return;
    final done = await _vm.withdrawAssignment(assignment);
    if (!mounted) return;
    if (!done) _toast(_vm.state.value.error ?? 'Could not withdraw that.');
  }

  // ── The friendship ─────────────────────────────────────────────────────────

  Future<void> _rename(Friend friend) async {
    final result = await showNicknameSheet(context, friend: friend);
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    final saved = await _vm.setNickname(trimmed.isEmpty ? null : trimmed);
    if (!mounted || saved) return;
    _toast(_vm.state.value.error ?? 'Could not save that nickname.');
  }

  Future<void> _privacy(Friend friend) async {
    _vm.clearError();
    await showFriendPrivacySheet(
      context,
      friend: friend,
      onShareNotes: _vm.setShareNotes,
      errorOf: () => _vm.state.value.error,
    );
  }

  Future<void> _unfriend(Friend friend) async {
    final ok = await _confirm(
      context,
      title: 'Remove Friend',
      message:
          'Remove ${friend.displayName} from your friends? '
          'You will not see each other\'s sessions anymore, and any coaching '
          'between you ends.',
      confirm: 'Remove',
    );
    if (!ok || !mounted) return;
    final removed = await _vm.unfriend();
    if (!mounted) return;
    if (!removed) {
      _toast(_vm.state.value.error ?? 'Could not remove that friend.');
      return;
    }
    _back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<FriendProfileState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          final friend = state.friend;
          final name = friend?.displayName ?? widget.initialName ?? 'Friend';
          return Column(
            children: [
              PageHeader(
                title: name,
                left: HeaderIconButton(
                  icon: LucideIcons.arrowLeft,
                  semanticsLabel: 'Back',
                  onPressed: _back,
                ),
              ),
              Expanded(
                child: ListView(
                  // The shell's bar floats over this page, so the last row
                  // has to scroll clear of it.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
                  ),
                  children: [
                    _Identity(name: name, role: friend?.coachingRole),
                    const SizedBox(height: AppSpacing.xl),
                    GlassButton(
                      label: 'View training',
                      icon: LucideIcons.history,
                      solid: true,
                      onPressed: () => context.push(
                        '/friends/${widget.friendId}/logs',
                        extra: name,
                      ),
                    ),
                    if (state.incomingAssignments.isNotEmpty ||
                        state.sentAssignments.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      const _SectionLabel('WORKOUTS'),
                      const SizedBox(height: AppSpacing.sm),
                      for (final assignment in state.incomingAssignments) ...[
                        _IncomingAssignmentCard(
                          assignment: assignment,
                          coachName: name,
                          busy: state.isBusy,
                          onAccept: () => _acceptAssignment(assignment),
                          onDecline: () => _declineAssignment(assignment),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      for (final assignment in state.sentAssignments) ...[
                        _SentAssignmentCard(
                          assignment: assignment,
                          athleteName: name,
                          busy: state.isBusy,
                          onWithdraw: assignment.isPending
                              ? () => _withdrawAssignment(assignment)
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionLabel('COACHING'),
                    const SizedBox(height: AppSpacing.sm),
                    _coachingCard(state, name),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionLabel('FRIEND'),
                    const SizedBox(height: AppSpacing.sm),
                    if (friend != null) ...[
                      _ActionCard(
                        icon: LucideIcons.pencil,
                        title: 'Nickname',
                        subtitle: friend.nickname?.trim().isNotEmpty == true
                            ? friend.nickname!.trim()
                            : 'Only you see it',
                        onTap: () => _rename(friend),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ActionCard(
                        icon: LucideIcons.eye,
                        title: 'Privacy',
                        subtitle: friend.shareNotes
                            ? 'Notes are shared with them'
                            : 'Numbers only — notes stay private',
                        onTap: () => _privacy(friend),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      GlassButton(
                        label: 'Remove friend',
                        icon: LucideIcons.userMinus,
                        color: AppColors.danger,
                        disabled: state.isBusy,
                        onPressed: () => _unfriend(friend),
                      ),
                    ] else if (!state.isLoading)
                      Text(
                        'This friendship is gone.',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The coaching card: one edge drawn in its three possible states.
  Widget _coachingCard(FriendProfileState state, String name) {
    final pending = state.pendingEdge;
    final buttons = <Widget>[];

    if (state.theyCoachMe) {
      return _CoachingCard(
        title: '$name coaches you',
        body: 'They can read your training and write in your library. '
            'You can end that at any time.',
        buttons: [
          GlassButton(
            label: 'From your coach',
            icon: LucideIcons.history,
            compact: true,
            onPressed: () => showCoachActivitySheet(context),
          ),
          GlassButton(
            label: 'Coaching limits',
            icon: LucideIcons.info,
            compact: true,
            onPressed: () => showCoachPermissionsSheet(context),
          ),
          GlassButton(
            label: 'End coaching',
            compact: true,
            color: AppColors.danger,
            onPressed: () => _endCoaching(name, pending: false),
          ),
        ],
      );
    }

    if (state.iCoachThem) {
      return _CoachingCard(
        title: 'You coach $name',
        body: 'You can open their training as them and add to their library. '
            'Neither of you can delete what the other wrote.',
        buttons: [
          GlassButton(
            label: 'Open as coach',
            icon: LucideIcons.whistle,
            compact: true,
            solid: true,
            onPressed: () => context.push(
              '/coach-mode/${widget.friendId}',
              extra: name,
            ),
          ),
          GlassButton(
            label: 'Assign workout',
            icon: LucideIcons.clipboardList,
            compact: true,
            onPressed: () => _assign(name),
          ),
          GlassButton(
            label: 'Coaching limits',
            icon: LucideIcons.info,
            compact: true,
            onPressed: () => showCoachPermissionsSheet(context),
          ),
          GlassButton(
            label: 'End coaching',
            compact: true,
            color: AppColors.danger,
            onPressed: () => _endCoaching(name, pending: false),
          ),
        ],
      );
    }

    if (pending != null) {
      final requestedByMe = pending.requestedBy(_vm.me);
      if (requestedByMe) {
        final theyCoach = pending.coachUserId == _vm.friendId;
        return _CoachingCard(
          title: 'Waiting on $name',
          body: theyCoach
              ? 'You asked them to coach you. They have not answered yet.'
              : 'You offered to coach them. They have not answered yet.',
          buttons: [
            GlassButton(
              label: 'Cancel request',
              compact: true,
              color: AppColors.danger,
              onPressed: () => _endCoaching(name, pending: true),
            ),
          ],
        );
      }
      final theyOffered = pending.coachUserId == _vm.friendId;
      return _CoachingCard(
        title: theyOffered ? '$name wants to coach you' : '$name asks you to coach them',
        body: theyOffered
            ? 'Accepting lets them read your training and add to your library. '
                  'You can end it at any time.'
            : 'Accepting lets you open their training as them and add to their '
                  'library. Neither of you can delete what the other wrote.',
        buttons: [
          GlassButton(
            label: 'Decline',
            compact: true,
            onPressed: _decline,
          ),
          GlassButton(
            label: 'Accept',
            compact: true,
            solid: true,
            color: AppColors.success,
            onPressed: () => _accept(name, asAthlete: theyOffered),
          ),
        ],
      );
    }

    buttons.addAll([
      GlassButton(
        label: 'Ask to be coached',
        compact: true,
        onPressed: () => _ask(name),
      ),
      GlassButton(
        label: 'Offer to coach',
        compact: true,
        onPressed: () => _offer(name),
      ),
      GlassButton(
        label: 'Coaching limits',
        icon: LucideIcons.info,
        compact: true,
        onPressed: () => showCoachPermissionsSheet(context),
      ),
    ]);
    return _CoachingCard(
      title: 'No coaching yet',
      body: 'Coaching is a permission on top of friendship. Either of you '
          'can ask; the other accepts.',
      buttons: buttons,
    );
  }
}

/// The top of the page: the placeholder picture, the name, the pill.
class _Identity extends StatelessWidget {
  const _Identity({required this.name, required this.role});

  final String name;
  final FriendCoachingRole? role;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const LambdaAvatar(size: 88),
        const SizedBox(height: AppSpacing.md),
        UserNameText(
          name,
          style: AppFonts.ui(
            fontSize: AppTextStyles.xl,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        if (role != null) ...[
          const SizedBox(height: AppSpacing.sm),
          CoachingPill(role: role!),
        ],
      ],
    );
  }
}

/// A mono section caption, the same one the Social list reads.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.inkSecondary,
      ),
    );
  }
}

/// The coaching state's card: a one-line title, the one-sentence explanation,
/// and the verbs that state allows.
class _CoachingCard extends StatelessWidget {
  const _CoachingCard({
    required this.title,
    required this.body,
    required this.buttons,
  });

  final String title;
  final String body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppFonts.ui(
              fontSize: AppTextStyles.body,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              height: 1.4,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: buttons,
          ),
        ],
      ),
    );
  }
}

/// A tappable settings row: glyph, label, current value, chevron.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(LucideIcons.chevronRight, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// A workout a coach sent the caller: what it is, its note, and the two
/// verbs that decide it (2026-10-26, #24).
class _IncomingAssignmentCard extends StatelessWidget {
  const _IncomingAssignmentCard({
    required this.assignment,
    required this.coachName,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final CoachAssignment assignment;
  final String coachName;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final note = assignment.note?.trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserNameText(
            assignment.name,
            style: AppFonts.ui(
              fontSize: AppTextStyles.body,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'From $coachName',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
            ),
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.inkSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassButton(
                label: 'Decline',
                compact: true,
                disabled: busy,
                onPressed: onDecline,
              ),
              const SizedBox(width: AppSpacing.sm),
              GlassButton(
                label: 'Accept',
                compact: true,
                solid: true,
                color: AppColors.success,
                disabled: busy,
                onPressed: onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A workout the caller sent as a coach: its status, and the withdraw verb
/// while it is still pending.
class _SentAssignmentCard extends StatelessWidget {
  const _SentAssignmentCard({
    required this.assignment,
    required this.athleteName,
    required this.busy,
    required this.onWithdraw,
  });

  final CoachAssignment assignment;
  final String athleteName;
  final bool busy;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserNameText(
                  assignment.name,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'To $athleteName',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            assignment.isPending ? 'AWAITING REPLY' : 'ACCEPTED',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: assignment.isPending
                  ? AppColors.inkSecondary
                  : AppColors.success,
            ),
          ),
          if (onWithdraw != null) ...[
            const SizedBox(width: AppSpacing.sm),
            GlassButton(
              label: 'Withdraw',
              compact: true,
              disabled: busy,
              onPressed: onWithdraw!,
            ),
          ],
        ],
      ),
    );
  }
}

/// The one confirm the page uses: ending coaching, declining an ask or
/// withdrawing one, and removing a friend all end the same edge, so they
/// share the two verbs ([confirm] kills, `Keep it` stays).
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        title,
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      content: Text(
        message,
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        GlassButton(
          label: 'Keep it',
          compact: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        GlassButton(
          label: confirm,
          compact: true,
          solid: true,
          color: AppColors.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return ok ?? false;
}
