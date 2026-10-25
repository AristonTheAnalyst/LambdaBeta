import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/friend_code.dart';
import '../../../core/utils/name_limit.dart';
import '../../../data/models/friend.dart';
import '../../../data/repositories/friend_repository.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/name_limit_counter.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../viewmodel/friends_viewmodel.dart';

/// The Friends tab (2026-10-23): the user's own shareable code, the friends
/// the code has won, and the way to add more.
///
/// A friend is made instantly and mutually — entering a code is the whole
/// ceremony, so this screen has no pending section and no request verbs. The
/// code card is the top of the page because sharing it is the act that makes
/// the feature work; the list below it opens each friend's training history
/// in the same read-only viewer the user reads their own sessions in.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _vm = FriendsViewModel();

  @override
  void initState() {
    super.initState();
    _vm.start();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
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

  Future<void> _remove(Friend friend) async {
    final ok = await _confirmRemoveFriend(context, friend.displayName);
    if (!ok || !mounted) return;
    final removed = await _vm.remove(friend);
    if (!mounted || removed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _vm.state.value.error ?? 'Could not remove that friend.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opens the nickname sheet for [friend]. A dismissed sheet writes nothing;
  /// an emptied field clears the nickname, so the row falls back to the
  /// friend's own name, then their code.
  Future<void> _rename(Friend friend) async {
    final result = await showNicknameSheet(context, friend: friend);
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    final saved = await _vm.setNickname(
      friend,
      trimmed.isEmpty ? null : trimmed,
    );
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _vm.state.value.error ?? 'Could not save that nickname.',
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
                title: 'Friends',
                right: HeaderIconButton(
                  icon: Icons.person_add_alt_1,
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
                    _CodeCard(
                      code: state.myCode,
                      onCopy: state.myCode == null
                          ? null
                          : () => _copyCode(state.myCode!),
                    ),
                    const SizedBox(height: AppSpacing.xl),
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
                          onRename: () => _rename(state.friends[i]),
                          onRemove: () => _remove(state.friends[i]),
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

/// The shareable code, in its mono grouping, with the one action that
/// matters beside it. `—` until the code's row first syncs.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});

  final String? code;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
                icon: Icons.copy_outlined,
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

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
  });

  final Friend friend;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SwipeActions(
      // Keyed by friend, so a removal never hands an open drawer's state to
      // the row that slides up into its place.
      key: ValueKey(friend.userId),
      actions: [
        // Rename is the drawer's one non-destructive circle: the cream
        // `primary` fill with the page's own `bg` as its ink, the same recipe
        // the set row's notes action uses (`session_set_row.dart`). Red stays
        // reserved for remove.
        SwipeAction(
          icon: Icons.edit_outlined,
          color: AppColors.primary,
          foreground: AppColors.bg,
          onTap: onRename,
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
                friend.displayName,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.muted,
            ),
          ],
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
          Icon(Icons.people_outline, size: 28, color: AppColors.muted),
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

/// The add-by-code sheet. Returns the added friend (and whether the
/// friendship was new); null when dismissed.
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
              'Add friend',
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

/// The one "remove this friend?" warning. Returns true only on confirmation;
/// a dismissed dialog reads as "no".
Future<bool> _confirmRemoveFriend(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Remove Friend',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      content: Text(
        'Remove $name from your friends? '
        'You will not see each other\'s sessions anymore.',
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancel',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Remove',
            style: AppFonts.ui(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
