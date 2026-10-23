import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../features/session/model/session_local_state.dart';
import 'container_styles.dart';
import 'session_chevron_button.dart';

/// The session's place in time, drawn at the top of the floor bar on both
/// session surfaces (2026-10-22): `TODAY - 22 Oct 2026` while the session
/// being logged is today's, `PREVIOUSLY - 20 Oct 2026` while a recorded one
/// is on screen.
///
/// One widget, so the live Training page and the past-session viewer read as
/// the same page — the lab's date changer is the look it comes from
/// (2026-10-21), arrows included: the phrase is centred between two chevrons
/// that walk the session stack (older on the left, newer on the right). The
/// stage owns what a step means — the live page opens the previous record,
/// the viewer walks completed sessions and returns to today's live session
/// from the newest — so the bar itself only asks for the two taps. A null
/// callback greys that arrow; the ends are inert, never absent, so the
/// phrase stays on the bar's own middle.
///
/// [isToday] is the caller's fact, not the clock's: the live page says TODAY
/// because the session is the one being logged, and the viewer says
/// PREVIOUSLY because it is reading a record — even one recorded this
/// morning.
///
/// Tapping the phrase walks the date's reading (2026-10-23): the written
/// date, then `N days ago`, then `N weeks N days ago`, then round again.
/// A relative reading is its own whole phrase — `PREVIOUSLY -` is dropped,
/// because "previously, 3 days ago" says the same thing twice — and a
/// session younger than a week has no weeks reading to show, so its cycle
/// is the dated phrase and the days alone. The old reading cuts away and
/// the new one scales in — the bar is a readout, not a destination, so the
/// switch stays a flicker of the same line rather than a navigation. A live
/// session's phrase is not a control: today is today in every reading, so
/// its tap stays inert.
///
/// The bar walks one of two stacks (2026-10-23), and the stage brings both:
/// **EXERCISE** (the default on both surfaces) reads the exercise on the
/// card performance by performance — the card's sets swap, the page stays;
/// **SESSION** reads whole records, swapping everything under the bar. A
/// compact radio pair **inside the bar, under the date** names both modes,
/// one checked (2026-10-23) — `SESSION` and `SESSION BY EXERCISE` — and the
/// box wraps both rows so the selector is one thing; both names are always
/// visible, so what the arrows walk is read without pressing anything.
/// Without [onToggleMode] the bar draws no radios, so the two-mode readout
/// is the stages' fact, not the bar's.
class SessionDateBar extends StatefulWidget {
  const SessionDateBar({
    super.key,
    required this.isToday,
    required this.date,
    this.mode = SessionDateMode.exercise,
    this.onToggleMode,
    this.onOlder,
    this.onNewer,
  });

  final bool isToday;
  final DateTime date;

  /// Which stack the arrows are walking — the radios' selection, nothing more.
  final SessionDateMode mode;

  /// Switches the stacks; null hides the radios (a bar with one stack).
  final VoidCallback? onToggleMode;

  /// Walk to the session before this one; null greys the left arrow.
  final VoidCallback? onOlder;

  /// Walk to the session after this one (toward today); null greys the
  /// right arrow.
  final VoidCallback? onNewer;

  @override
  State<SessionDateBar> createState() => _SessionDateBarState();
}

/// The three readings the phrase cycles through, in tap order.
enum _DateLook { date, daysAgo, weeksAgo }

