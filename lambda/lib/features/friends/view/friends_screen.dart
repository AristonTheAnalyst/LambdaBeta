import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/friend_code.dart';
import '../../../core/utils/name_limit.dart';
import '../../../data/models/friend.dart';
import '../../../data/repositories/friend_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/lambda_avatar.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/name_limit_counter.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../viewmodel/friends_viewmodel.dart';

/// The Social tab (2026-10-23, reshaped 2026-10-30): the people the caller
/// trains with, one list, and one door in.
///
/// A friend is made instantly and mutually — entering a code is the whole
/// ceremony — and every friend's row opens their **profile**, which is where
/// the friendship's verbs live: their training, a nickname, the note tier,
/// coaching in either direction, and removing them. The shareable code lives
/// in the add sheet (the header's `person_add` icon), because sharing it is
/// what makes the feature work.
///
/// A row wears a **COACH** or **CLIENT** pill when an accepted coaching edge
/// connects the two (2026-10-30); a plain friendship wears none.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, this.viewModel});

  /// A caller-supplied state holder (host tests); null builds its own.
  final FriendsViewModel? viewModel;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final FriendsViewModel _vm = widget.viewModel ?? FriendsViewModel();

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

  Future<void> _openAddSheet() async {
    // A refusal from a previous attempt belongs to the sheet that showed it.
    _vm.clearError();
    final result = await showAddFriendSheet(context, vm: _vm);
    if (result == null || !mounted) return;
    final name = result.friend.displayName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.created
              ? 'Added $name'
              : "You're already friends with $name",
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<FriendsState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: 'Social',
                right: HeaderIconButton(
                  icon: LucideIcons.userPlus,
                  semanticsLabel: 'Add friend',
                  onPressed: _openAddSheet,
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
                    _SectionCaption(count: state.friends.length),
                    const SizedBox(height: AppSpacing.sm),
                    if (state.isLoading && state.friends.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxl),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        ),
                      )
                    else if (state.friends.isEmpty)
                      const _EmptyFriends()
                    else
                      for (var i = 0; i < state.friends.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.md),
                        _FriendRow(
                          friend: state.friends[i],
                          onTap: () => context.push(
                            '/friends/${state.friends[i].userId}',
                            extra: state.friends[i].displayName,
                          ),
                        ),
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

/// `FRIENDS` with the list's size — the same mono caption the date bar and
/// stats tiles read in.
class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'FRIENDS',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.inkSecondary,
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

