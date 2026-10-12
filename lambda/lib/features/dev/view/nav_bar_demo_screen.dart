import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/theme/lambda_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/scroll_shrink_nav_bar.dart';

/// Playground for [ScrollShrinkNavBar]: scroll the feed and watch the bar
/// shrink and fade, scroll back up and watch it spring back, tap the icons for
/// the selection pop. UI only — the tabs do not navigate anywhere.
class NavBarDemoScreen extends StatefulWidget {
  const NavBarDemoScreen({super.key});

  @override
  State<NavBarDemoScreen> createState() => _NavBarDemoScreenState();
}

class _NavBarDemoScreenState extends State<NavBarDemoScreen> {
  int _index = 0;

  /// The app's own four tabs, with Social in the slot Dev holds today — icon
  /// only, labels live on `Semantics` for screen readers.
  static const _items = [
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
    ScrollShrinkNavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Social',
      badge: true,
    ),
    ScrollShrinkNavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, _) {
        final c = themeNotifier.colors;
        return Scaffold(
          backgroundColor: c.bg,
          body: ScrollShrinkNavBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            items: _items,
            child: Column(
              children: [
                PageHeader(
                  title: 'Nav Bar Demo',
                  left: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: c.primary,
                    ),
                    onPressed: () => context.pop(),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      ScrollShrinkNavBar.contentInset(context),
                    ),
                    children: [
                      _IntroCard(selected: _items[_index].label),
                      const SizedBox(height: AppSpacing.lg),
                      _FeedCard(
                        color: c.accent,
                        icon: Icons.fitness_center,
                        title: 'Push Day · Week 3',
                        body:
                            'Bench 4 × 5 @ 82.5 · OHP 3 × 8 · Dips 3 × 10. '
                            'A card like this is the thing to watch slide '
                            'under the bar — the blur is sampling it live.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FeedCard(
                        color: c.planned,
                        icon: Icons.timeline,
                        title: 'Block 2 started',
                        body:
                            'Deload behind you. Volume climbs for three weeks, '
                            'then one back-off. Nothing to do but show up.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SectionLabel('Explore'),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: _Tile(
                              color: c.success,
                              icon: Icons.trending_up,
                              label: 'Progress',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _Tile(
                              color: c.accent,
                              icon: Icons.emoji_events_outlined,
                              label: 'PRs',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: _Tile(
                              color: c.danger,
                              icon: Icons.local_fire_department_outlined,
                              label: 'Streaks',
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _Tile(
                              color: c.planned,
                              icon: Icons.calendar_today_outlined,
                              label: 'Schedule',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _FeedCard(
                        color: c.success,
                        icon: Icons.bolt,
                        title: 'Squat PR · 140 × 3',
                        body:
                            'Beats 135 × 4 on the frontier — one event, both '
                            'axes. The stats bar agreed with the logs this '
                            'time, as it should.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FeedCard(
                        color: c.primary,
                        icon: Icons.self_improvement,
                        title: 'Rest day',
                        body:
                            'Walk, stretch, eat. The plan is a hint layer, '
                            'not a contract — skipping one set never failed '
                            'anyone.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FeedCard(
                        color: c.danger,
                        icon: Icons.hardware,
                        title: 'Bar path notes',
                        body:
                            'Elbows under the bar, wrists stacked. Pinned '
                            'lessons live on the exercise card so they are '
                            'there mid-set, not in a notebook.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _EndCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return AppCard(
      background: c.accentBg,
      borderColor: c.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Instagram-style nav bar',
            style: TextStyle(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w700,
              color: c.accentText,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Scroll down — the bar shrinks. Scroll up — it springs back. Tap '
            'an icon for the pop. The bar blurs whatever passes underneath '
            'it.',
            style: TextStyle(
              fontSize: AppTextStyles.sm,
              height: 1.4,
              color: c.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Selected: $selected',
            style: TextStyle(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: c.accentText,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w700,
        color: c.muted,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// A feed card with a coloured band up top — food for the bar's blur.
class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 132,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.85),
                  color.withValues(alpha: 0.18),
                ],
              ),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Icon(icon, size: 44, color: c.bg.withValues(alpha: 0.7)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: AppTextStyles.sm,
                    height: 1.4,
                    color: c.muted,
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

class _Tile extends StatelessWidget {
  const _Tile({required this.color, required this.icon, required this.label});

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return AspectRatio(
      aspectRatio: 1.4,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.8),
              color.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: c.bg.withValues(alpha: 0.75)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w600,
                color: c.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard();

  @override
  Widget build(BuildContext context) {
    final c = themeNotifier.colors;
    return AppCard(
      child: Column(
        children: [
          Icon(Icons.keyboard_arrow_up, size: 22, color: c.muted),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'End of the feed — scroll up and the bar springs back.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTextStyles.sm,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}