class _SessionDateBarState extends State<SessionDateBar>
    with SingleTickerProviderStateMixin {
  _DateLook _look = _DateLook.date;

  /// Drives the scale-in. It rests at 1 so the bar paints at full size on
  /// first build; a tap rewinds it to 0 and lets it run.
  late final AnimationController _scale = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  /// Calendar days since the session, so "3 days ago" does not drift with
  /// the hour it is read at.
  int _daysSince() {
    final now = DateUtils.dateOnly(DateTime.now());
    final then = DateUtils.dateOnly(widget.date.toLocal());
    // A clock that runs behind can stamp a session ahead of "now"; read it
    // as today rather than invent a reading from the future.
    final elapsed = now.difference(then).inDays;
    return elapsed < 0 ? 0 : elapsed;
  }

  /// The next reading: date → days → weeks → date, except that a session
  /// younger than a week has no weeks reading to show, so its cycle is the
  /// date and the days alone (2026-10-23).
  void _cycleLook() {
    final longEnoughForWeeks = _daysSince() >= 7;
    setState(() {
      _look = switch (_look) {
        _DateLook.date => _DateLook.daysAgo,
        _DateLook.daysAgo =>
          longEnoughForWeeks ? _DateLook.weeksAgo : _DateLook.date,
        _DateLook.weeksAgo => _DateLook.date,
      };
    });
    _scale.forward(from: 0);
  }

  /// The date part of the phrase, in the reading [_look] asks for.
  String _datePart() {
    if (_look == _DateLook.date) {
      return DateFormat('d MMM yyyy').format(widget.date.toLocal());
    }
    final days = _daysSince();
    if (_look == _DateLook.daysAgo) return _daysAgo(days);

    final weeks = days ~/ 7;
    final rest = days % 7;
    final weekPart = weeks == 1 ? '1 week' : '$weeks weeks';
    if (rest == 0) return '$weekPart ago';
    final dayPart = rest == 1 ? '1 day' : '$rest days';
    return '$weekPart $dayPart ago';
  }

  String _daysAgo(int days) {
    if (days <= 0) return 'today';
    return days == 1 ? '1 day ago' : '$days days ago';
  }

  /// The mode radios (2026-10-23): both stacks named side by side under the
  /// date — `SESSION` and `SESSION BY EXERCISE` — inside the bar's own box,
  /// the live one marked; a radio pair, not
  /// a toggle word, so what the arrows will walk is read without pressing
  /// anything. Discreet by design: no glass and no fill, the date's own mono
  /// caption at the date's own size, and a small radio glyph carrying the
  /// selection. The 40pt target is the option's, not the text's.
  Widget _modeRadios() {
    final pair = Row(
      key: const ValueKey('session-date-bar-mode'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeOption(
          SessionDateMode.session,
          'SESSION',
          'Session',
          'Walks whole sessions',
        ),
        const SizedBox(width: AppSpacing.lg),
        _modeOption(
          SessionDateMode.exercise,
          'SESSION BY EXERCISE',
          'Session by exercise',
          'Walks this exercise\'s own performances',
        ),
      ],
    );
    // A long label at a large text scale must not push the box past the
    // page: the pair scales down whole, the phrase's own guard (2026-10-23).
    return FittedBox(fit: BoxFit.scaleDown, child: pair);
  }

  /// One radio: a glyph and a word on a 40pt target. The selected side reads
  /// in primary ink with the accent ring the app's radio idiom wears; the
  /// other stays legible in `inkSecondary`, quiet behind the muted ring.
  Widget _modeOption(
    SessionDateMode mode,
    String label,
    String semanticsLabel,
    String hint,
  ) {
    final selected = widget.mode == mode;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: semanticsLabel,
      hint: selected ? null : hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping the live side is not a switch: only the other radio is.
        onTap: selected ? null : widget.onToggleMode,
        child: SizedBox(
          key: ValueKey('session-date-bar-mode-${mode.name}'),
          height: SessionChevronButton.kSessionChevronSize,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 14,
                color: selected ? AppColors.accent : AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppFonts.mono(
                  // The date's own size and family: the pair reads as the
                  // bar's own caption, not as a second surface (2026-10-23).
                  fontSize: AppTextStyles.caption,
                  letterSpacing: 0.6,
                  color: selected ? AppColors.primary : AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateLabel = widget.isToday ? 'TODAY' : 'PREVIOUSLY';

    Widget phrase = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          key: const ValueKey('session-date-bar-phrase'),
          scale: 0.85 + 0.15 * Curves.easeOut.transform(_scale.value),
          child: child,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The state belongs to the written date; a relative reading is
            // its own phrase and drops it.
            if (_look == _DateLook.date) ...[
              Text(
                '$stateLabel -',
                key: const ValueKey('session-date-bar-state'),
                style: AppFonts.mono(
                  // The date's own size: the state and the date it names
                  // are one line read as one phrase (2026-10-21).
                  fontSize: AppTextStyles.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  // Both states are read, so both wear readable ink; the
                  // accent marks the live session, not the only legible
                  // reading.
                  color: widget.isToday
                      ? AppColors.accent
                      : AppColors.inkSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              _datePart(),
              key: const ValueKey('session-date-bar-date'),
              style: AppFonts.mono(
                fontSize: AppTextStyles.caption,
                letterSpacing: 0.6,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );

    // Today reads the same however it is phrased, so a live bar's phrase is
    // a plain readout; only a record's date is a control (2026-10-23).
    if (!widget.isToday) {
      phrase = Semantics(
        button: true,
        hint: 'Changes how the date reads',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cycleLook,
          child: phrase,
        ),
      );
    }

    final dateRow = Row(
      children: [
        SessionChevronButton(
          key: const ValueKey('session-date-bar-older'),
          icon: Icons.chevron_left,
          // What a step is depends on the stack the bar walks (2026-10-23).
          semanticsLabel: widget.mode == SessionDateMode.exercise
              ? 'Previous performance'
              : 'Previous session',
          enabled: widget.onOlder != null,
          onPressed: widget.onOlder ?? () {},
        ),
        const SizedBox(width: AppSpacing.xs),
        // The phrase keeps every point between the arrows: the mode radios
        // have a row of their own under it (2026-10-23).
        Expanded(child: phrase),
        const SizedBox(width: AppSpacing.xs),
        SessionChevronButton(
          key: const ValueKey('session-date-bar-newer'),
          icon: Icons.chevron_right,
          semanticsLabel: widget.mode == SessionDateMode.exercise
              ? 'Next performance'
              : 'Next session',
          enabled: widget.onNewer != null,
          onPressed: widget.onNewer ?? () {},
        ),
      ],
    );

    // One stack is the stage's fact, not something to name: no toggle, no
    // radios — just the date.
    final content = widget.onToggleMode == null
        ? dateRow
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dateRow,
              // The pair hugs its words — a Row sizes to its children — and
              // stands centred under the date, inside the same box: one
              // control, read top to bottom (2026-10-23).
              _modeRadios(),
            ],
          );

    return Container(
      key: const ValueKey('session-date-bar'),
      // One inset all round, the lab date bar's own: an arrow stands at each
      // edge, and the phrase sits between them rather than in whatever room
      // they leave. The radios ride inside the same box, under the date, so
      // the selector is one thing (2026-10-23).
      padding: const EdgeInsets.all(5),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: content,
    );
  }
}