/// One friend: the placeholder picture, their name, the coaching pill when
/// there is one, and the chevron into their profile (2026-10-30).
class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.onTap});

  final Friend friend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = friend.coachingRole;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          const LambdaAvatar(),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: UserNameText(
              friend.displayName,
              style: AppFonts.ui(
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          if (role != null) ...[
            const SizedBox(width: AppSpacing.sm),
            CoachingPill(role: role),
          ],
          const SizedBox(width: AppSpacing.sm),
          Icon(LucideIcons.chevronRight, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// The row's coaching badge: what this friend is TO THE CALLER — their coach,
/// or their client (2026-10-30). A plain friendship draws none.
class CoachingPill extends StatelessWidget {
  const CoachingPill({super.key, required this.role});

  final FriendCoachingRole role;

  @override
  Widget build(BuildContext context) {
    final isCoach = role == FriendCoachingRole.coach;
    final bg = isCoach ? AppColors.successBg : AppColors.accentBg;
    final ink = isCoach ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        isCoach ? 'COACH' : 'CLIENT',
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: ink,
        ),
      ),
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(LucideIcons.users, size: 28, color: AppColors.muted),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No friends yet',
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
              'Share your code, or add a friend with theirs.',
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

/// The add sheet (2026-10-30): the caller's own code, with its copy verb, and
/// the field that adds someone else's. One sheet because the two halves are
/// one exchange — you show yours, then type theirs.
///
/// Returns the added friend (and whether the friendship was new); null when
/// dismissed.
Future<AddFriendResult?> showAddFriendSheet(
  BuildContext context, {
  required FriendsViewModel vm,
}) => showLambdaModal<AddFriendResult>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _AddFriendSheet(vm: vm),
);

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet({required this.vm});

  final FriendsViewModel vm;

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
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

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: formatFriendCode(code)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Friend code copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// The field's own cleaner: upper-case, drop anything that is not a letter
  /// or digit (the hyphens the card draws, pasted spaces), stop at eight. The
  /// cleaner runs before the field's cap would, so pasting `abcd-efgh` lands
  /// whole — a raw `maxLength: 8` would have cut the pasted H off first.
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
    final result = await widget.vm.add(code);
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
              'Add a friend',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Enter your friend's code. You're friends as soon as it's added.",
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ValueListenableBuilder<FriendsState>(
              valueListenable: widget.vm.state,
              builder: (context, state, _) {
                final code = state.myCode;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CodeCard(
                      code: code,
                      onCopy: code == null ? null : () => _copyCode(code),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
                      label: 'Add friend',
                      solid: true,
                      loading: state.isAdding,
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

/// The shareable code, in its mono grouping, with the one action that
/// matters beside it. `—` until the code's row first syncs.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});

  final String? code;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR FRIEND CODE',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  code == null ? '—' : formatFriendCode(code!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xl,
                    fontWeight: FontWeight.w600,
                    // The uppercase-mono label tracking's ceiling — the
                    // spacing that makes a code read as a code without
                    // drifting off the type ladder (typography §3).
                    letterSpacing: 0.8,
                    // The absence glyph is a placeholder, and placeholders
                    // read in secondary ink (2026-10-22).
                    color: code == null
                        ? AppColors.inkSecondary
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              GlassButton(
                label: 'Copy',
                icon: LucideIcons.copy,
                compact: true,
                disabled: code == null,
                onPressed: onCopy ?? () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The nickname editor: what the caller calls one friend (2026-10-25).
/// Returns the trimmed draft — `''` when the field was emptied, which clears
/// the nickname — or null when the sheet was dismissed.
Future<String?> showNicknameSheet(
  BuildContext context, {
  required Friend friend,
}) => showLambdaModal<String>(
  context,
  fitContent: true,
  keyboardAware: true,
  child: _NicknameSheet(friend: friend),
);

class _NicknameSheet extends StatefulWidget {
  const _NicknameSheet({required this.friend});

  final Friend friend;

  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  late final _ctrl = TextEditingController(text: widget.friend.nickname ?? '');

  @override
  void initState() {
    super.initState();
    // Save's enabled state is derived from the text, so the sheet repaints as
    // the user types.
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

  String get _trimmed => _ctrl.text.trim();

  /// Save is enabled only when the draft would write something: a different
  /// value (an emptied field is a valid draft — it clears the nickname) and
  /// inside the cap. A Save that would write nothing stays disabled.
  bool get _canSave =>
      _trimmed != (widget.friend.nickname ?? '').trim() &&
      !nameTooLong(_ctrl.text, kMaxFriendNicknameLength);

  void _save() {
    if (!_canSave) return;
    Navigator.of(context, rootNavigator: true).pop(_trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final code = friend.friendCode?.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nickname',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Otherwise shown as ${friend.fallbackName}.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            // The friend's code is the other way to tell two same-named
            // friends apart, and this sheet is the only place it is drawn.
            if (code != null && code.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Friend code ${formatFriendCode(code)}',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            LambdaInput(
              controller: _ctrl,
              // The fallback doubles as the hint: an empty field shows
              // exactly what the row will read.
              placeholder: friend.fallbackName,
              // The sheet sits on the modal's surface ground.
              elevated: true,
              autofocus: true,
              maxLength: kMaxFriendNicknameLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: NameLimitCounter(
                length: _trimmed.length,
                max: kMaxFriendNicknameLength,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            GlassButton(
              label: 'Save',
              solid: true,
              disabled: !_canSave,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// The per-friend privacy sheet (2026-10-26, #23): exactly what one friend is
/// sent. Two tiers are drawn — the first always on, the second the caller's
/// choice — and every tap is its own complete write, so there is no Save to
/// press and a dismissal loses nothing.
///
/// The sheet takes the write itself ([onShareNotes]) rather than a view model,
/// so the friend profile and the Social list can both open it (2026-10-30).
Future<void> showFriendPrivacySheet(
  BuildContext context, {
  required Friend friend,
  required Future<bool> Function(bool shareNotes) onShareNotes,
  String? Function()? errorOf,
}) => showLambdaModal<void>(
  context,
  fitContent: true,
  child: _PrivacySheet(
    friend: friend,
    onShareNotes: onShareNotes,
    errorOf: errorOf,
  ),
);

class _PrivacySheet extends StatefulWidget {
  const _PrivacySheet({
    required this.friend,
    required this.onShareNotes,
    this.errorOf,
  });

  final Friend friend;
  final Future<bool> Function(bool shareNotes) onShareNotes;
  final String? Function()? errorOf;

  @override
  State<_PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends State<_PrivacySheet> {
  late bool _shareNotes = widget.friend.shareNotes;
  bool _saving = false;
  String? _error;

  Future<void> _setShareNotes(bool value) async {
    if (_saving || value == _shareNotes) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onShareNotes(value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _shareNotes = value;
      } else {
        // The row keeps its old mark: a write that did not land must not
        // read as a choice that did.
        _error = widget.errorOf?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.friend.displayName;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Privacy',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'What $name sees of your training.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                height: 1.4,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _TierRow(
              icon: LucideIcons.dumbbell,
              title: 'Training and sets',
              subtitle:
                  "Weights, reps and each set's notes. Always shared while "
                  "you're friends.",
              selected: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _TierRow(
              icon: LucideIcons.stickyNote,
              title: 'Exercise and session notes',
              subtitle:
                  'Your exercise notes and what you write before and after a '
                  'session.',
              selected: _shareNotes,
              onTap: _saving ? null : () => _setShareNotes(!_shareNotes),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  height: 1.4,
                  color: AppColors.danger,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            GlassButton(
              label: 'Done',
              solid: true,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One privacy level: an icon, a name, what it covers, and a mark saying
/// whether it is on. [onTap] null means the level cannot be changed (the
/// first tier is always shared).
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The mark is decoration; a screen reader hears the state from the row.
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: selected
              ? glassBox(AppColors.primary)
              : BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.inkSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
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
                        height: 1.4,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 20,
                // Muted is the unselected ring — inactive chrome, never text.
                color: selected ? AppColors.primary : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
