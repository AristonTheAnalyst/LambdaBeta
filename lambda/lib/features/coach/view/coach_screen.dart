import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/friend_code.dart';
import '../../../data/models/athlete.dart';
import '../../../data/models/coach_assignment.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/repositories/coach_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import 'coach_activity_sheet.dart';
import 'coach_permissions_sheet.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../viewmodel/coach_viewmodel.dart';

/// The Coach screen (2026-10-26), reached from Profile: one page for both
/// sides of a coaching relationship.
///
/// It draws four slices of the caller's coaching edges — invitations waiting
/// on them, the athletes they coach, their own coaches, and invitations still
/// pending — and any of them can be empty. An accepted athlete opens their
/// completed history in the same read-only viewer the Friends list uses: the
/// Training Logs list pointed at their id, and from a card the past-session
/// viewer with every write affordance gone.
///
/// Consent is the page's spine (2026-10-26, #22): the `+` sends an invitation
/// by friend code; nothing about the invitee reaches this device until they
/// accept — which is why a pending sent row is nameless — while the coach's
/// own name reaches the athlete from the invitation on.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key, this.viewModel});

  /// A caller-supplied state holder (host tests); null builds its own.
  final CoachViewModel? viewModel;

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  late final CoachViewModel _vm = widget.viewModel ?? CoachViewModel();

  /// Whether [_vm] is this screen's to dispose. An injected view model belongs
  /// to whoever passed it — a host test goes on asserting against it after the
  /// widget is gone.
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

  Future<void> _openInviteSheet() async {
    // A refusal from a previous attempt belongs to the sheet that showed it.
    _vm.clearError();
    final result = await showCoachInviteSheet(context, vm: _vm);
    if (result == null || !mounted) return;
    _toast(
      result.created ? 'Invitation sent' : 'That invitation was already sent',
    );
  }

  /// The athlete's accept carries the consent statement (2026-10-29): the
  /// permission sheet is the accept step, and only its Accept writes.
  Future<void> _accept(Athlete coach) async {
    final allowed = await showCoachPermissionsSheet(
      context,
      coachName: coach.displayName,
      accepting: true,
    );
    if (!allowed || !mounted) return;
    final ok = await _vm.accept(coach);
    if (!mounted || ok) return;
    _toast(_vm.state.value.error ?? 'Could not accept that invitation.');
  }

  Future<void> _remove(
    Athlete other, {
    required String title,
    required String message,
    required String confirm,
  }) async {
    final ok = await _confirmRemove(
      context,
      title: title,
      message: message,
      confirm: confirm,
    );
    if (!ok || !mounted) return;
    final removed = await _vm.remove(other);
    if (!mounted || removed) return;
    _toast(_vm.state.value.error ?? 'Could not remove that.');
  }

  // ── Workout assignments (2026-10-26, #24) ────────────────────────────────

  /// The athlete's accept: the copy lands in their library at once; the
  /// invitation leaves the list, and the toast says where it went.
  Future<void> _acceptAssignment(CoachAssignment assignment) async {
    final ok = await _vm.acceptAssignment(assignment);
    if (!mounted) return;
    if (ok) {
      _toast('${assignment.name} added to your workouts');
      return;
    }
    _toast(_vm.state.value.error ?? 'Could not accept that workout.');
  }

  Future<void> _declineAssignment(CoachAssignment assignment) async {
    final ok = await _confirmRemove(
      context,
      title: 'Decline Workout',
      message:
          "Decline ${assignment.name}? It stays out of your library, and "
          'your coach is not told why.',
      confirm: 'Decline',
    );
    if (!ok || !mounted) return;
    final declined = await _vm.declineAssignment(assignment);
    if (!mounted || declined) return;
    _toast(_vm.state.value.error ?? 'Could not decline that workout.');
  }

  Future<void> _openAssignSheet(Athlete athlete) async {
    // A refusal from a previous attempt belongs to the sheet that showed it.
    _vm.clearError();
    final sent = await showAssignWorkoutSheet(
      context,
      vm: _vm,
      athlete: athlete,
    );
    if (sent == true && mounted) _toast('Workout sent to ${athlete.displayName}');
  }

  Future<void> _withdrawAssignment(CoachAssignment assignment) async {
    final ok = await _confirmRemove(
      context,
      title: 'Withdraw Workout',
      message:
          "Withdraw ${assignment.name}? They won't see it anymore, and "
          'nothing is left behind.',
      confirm: 'Withdraw',
    );
    if (!ok || !mounted) return;
    final withdrawn = await _vm.withdrawAssignment(assignment);
    if (!mounted || withdrawn) return;
    _toast(_vm.state.value.error ?? 'Could not withdraw that workout.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<CoachState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: 'Coach',
                left: HeaderIconButton(
                  icon: Icons.arrow_back_ios_new,
                  semanticsLabel: 'Back',
                  glyphSize: 18,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/profile'),
                ),
                right: HeaderIconButton(
                  icon: Icons.person_add_alt_1,
                  semanticsLabel: 'Invite an athlete',
                  onPressed: _openInviteSheet,
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
                    // The consent statement stays reachable after the grant
                    // (2026-10-29).
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          GlassButton(
                            label: 'What coaching allows',
                            icon: Icons.info_outline,
                            compact: true,
                            onPressed: () =>
                                showCoachPermissionsSheet(context),
                          ),
                          GlassButton(
                            label: 'From your coach',
                            icon: Icons.history,
                            compact: true,
                            onPressed: () => showCoachActivitySheet(context),
                          ),
                        ],
                      ),
                    ),
                    if (state.isLoading && state.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxl),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    else if (state.isEmpty)
                      const _EmptyCoach()
                    else ...[
                      if (state.invitations.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'INVITATIONS TO YOU',
                          count: state.invitations.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < state.invitations.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _InvitationRow(
                            key: ValueKey(
                              'invite-${state.invitations[i].userId}',
                            ),
                            coach: state.invitations[i],
                            onAccept: () => _accept(state.invitations[i]),
                            onDecline: () => _remove(
                              state.invitations[i],
                              title: 'Decline Invitation',
                              message:
                                  'Decline this invitation? Nothing is shared '
                                  'either way.',
                              confirm: 'Decline',
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (state.assignmentInvitations.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'ASSIGNMENTS TO YOU',
                          count: state.assignmentInvitations.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (
                          var i = 0;
                          i < state.assignmentInvitations.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _AssignmentInvitationRow(
                            key: ValueKey(
                              'assignment-'
                              '${state.assignmentInvitations[i].assignmentId}',
                            ),
                            assignment: state.assignmentInvitations[i],
                            coachName: _coachNameOf(
                              state,
                              state.assignmentInvitations[i].coachUserId,
                            ),
                            onAccept: () => _acceptAssignment(
                              state.assignmentInvitations[i],
                            ),
                            onDecline: () => _declineAssignment(
                              state.assignmentInvitations[i],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (state.athletes.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'ATHLETES',
                          count: state.athletes.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < state.athletes.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _AthleteRow(
                            key: ValueKey(
                              'athlete-${state.athletes[i].userId}',
                            ),
                            athlete: state.athletes[i],
                            // Coach mode (2026-10-28): the athlete's own
                            // two-tab page, not the old read-only log list.
                            onTap: () => context.push(
                              '/coach-mode/${state.athletes[i].userId}',
                              extra: state.athletes[i].displayName,
                            ),
                            onAssign: () => _openAssignSheet(
                              state.athletes[i],
                            ),
                            onRemove: () => _remove(
                              state.athletes[i],
                              title: 'Remove Athlete',
                              message:
                                  'Remove ${state.athletes[i].displayName}? '
                                  "You'll stop seeing their training.",
                              confirm: 'Remove athlete',
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (state.coaches.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'YOUR COACHES',
                          count: state.coaches.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < state.coaches.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _PersonRow(
                            key: ValueKey('coach-${state.coaches[i].userId}'),
                            title: _nameOf(state.coaches[i], 'Your coach'),
                            onRemove: () => _remove(
                              state.coaches[i],
                              title: 'Remove Coach',
                              message:
                                  'Stop sharing your training with '
                                  '${_nameOf(state.coaches[i], 'this coach')}?',
                              confirm: 'Remove coach',
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (state.pendingSent.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'INVITATIONS SENT',
                          count: state.pendingSent.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < state.pendingSent.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _PendingSentRow(
                            key: ValueKey(
                              'sent-${state.pendingSent[i].userId}',
                            ),
                            sentDate: state.pendingSent[i].createdDate,
                            onWithdraw: () => _remove(
                              state.pendingSent[i],
                              title: 'Withdraw Invitation',
                              message:
                                  "Withdraw this invitation? They won't see "
                                  'it anymore.',
                              confirm: 'Withdraw',
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (state.assignmentsSent.isNotEmpty) ...[
                        _SectionCaption(
                          label: 'ASSIGNMENTS SENT',
                          count: state.assignmentsSent.length,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (
                          var i = 0;
                          i < state.assignmentsSent.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          _SentAssignmentRow(
                            key: ValueKey(
                              'sent-assignment-'
                              '${state.assignmentsSent[i].assignmentId}',
                            ),
                            assignment: state.assignmentsSent[i],
                            athleteName: _athleteNameOf(
                              state,
                              state.assignmentsSent[i].athleteUserId,
                            ),
                            // An accepted assignment is a record now, not a
                            // pending offer — only the pending row withdraws.
                            onWithdraw: state.assignmentsSent[i].isPending
                                ? () => _withdrawAssignment(
                                    state.assignmentsSent[i],
                                  )
                                : null,
                            onOpen: () => context.push(
                              '/coach-mode/'
                              '${state.assignmentsSent[i].athleteUserId}',
                              extra: _athleteNameOf(
                                state,
                                state.assignmentsSent[i].athleteUserId,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// [athlete]'s name, or [fallback] when their name slice has not synced — a
/// pending invitation's athlete, or a coach whose slice is still on its way.
String _nameOf(Athlete athlete, String fallback) =>
    athlete.hasName ? athlete.displayName : fallback;

/// The name behind an assignment's coach id, read off the caller's own coach
/// list — the coaching stream has already delivered it, so an assignment row
/// needs no read of its own (2026-10-26, #24).
String _coachNameOf(CoachState state, String coachUserId) {
  for (final coach in state.coaches) {
    if (coach.userId == coachUserId && coach.hasName) return coach.displayName;
  }
  return 'Your coach';
}

/// The name behind an assignment's athlete id, off the caller's roster.
String _athleteNameOf(CoachState state, String athleteUserId) {
  for (final athlete in state.athletes) {
    if (athlete.userId == athleteUserId && athlete.hasName) {
      return athlete.displayName;
    }
  }
  return 'Your athlete';
}

/// A mono caption with a count, the section head used on every list.
class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

/// An invitation waiting on the caller: the coach's name, when it came, and
/// the two verbs that decide it.
class _InvitationRow extends StatelessWidget {
  const _InvitationRow({
    super.key,
    required this.coach,
    required this.onAccept,
    required this.onDecline,
  });

  final Athlete coach;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserNameText(
            _nameOf(coach, 'A coach'),
            style: AppFonts.ui(
              fontSize: AppTextStyles.body,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Wants to coach you',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GlassButton(
                label: 'Decline',
                compact: true,
                onPressed: onDecline,
              ),
              const SizedBox(width: AppSpacing.sm),
              GlassButton(
                label: 'Accept',
                compact: true,
                solid: true,
                color: AppColors.success,
                onPressed: onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An accepted athlete: tapping opens their completed history; swiping hands
/// them a workout or removes them (2026-10-26, #24).
class _AthleteRow extends StatelessWidget {
  const _AthleteRow({
    super.key,
    required this.athlete,
    required this.onTap,
    required this.onAssign,
    required this.onRemove,
  });

  final Athlete athlete;
  final VoidCallback onTap;
  final VoidCallback onAssign;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.assignment_outlined,
          color: AppColors.primary,
          foreground: AppColors.bg,
          onTap: onAssign,
        ),
        SwipeAction(
          icon: Icons.person_remove_outlined,
          color: AppColors.danger,
          foreground: AppColors.dangerText,
          onTap: onRemove,
        ),
      ],
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: UserNameText(
                athlete.displayName,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// A coach of the caller's, or another non-opening person row — no chevron:
/// there is no page behind it, only the swipe's remove.
class _PersonRow extends StatelessWidget {
  const _PersonRow({super.key, required this.title, required this.onRemove});

  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.person_remove_outlined,
          color: AppColors.danger,
          foreground: AppColors.dangerText,
          onTap: onRemove,
        ),
      ],
      child: AppCard(
        child: UserNameText(
          title,
          style: AppFonts.ui(
            fontSize: AppTextStyles.body,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// An invitation the caller sent that is still pending. Nameless by design:
/// nothing about the athlete reaches this device before they accept.
class _PendingSentRow extends StatelessWidget {
  const _PendingSentRow({
    super.key,
    required this.sentDate,
    required this.onWithdraw,
  });

  final DateTime? sentDate;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final sent = sentDate;
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.undo,
          color: AppColors.primary,
          foreground: AppColors.bg,
          onTap: onWithdraw,
        ),
      ],
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invitation pending',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  if (sent != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Sent ${DateFormat('d MMM yyyy').format(sent.toLocal())}',
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.xs,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A workout a coach sent the caller: what it is, who sent it, its note, and
/// the two verbs that decide it (2026-10-26, #24). Accepting copies it into
/// the caller's own library — the coach's template is never shared — so the
/// row says "copy" nowhere: the athlete simply gets the workout.
class _AssignmentInvitationRow extends StatelessWidget {
  const _AssignmentInvitationRow({
    super.key,
    required this.assignment,
    required this.coachName,
    required this.onAccept,
    required this.onDecline,
  });

  final CoachAssignment assignment;
  final String coachName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final note = assignment.note?.trim();
    final created = assignment.createdDate;
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
          Row(
            children: [
              Text(
                'From ',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              ),
              Flexible(
                child: UserNameText(
                  coachName,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (created != null)
                Text(
                  DateFormat('d MMM yyyy').format(created.toLocal()).toUpperCase(),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
            ],
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
                onPressed: onDecline,
              ),
              const SizedBox(width: AppSpacing.sm),
              GlassButton(
                label: 'Accept',
                compact: true,
                solid: true,
                color: AppColors.success,
                onPressed: onAccept,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An assignment the caller sent as a coach: the workout, whose desk it is
/// on, and whether it has been taken. A pending row swipes to withdraw; an
/// accepted one is a record and only opens the athlete (2026-10-26, #24).
class _SentAssignmentRow extends StatelessWidget {
  const _SentAssignmentRow({
    super.key,
    required this.assignment,
    required this.athleteName,
    required this.onOpen,
    required this.onWithdraw,
  });

  final CoachAssignment assignment;
  final String athleteName;
  final VoidCallback onOpen;

  /// Null once accepted: there is nothing left to withdraw.
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      onTap: onOpen,
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
          Row(
            children: [
              Text(
                'To ',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              ),
              Flexible(
                child: UserNameText(
                  athleteName,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
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
            ],
          ),
        ],
      ),
    );
    final withdraw = onWithdraw;
    if (withdraw == null) return card;
    return SwipeActions(
      actions: [
        SwipeAction(
          icon: Icons.undo,
          color: AppColors.primary,
          foreground: AppColors.bg,
          onTap: withdraw,
        ),
      ],
      child: card,
    );
  }
}

/// The assign sheet: pick one of the coach's own workouts, add a word of
/// context, send (2026-10-26, #24). Returns true when an assignment landed.
Future<bool?> showAssignWorkoutSheet(
  BuildContext context, {
  required CoachViewModel vm,
  required Athlete athlete,
}) => showLambdaModal<bool>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _AssignWorkoutSheet(vm: vm, athlete: athlete),
);

class _AssignWorkoutSheet extends StatefulWidget {
  const _AssignWorkoutSheet({required this.vm, required this.athlete});

  final CoachViewModel vm;
  final Athlete athlete;

  @override
  State<_AssignWorkoutSheet> createState() => _AssignWorkoutSheetState();
}

class _AssignWorkoutSheetState extends State<_AssignWorkoutSheet> {
  final _noteCtrl = TextEditingController();
  List<PlannedSession>? _workouts;
  PlannedSession? _chosen;
  bool _sending = false;
  String? _loadError;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _workouts = null;
    });
    final workouts = await widget.vm.loadWorkouts();
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _loadError = workouts == null
          ? (widget.vm.state.value.error ?? 'Could not load your workouts.')
          : null;
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chosen = _chosen;
    if (chosen == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final note = _noteCtrl.text.trim();
    final sent = await widget.vm.assign(
      widget.athlete,
      chosen,
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      // A refusal stays in the sheet (the VM's error), so the sheet that
      // caused it is also the one that shows it — and the words are the
      // VM's, not a generic sentence written twice.
      if (!sent) {
        _sendError =
            widget.vm.state.value.error ?? 'Could not send that workout.';
      }
    });
    if (sent) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final workouts = _workouts;
    return SafeArea(
      key: const ValueKey('assign-workout-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assign a workout',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick one of your workouts. '
              "${widget.athlete.displayName} gets their own copy to accept.",
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loadError != null) ...[
              Text(
                _loadError!,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassButton(
                label: 'Retry',
                compact: true,
                onPressed: _load,
              ),
            ] else if (workouts == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (workouts.isEmpty)
              Text(
                'You have no workouts yet — build one in the Library first.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.inkSecondary,
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final workout in workouts) ...[
                        _workoutChoice(workout),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              LambdaInput(
                controller: _noteCtrl,
                label: 'Note (optional)',
                placeholder: 'Why this one?\nAnything to focus on?',
                elevated: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_sendError != null) ...[
                Text(
                  _sendError!,
                  key: const ValueKey('assign-workout-error'),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              GlassButton(
                key: const ValueKey('assign-workout-send'),
                label: 'Send workout',
                solid: true,
                color: AppColors.success,
                loading: _sending,
                disabled: _chosen == null,
                onPressed: _send,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One selectable workout — the choice recipe (glass fill, accent when
  /// chosen), drawn through [UserNameText] so a 20-character name ellipsizes
  /// instead of overflowing the sheet.
  Widget _workoutChoice(PlannedSession workout) {
    final active = _chosen?.sessionId == workout.sessionId;
    return GestureDetector(
      key: ValueKey('assign-workout-${workout.sessionId}'),
      onTap: () => setState(() => _chosen = workout),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: glassBox(
          active ? AppColors.accent : AppColors.primary,
        ),
        child: Row(
          children: [
            Expanded(
              child: UserNameText(
                workout.name,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.accent : AppColors.primary,
                ),
              ),
            ),
            if (active)
              Icon(Icons.check, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

class _EmptyCoach extends StatelessWidget {
  const _EmptyCoach();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(Icons.sports_outlined, size: 28, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No coaching yet',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              'Invite an athlete with their friend code, or accept an '
              'invitation sent to you.',
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The invite sheet. Returns the RPC's report (and whether the invitation is
/// new); null when dismissed.
Future<CoachInvite?> showCoachInviteSheet(
  BuildContext context, {
  required CoachViewModel vm,
}) => showLambdaModal<CoachInvite>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _InviteSheet(vm: vm),
);

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.vm});

  final CoachViewModel vm;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_rebuildForValidity);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_rebuildForValidity);
    _ctrl.dispose();
    super.dispose();
  }

  void _rebuildForValidity() {
    if (mounted) setState(() {});
  }

  /// The field's own cleaner: upper-case, drop anything that is not a letter
  /// or digit (the hyphens the code card draws, pasted spaces), stop at eight
  /// — the same cleaner the Friends add sheet uses, and for the same reason: a
  /// raw `maxLength: 8` would cut a pasted `abcd-efgh`'s last letter first.
  void _onChanged(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final capped = cleaned.length <= kFriendCodeLength
        ? cleaned
        : cleaned.substring(0, kFriendCodeLength);
    if (capped != raw) {
      _ctrl.value = TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length),
      );
    }
  }

  bool get _valid => normalizeFriendCode(_ctrl.text) != null;

  Future<void> _submit() async {
    final code = normalizeFriendCode(_ctrl.text);
    if (code == null) return;
    final result = await widget.vm.invite(code);
    if (!mounted || result == null) return;
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Invite an athlete',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Enter your athlete's friend code. They'll see the invitation "
              'and choose whether to share their training.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ValueListenableBuilder<CoachState>(
              valueListenable: widget.vm.state,
              builder: (context, state, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LambdaInput(
                      controller: _ctrl,
                      label: 'Friend code',
                      placeholder: 'ABCD-EFGH',
                      // The sheet sits on the modal's surface ground.
                      elevated: true,
                      autofocus: true,
                      // A backstop only — [_onChanged] is what caps the code.
                      maxLength: kFriendCodeLength + 4,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      error: state.error,
                      onChanged: _onChanged,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    GlassButton(
                      label: 'Send invitation',
                      solid: true,
                      loading: state.isInviting,
                      disabled: !_valid,
                      onPressed: _submit,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The one confirm the page uses: removing an athlete, a coach, declining an
/// invitation or withdrawing one all end the same edge, so they share the two
/// verbs ([confirm] kills, `Keep it` stays) and differ only in wording.
Future<bool> _confirmRemove(
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
