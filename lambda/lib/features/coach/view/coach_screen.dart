import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/friend_code.dart';
import '../../../data/models/athlete.dart';
import '../../../data/repositories/coach_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/glass_button.dart';
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

  Future<void> _accept(Athlete coach) async {
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
                            onTap: () => context.push(
                              '/profile/coach/${state.athletes[i].userId}',
                              extra: state.athletes[i].displayName,
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

/// An accepted athlete: tapping opens their completed history; swiping
/// removes them.
class _AthleteRow extends StatelessWidget {
  const _AthleteRow({
    super.key,
    required this.athlete,
    required this.onTap,
    required this.onRemove,
  });

  final Athlete athlete;
  final VoidCallback onTap;
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
