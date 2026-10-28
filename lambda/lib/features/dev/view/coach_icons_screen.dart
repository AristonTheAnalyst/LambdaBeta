import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';

/// DEV — the coaching icon study (2026-10-28).
///
/// The coach bar needs two glyphs it does not have yet: one that says
/// `COACHING` beside the athlete's name, and the way out. This page draws
/// every candidate that exists in Flutter's Material set at the bar's own
/// sizes — 24 (the floor control) and 40 (a floor-bar square's glyph) — with
/// the identifier to copy and a line on what the shape says.
///
/// Nothing here is wired: pick a name, then it moves into `CoachModeIdentity`
/// (or `_exitButton`) once.
class CoachIconsScreen extends StatelessWidget {
  const CoachIconsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Coach Icons'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                ScrollShrinkNavBar.contentInset(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _IntroCard(),
                  const SizedBox(height: AppSpacing.lg),
                  const _IconSection(
                    label: 'IDENTITY — beside COACHING',
                    rows: [
                      _IconRowData(
                        icon: Icons.school_outlined,
                        name: 'school_outlined',
                        reads: 'The mentor read: a person and the guidance.',
                      ),
                      _IconRowData(
                        icon: Icons.sports_outlined,
                        name: 'sports_outlined',
                        reads: 'The whistle — sport-specific coaching.',
                      ),
                      _IconRowData(
                        icon: Icons.supervisor_account_outlined,
                        name: 'supervisor_account_outlined',
                        reads: 'One person overseeing another: coach + athlete.',
                        inUse: true,
                      ),
                      _IconRowData(
                        icon: Icons.assignment_ind_outlined,
                        name: 'assignment_ind_outlined',
                        reads: 'Person with a clipboard — reviewing what she did.',
                      ),
                      _IconRowData(
                        icon: Icons.handshake,
                        name: 'handshake',
                        reads: 'The grant itself: a two-sided agreement.',
                      ),
                      _IconRowData(
                        icon: Icons.badge_outlined,
                        name: 'badge_outlined',
                        reads: 'A credential — the coach’s standing.',
                      ),
                      _IconRowData(
                        icon: Icons.groups_outlined,
                        name: 'groups_outlined',
                        reads: 'The roster — several athletes.',
                      ),
                      _IconRowData(
                        icon: Icons.psychology_alt,
                        name: 'psychology_alt',
                        reads: 'Mindset; abstract, carries no person.',
                      ),
                      _IconRowData(
                        icon: Icons.workspace_premium,
                        name: 'workspace_premium',
                        reads: 'Award — may read as an achievement, not a role.',
                      ),
                      _IconRowData(
                        icon: Icons.military_tech,
                        name: 'military_tech',
                        reads: 'Award/medal — same risk, louder.',
                      ),
                      _IconRowData(
                        icon: Icons.supervised_user_circle_outlined,
                        name: 'supervised_user_circle_outlined',
                        reads: 'A person inside someone’s circle of care.',
                      ),
                      _IconRowData(
                        icon: Icons.manage_accounts_outlined,
                        name: 'manage_accounts_outlined',
                        reads: 'Managing someone’s account — close to “act as”.',
                      ),
                      _IconRowData(
                        icon: Icons.escalator_warning,
                        name: 'escalator_warning',
                        reads: 'The mentor sign: an adult guiding a smaller figure.',
                      ),
                      _IconRowData(
                        icon: Icons.cast_for_education,
                        name: 'cast_for_education',
                        reads: 'Teaching a class — instruction, not partnership.',
                      ),
                      _IconRowData(
                        icon: Icons.menu_book,
                        name: 'menu_book',
                        reads: 'A playbook — the plan, not the person.',
                      ),
                      _IconRowData(
                        icon: Icons.person_outline,
                        name: 'person_outline',
                        reads: 'Plain person: no role, no relationship.',
                      ),
                      _IconRowData(
                        icon: Icons.account_circle_outlined,
                        name: 'account_circle_outlined',
                        reads: 'A profile avatar — an identity, but any identity.',
                      ),
                      _IconRowData(
                        icon: Icons.diversity_3,
                        name: 'diversity_3',
                        reads: 'A small group — coach and athlete together.',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _IconSection(
                    label: 'COACHING WORK — what the role does',
                    rows: [
                      _IconRowData(
                        icon: Icons.fact_check,
                        name: 'fact_check',
                        reads: 'Reviewing what she did.',
                      ),
                      _IconRowData(
                        icon: Icons.checklist,
                        name: 'checklist',
                        reads: 'The plan, ticked off.',
                      ),
                      _IconRowData(
                        icon: Icons.rate_review_outlined,
                        name: 'rate_review_outlined',
                        reads: 'Feedback — already the Library’s Reviews glyph.',
                      ),
                      _IconRowData(
                        icon: Icons.forum,
                        name: 'forum',
                        reads: 'A conversation.',
                      ),
                      _IconRowData(
                        icon: Icons.insights,
                        name: 'insights',
                        reads: 'Progress at a glance.',
                      ),
                      _IconRowData(
                        icon: Icons.query_stats,
                        name: 'query_stats',
                        reads: 'Trends and queries.',
                      ),
                      _IconRowData(
                        icon: Icons.trending_up,
                        name: 'trending_up',
                        reads: 'Getting better.',
                      ),
                      _IconRowData(
                        icon: Icons.lightbulb_outline,
                        name: 'lightbulb_outline',
                        reads: 'A cue or an idea.',
                      ),
                      _IconRowData(
                        icon: Icons.tips_and_updates,
                        name: 'tips_and_updates',
                        reads: 'Tips — reads a little casual.',
                      ),
                      _IconRowData(
                        icon: Icons.monitor_heart_outlined,
                        name: 'monitor_heart_outlined',
                        reads: 'Training load / heart rate.',
                      ),
                      _IconRowData(
                        icon: Icons.sports_score,
                        name: 'sports_score',
                        reads: 'A scoreboard flag — results.',
                      ),
                      _IconRowData(
                        icon: Icons.scoreboard,
                        name: 'scoreboard',
                        reads: 'Results, more literally.',
                      ),
                      _IconRowData(
                        icon: Icons.assignment_turned_in_outlined,
                        name: 'assignment_turned_in_outlined',
                        reads: 'Work done.',
                      ),
                      _IconRowData(
                        icon: Icons.task_alt,
                        name: 'task_alt',
                        reads: 'A tick — completion.',
                      ),
                      _IconRowData(
                        icon: Icons.verified_outlined,
                        name: 'verified_outlined',
                        reads: 'Checked / verified.',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _IconSection(
                    label: 'EXIT — leaving coach mode',
                    rows: [
                      _IconRowData(
                        icon: Icons.chevron_left,
                        name: 'chevron_left',
                        reads: 'Current. Pure navigation: back out of the mode.',
                        inUse: true,
                      ),
                      _IconRowData(
                        icon: Icons.arrow_back_ios_new,
                        name: 'arrow_back_ios_new',
                        reads: 'The app’s own header back glyph.',
                      ),
                      _IconRowData(
                        icon: Icons.keyboard_arrow_left,
                        name: 'keyboard_arrow_left',
                        reads: 'Lighter chevron, the selectors’ family.',
                      ),
                      _IconRowData(
                        icon: Icons.door_front_door_outlined,
                        name: 'door_front_door_outlined',
                        reads: 'Leave the room — literal, no second meaning.',
                      ),
                      _IconRowData(
                        icon: Icons.meeting_room_outlined,
                        name: 'meeting_room_outlined',
                        reads: 'Also a door, a bit more office.',
                      ),
                      _IconRowData(
                        icon: Icons.logout,
                        name: 'logout',
                        reads: 'Reads as signing out of the account — avoid here.',
                      ),
                      _IconRowData(
                        icon: Icons.exit_to_app,
                        name: 'exit_to_app',
                        reads: 'Same sign-out risk, and the shape is busier.',
                      ),
                      _IconRowData(
                        icon: Icons.arrow_back,
                        name: 'arrow_back',
                        reads: 'Plain back arrow.',
                      ),
                      _IconRowData(
                        icon: Icons.arrow_left,
                        name: 'arrow_left',
                        reads: 'The same arrow without the iOS tail.',
                      ),
                      _IconRowData(
                        icon: Icons.navigate_before,
                        name: 'navigate_before',
                        reads: 'The old Material back chevron.',
                      ),
                      _IconRowData(
                        icon: Icons.west,
                        name: 'west',
                        reads: 'A left arrow wearing a compass name.',
                      ),
                      _IconRowData(
                        icon: Icons.keyboard_backspace,
                        name: 'keyboard_backspace',
                        reads: 'Delete-shaped — reads as erasing text.',
                      ),
                      _IconRowData(
                        icon: Icons.first_page,
                        name: 'first_page',
                        reads: 'Jump to the start — a bar glyph.',
                      ),
                      _IconRowData(
                        icon: Icons.arrow_circle_left_outlined,
                        name: 'arrow_circle_left_outlined',
                        reads: 'Back inside a circle — a control, not a bar glyph.',
                      ),
                      _IconRowData(
                        icon: Icons.door_back_door_outlined,
                        name: 'door_back_door_outlined',
                        reads: 'The back door.',
                      ),
                      _IconRowData(
                        icon: Icons.door_sliding_outlined,
                        name: 'door_sliding_outlined',
                        reads: 'A sliding door — leaving, softly.',
                      ),
                      _IconRowData(
                        icon: Icons.close,
                        name: 'close',
                        reads: 'Dismiss — reads as closing a sheet.',
                      ),
                      _IconRowData(
                        icon: Icons.cancel_outlined,
                        name: 'cancel_outlined',
                        reads: 'Cancel — an abort read.',
                      ),
                      _IconRowData(
                        icon: Icons.undo,
                        name: 'undo',
                        reads: 'Undo — the wrong meaning entirely.',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _IconSection(
                    label: 'SWITCHING — for a later “switch athlete”',
                    rows: [
                      _IconRowData(
                        icon: Icons.switch_account,
                        name: 'switch_account',
                        reads: 'The natural switch — one account to another.',
                      ),
                      _IconRowData(
                        icon: Icons.swap_horiz,
                        name: 'swap_horiz',
                        reads: 'Exchange two things.',
                      ),
                      _IconRowData(
                        icon: Icons.sync_alt,
                        name: 'sync_alt',
                        reads: 'Two arrows cycling — switch without a new account.',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _FootnoteCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Two glyphs, one choice each',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Every icon below exists in Flutter’s Material set. Each row shows '
            'the shape at 24 (the floor control’s size) and 40 (a square’s '
            'glyph), then the identifier to copy and what the shape says. The '
            'name is what matters: once picked, it moves into the coach bar '
            'once and nowhere else.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              height: 1.45,
              color: AppColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FootnoteCard extends StatelessWidget {
  const _FootnoteCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text(
        'The bar is the frame, so its controls are glyphs and carry their '
        'meaning in semantics — never a word added to explain the shape. The '
        'identity’s `COACHING` eyebrow is text and stays text; these are the '
        'candidates if a glyph joins it.',
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          height: 1.45,
          color: AppColors.inkSecondary,
        ),
      ),
    );
  }
}

class _IconRowData {
  const _IconRowData({
    required this.icon,
    required this.name,
    required this.reads,
    this.inUse = false,
  });

  final IconData icon;
  final String name;
  final String reads;
  final bool inUse;
}

class _IconSection extends StatelessWidget {
  const _IconSection({required this.label, required this.rows});

  final String label;
  final List<_IconRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Container(height: 1, color: AppColors.border),
                _IconRow(data: rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({required this.data});

  final _IconRowData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Icon(data.icon, size: 24, color: AppColors.primary),
          ),
          SizedBox(
            width: 52,
            child: Icon(data.icon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        data.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.mono(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (data.inUse) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'IN USE',
                        style: AppFonts.mono(
                          fontSize: AppTextStyles.xs,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  data.reads,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    height: 1.35,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
