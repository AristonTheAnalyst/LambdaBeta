import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/session.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/confirm_delete_session_dialog.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/floating_bar.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/planned_banner.dart';
import '../../../shared/widgets/session_log_card.dart';
import '../../../shared/widgets/reflection_summary.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_bookend.dart';
import '../../../shared/widgets/session_date_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/section_divider.dart';
import '../../logs/view/logs_screen.dart';
import '../../logs/viewmodel/session_detail_viewmodel.dart';
import '../model/past_session_seed.dart';
import '../model/session_local_state.dart';
import '../viewmodel/session_viewmodel.dart';
import 'foreign_session_preview.dart';
import 'live_exercise_card.dart';
import 'session_history_peek.dart';
import 'ratings_sheet.dart';
import 'session_stats_bar.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../../shared/widgets/user_name_text.dart';

/// Whether a re-tap of the Session nav tab moves the wizard to its browse
/// (2026-10-23).
///
/// The tab re-tap is how the user reads past sessions while one is live: the
/// wizard stops at Home — the embedded Training Logs browse — and the
/// session keeps running underneath, since nothing ends a session but Finish
/// (or Cancel). Only the two pages a live session actually shows can step
/// away to it: Training and Summary. Home is already the browse, the
/// pre-questionnaire has nothing live to leave, and the post-questionnaire is
/// a one-way door — the session has already ended, and Done is the only way
/// off it.
bool browseOnSessionTabRetap({required bool live, required int page}) =>
    live &&
    (page == SessionViewModel.kTrainingPage ||
        page == SessionViewModel.kSummaryPage);

/// The storey the shell floats above its nav bar: the another-device notice
/// while it is showing (2026-10-27). Null whenever there is no notice — the
/// wizard is the only writer.
///
/// The notice belongs to the branch's floor rather than to any one page, so
/// the wizard hands it to the shell instead of drawing it in its own column:
/// a strip in the page's flow pushed the wizard's pages down while the nav
/// bar stayed floating over them, and the two disagreed about where the floor
/// was. The shell puts whatever this holds into
/// [ScrollShrinkNavBar.aboveBar], which also makes every page clear it
/// through [ScrollShrinkNavBar.contentInset] for free.
final ValueNotifier<Widget?> sessionAboveBarNotice = ValueNotifier(null);

/// Whether the another-device notice belongs on the wizard's [page]
/// (2026-10-27): only the screens **before** the live one — Home and the
/// pre-questionnaire. A live session's own pages (Training, Summary, the
/// post-questionnaire) never carry it: the notice is a door to start from,
/// and a strip over the sets being logged is exactly the unsightliness this
/// moved to fix.
@visibleForTesting
bool showsForeignSessionNotice({required bool hasForeign, required int page}) =>
    hasForeign && page <= SessionViewModel.kPreQuestionnairePage;

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    this.viewModel,
    this.sessionShellSignals = true,
    this.reselectSignal,
    this.openRecord,
  });

  /// The VM the screen drives. Injected by coach mode, which owns an
  /// athlete-scoped VM for the whole page (2026-10-28); null means this is the
  /// signed-in user's Session tab and the static cache is used.
  final SessionViewModel? viewModel;

  /// Whether this screen owns the main shell's session signals
  /// (`sessionAboveBarNotice`, `AppRouter.sessionTabReselected`). The real tab
  /// does; coach mode does not — it has its own local reselect signal and must
  /// never clear the notice the main tab left floating (2026-10-28).
  final bool sessionShellSignals;

  /// The re-tap signal; defaults to the main shell's. Coach mode passes its
  /// own so a re-tap does not reach the tab underneath (2026-10-28).
  final ValueListenable<int>? reselectSignal;

  /// How a record is opened from this screen's list or recap. Null keeps the
  /// default `/logs/:id` route; coach mode pushes its own viewer (2026-10-28).
  final void Function(String sessionId)? openRecord;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver, RouteAware {
  static SessionViewModel? _cachedVm;

  static void _clearCachedVm() => _cachedVm = null;

  /// Releases the cached ViewModel on sign-out — the local DB is being
  /// cleared, so the next sign-in must build fresh.
  static void _resetCachedVmOnSignOut() {
    final vm = _cachedVm;
    _cachedVm = null;
    vm?.dispose();
  }

  late final SessionViewModel _vm;

  /// The re-tap signal this screen listens to (see [SessionScreen.
  /// reselectSignal]).
  late final ValueListenable<int> _reselect;

  /// Whether this screen created the VM (the self tab's cached one). An
  /// injected coach VM belongs to its shell and must not be cleared by this
  /// screen's sign-out hook or its dispose (2026-10-28).
  bool _ownsVm = false;

  /// The questionnaire note fields.
  ///
  /// The cached ViewModel outlives this State across tab switches, but a
  /// controller does not: rebuilt empty, the field would read blank while
  /// `vm.startNotes` still held the text — notes the user can no longer see,
  /// which a later Start would still write. So every mount re-seeds the
  /// controllers from the VM.
  late final TextEditingController _startNotesCtrl;
  late final TextEditingController _endNotesCtrl;

  /// The name the Training header should carry while a completed record is
  /// hosted on the page (2026-10-23): the SESSION walk swaps the card and the
  /// floor, so the header's title alone follows onto the record — its plan-name
  /// snapshot, or Freestyle. Null on today, where the live session's own name
  /// is the title. Written by [_TrainingPage], read here in the header.
  final ValueNotifier<String?> _peekTitle = ValueNotifier(null);

  /// Whether something is pushed over the wizard — the another-device preview.
  /// The notice hides while it is: the preview's own Switch bar is the door,
  /// and two doors to the same session stacked on one floor would read as two
  /// different offers.
  bool _wizardCovered = false;

  /// Recomputes what the shell floats above its nav bar (2026-10-27): the
  /// another-device notice on the screens before the live one, nothing
  /// anywhere else. Driven by the VM (the foreign list) and the pager (the
  /// wizard step), so a page change or a session ending elsewhere moves the
  /// storey with the page — never a rebuild of the wizard itself.
  void _syncAboveBarNotice() {
    if (!widget.sessionShellSignals) return;
    final show =
        showsForeignSessionNotice(
          hasForeign: _vm.foreignActiveSessions.isNotEmpty,
          page: _vm.slidePagesController.currentPage,
        ) &&
        !_wizardCovered;
    // Only the show/hide edge is written: a widget of the same shape would
    // rebuild the shell for nothing, and the notice watches the VM itself for
    // the words and the buttons.
    if (show && sessionAboveBarNotice.value == null) {
      sessionAboveBarNotice.value = _ForeignSessionNotice(
        vm: _vm,
        onPreview: _openForeignPreview,
      );
    } else if (!show && sessionAboveBarNotice.value != null) {
      sessionAboveBarNotice.value = null;
    }
  }

  /// Opens the another-device session read-only (2026-10-15). The push is
  /// this screen's — the tab branch's navigator — because the notice does not
  /// own one: it floats in the shell, above the branch, where the nearest
  /// navigator is the root's, and a root push would hide the shell's bar
  /// under the preview instead of floating over it, leaving the Switch band
  /// to clear nothing (2026-10-27).
  void _openForeignPreview(Session foreign) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForeignSessionPreviewScreen(session: foreign, vm: _vm),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injected = widget.viewModel;
    if (injected != null) {
      // Coach mode owns this VM for the page (2026-10-28): never cached,
      // never handed to the sign-out reset, never disposed here. Two live
      // identities never share the static slot.
      _vm = injected;
    } else {
      _ownsVm = true;
      ps.onSignOutReset = _resetCachedVmOnSignOut;
      _vm = _cachedVm ?? SessionViewModel();
      if (_cachedVm == null) {
        _cachedVm = _vm;
        _vm.onWorkoutEnded = _clearCachedVm;
      } else {
        // Reuse across hot reload — workout state stays intact.
        // Tab re-entry recreates this State (and its PageView); a freshly
        // attached PageView always starts at page 0, silently dumping the
        // user back on Prep — whose header has no Back button. Re-anchor the
        // pager at the wizard step they left, before the new PageView
        // attaches.
        _vm.slidePagesController.restorePageView();
        // Belt to restorePageView's braces: re-assert the remembered step
        // once the new PageView is attached, so a mis-anchored attach can
        // never dump the user back on the wizard's first page. A no-op when
        // the restore held.
        final restoredPage = _vm.slidePagesController.currentPage;
        // Returning to the tab: refresh the current program / planned workout
        // so a newly created or begun program shows without a full restart.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _vm.slidePagesController.slideToPage(restoredPage);
            _vm.refreshCatalog(); // always refresh exercise/variation catalog
            _vm.refreshProgram();
          }
        });
      }
    }
    _startNotesCtrl = TextEditingController(text: _vm.startNotes);
    _endNotesCtrl = TextEditingController(text: _vm.endNotes);
    // The shell's tab bar lives outside this screen, so a re-tap of the
    // Session tab arrives as a signal rather than a callback (2026-10-23).
    // Coach mode passes its own signal — the main shell's is not its to fire.
    _reselect = widget.reselectSignal ?? AppRouter.sessionTabReselected;
    _reselect.addListener(_onSessionTabReselected);
    if (widget.sessionShellSignals) {
      // The notice is a shell storey (2026-10-27): the shell cannot read this
      // screen's VM, so the two feeds it follows are watched here and only
      // the notifier is written — no setState, and the wizard itself stays
      // rebuild-free (2026-10-13).
      _vm.addListener(_syncAboveBarNotice);
      _vm.slidePagesController.addListener(_syncAboveBarNotice);
      // First paint is deferred: the shell is building this screen, and
      // writing a notifier its ancestor listens to mid-build would mark it
      // dirty inside its own build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAboveBarNotice();
      });
    }
    // No whole-screen listener: rebuilds are scoped to the widgets that read
    // the VM (per-page ListenableBuilders below) instead of one setState over
    // the entire wizard per notify (2026-10-13).
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route-return refresh — edits made in the past-session viewer must show
    // in the reflection surfaces (Summary's recap, the questionnaire's Last
    // Session toggle) when the user comes back.
    AppRouter.routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    // Something covers the wizard — the another-device preview. Its own
    // Switch bar is the offer now; the notice steps aside (2026-10-27).
    _wizardCovered = true;
    _syncAboveBarNotice();
  }

  @override
  void didPopNext() {
    // Back on the wizard: the storey returns if it still applies (2026-10-27).
    _wizardCovered = false;
    _syncAboveBarNotice();
    // A refresh, not a new browse: the Home list reloads itself on the same
    // pop (LogsScreen is a route-observer subscriber too), so the only thing
    // a version bump could add here is a remount — and with it the loss of
    // the scroll position and filters the user left behind (2026-10-25).
    _vm.refreshShownReflection(bumpVersion: false);
  }

  @override
  void dispose() {
    AppRouter.routeObserver.unsubscribe(this);
    _reselect.removeListener(_onSessionTabReselected);
    if (widget.sessionShellSignals) {
      _vm.removeListener(_syncAboveBarNotice);
      _vm.slidePagesController.removeListener(_syncAboveBarNotice);
      // The shell outlives this screen; a notice left behind would float over
      // whichever branch is showing next (2026-10-27). Coach mode must never
      // clear the main tab's notice (2026-10-28).
      sessionAboveBarNotice.value = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsVm && ps.onSignOutReset == _resetCachedVmOnSignOut) {
      ps.onSignOutReset = null;
    }
    _startNotesCtrl.dispose();
    _endNotesCtrl.dispose();
    // The Training page's State disposes before this one (children first), so
    // nothing listens by now — the notifier is simply spent.
    _peekTitle.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Commit is blur-only — backgrounding the app (or a hard kill right
    // after) must not lose typed set values. paused/inactive both fire on
    // the way to the background; detached covers a terminated app.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _vm.flushPendingCommits();
    }
  }

  /// The Session nav tab was re-tapped while the wizard was already on
  /// screen (2026-10-23): the user wants to read past sessions, not end
  /// this one. Slides to Home — the embedded Training Logs browse — and
  /// leaves the live session exactly as it is; Home's header swaps Start
  /// for Resume, which lands back on Training. [browseOnSessionTabRetap]
  /// holds the guard (no live session, Home already, the one-way post page).
  void _onSessionTabReselected() {
    if (!mounted ||
        !browseOnSessionTabRetap(
          live: _vm.hasActiveWorkout,
          page: _vm.slidePagesController.currentPage,
        )) {
      return;
    }
    // Typed set values commit on blur or the debounce — leaving the page
    // must not swallow the text under the cursor, the same flush every
    // wizard step takes.
    FocusManager.instance.primaryFocus?.unfocus();
    _vm.flushPendingCommits();
    _vm.slidePagesController.slideToPage(SessionViewModel.kSessionHomePage);
  }

  // ── Modals ─────────────────────────────────────────────────────────────────

  /// Wizard step: training → summary recap. Shows THIS SESSION first.
  void _goToSummary() {
    // Blur any focused set cell first — its typed value commits on focus
    // loss, and navigating away must not swallow it.
    FocusManager.instance.primaryFocus?.unfocus();
    // Real rows commit per keystroke, but draft rows commit on blur only —
    // flush them explicitly so a draft being typed isn't lost if the
    // Training page unmounts during the slide.
    _vm.flushPendingCommits();
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    _vm.showCurrentReflection();
    _vm.slidePagesController.slideToPage(SessionViewModel.kSummaryPage);
  }

  /// Summary's Finish Session — ends the session and slides to the
  /// post-questionnaire page.
  Future<void> _finishFromSummary() async {
    FocusManager.instance.primaryFocus?.unfocus();
    // Same as _goToSummary — commit any draft rows being typed before
    // the end flow prunes and finalizes.
    _vm.flushPendingCommits();
    if (_vm.sets.isEmpty) {
      _showNoSetsDialog();
      return;
    }
    await _vm.finishSession();
    // The VM resets endNotes but the controller would keep the old text —
    // clear it so this session's post-notes field starts empty.
    _endNotesCtrl.clear();
  }

  /// Post-questionnaire Done — writes the post answers, lands Home, and
  /// clears the pre answers so the next session's questionnaire starts
  /// blank.
  Future<void> _completePost() async {
    await _vm.completePostQuestionnaire();
    _startNotesCtrl.clear();
  }

  /// The floor bar's pencil: the same four answers the pre/post wizard pages
  /// collect, in one sheet. Edits go through the VM's own setters, and the
  /// notes are mirrored into the wizard's controllers, so closing the sheet
  /// never leaves a page disagreeing with what was just typed (2026-10-22).
  void _openRatings() {
    final vm = _vm;
    showSessionRatingsSheet(
      context,
      preFeeling: vm.sessionFeeling,
      preNotes: vm.startNotes,
      postFeeling: vm.endFeeling,
      postNotes: vm.endNotes,
      onPreFeelingChanged: vm.setSessionFeeling,
      onPreNotesChanged: (v) {
        vm.startNotes = v;
        _mirrorNotes(_startNotesCtrl, v);
      },
      onPostFeelingChanged: vm.setEndFeeling,
      onPostNotesChanged: (v) {
        vm.endNotes = v;
        _mirrorNotes(_endNotesCtrl, v);
      },
    );
  }

  /// Assign only when the text actually differs, and place the caret at the
  /// end — a plain `.text` write leaves the selection stale.
  void _mirrorNotes(TextEditingController controller, String text) {
    if (!mounted || controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _showNoSetsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'No Sets Logged',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Text(
          "You haven't logged any sets yet. Log at least one set before ending, or cancel the workout instead.",
          style: TextStyle(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Got It',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Coach mode's way out of a live session (2026-10-28): it ends, it never
  /// discards. The session is saved for the athlete with `end_datetime`; the
  /// wizard then carries on to the post-questionnaire exactly as Finish does.
  void _confirmEndWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'End Session',
          style: TextStyle(color: AppColors.primary),
        ),
        content: Text(
          'End this session? It is saved for the athlete — coach mode never '
          'discards a session.',
          style: TextStyle(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep Going',
              style: TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vm.finishSession();
            },
            child: Text(
              'End session',
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveExercise(int index) {
    final slot = _vm.exerciseSlots[index];
    // Get the display name for the first exercise in the slot
    final exerciseId = slot.activeExerciseId;
    final name = toProperCase(_vm.exerciseDisplayName(exerciseId));
    final setCount = _vm.sets
        .where((s) => slot.exerciseIds.contains(s.exerciseId))
        .length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Exercise',
          style: TextStyle(color: AppColors.danger),
        ),
        content: Text(
          'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.',
          style: TextStyle(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep',
              style: TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vm.removeExerciseSlot(index);
            },
            child: Text(
              'Remove',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancelWorkout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Cancel Session',
          style: TextStyle(color: AppColors.danger),
        ),
        content: Text(
          'Discard this workout and all logged sets?',
          style: TextStyle(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep Going',
              style: TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vm.cancelSession();
            },
            child: Text(
              'Discard',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // The keyboard paints over the page instead of shoving it up
      // (2026-10-25): the floor bar keeps the date bar and the PR/notes tiles
      // exactly where they are, and a scrolling page shrinks its viewport to
      // the keyboard's top instead. The shell opts out with this Scaffold
      // ([shellResizesForKeyboard]), or its nav bar would ride up anyway.
      resizeToAvoidBottomInset: false,
      // The whole-screen listener is gone: this builder scopes rebuilds to
      // the body subtree that actually reads the VM. The win is the notify
      // count — keystrokes debounce into one settle, so this fires per
      // settle instead of per keystroke (2026-10-13).
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => Stack(
          children: [
            _vm.initLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      ListenableBuilder(
                        listenable: _vm.slidePagesController,
                        builder: (context, _) {
                          final page = _vm.slidePagesController.currentPage;
                          // The header IS the wizard nav: title names the step, the
                          // left button steps back (or cancels), the right advances.
                          // Once started, Training's title is the bound template's
                          // name (freestyle keeps the generic title).
                          //
                          // While the SESSION walk hosts a completed record on the
                          // Training page, the title follows that record instead
                          // (2026-10-23): `peekTitle` is the record's own name —
                          // its plan-name snapshot, or Freestyle — so the header
                          // names what the card and floor are drawing, and goes
                          // back to the live name when the walk returns to today.
                          return ValueListenableBuilder<String?>(
                            valueListenable: _peekTitle,
                            builder: (context, peekTitle, _) {
                              final title = switch (page) {
                                SessionViewModel.kTrainingPage =>
                                  _vm.hasActiveWorkout
                                      ? (peekTitle ??
                                            _vm.selectedPlannedSession?.name ??
                                            _vm
                                                .selectedStandaloneWorkout
                                                ?.name ??
                                            'Freestyle Session')
                                      : 'Training Session',
                                SessionViewModel.kPreQuestionnairePage =>
                                  'Pre-Evaluation',
                                SessionViewModel.kSessionHomePage => 'Sessions',
                                _ => 'Session Reflection',
                              };
                              return PageHeader(
                                title: title,
                                // The Training page's idle title IS the session
                                // selector (2026-10-23): the picker lives in the
                                // header, not in a body card, so the page opens
                                // straight onto the preview. An active session
                                // keeps the plain name — a template cannot change
                                // mid-session.
                                titleWidget:
                                    page == SessionViewModel.kTrainingPage &&
                                        !_vm.hasActiveWorkout
                                    ? _TrainingHeaderSelector(
                                        vm: _vm,
                                        onTap: () => _showWorkoutPickerSheet(
                                          context,
                                          _vm,
                                        ),
                                      )
                                    : null,
                                left: switch (page) {
                                  // Home has nothing to go back to; the
                                  // post-questionnaire is a one-way door (the
                                  // session has already ended).
                                  SessionViewModel.kSessionHomePage ||
                                  SessionViewModel.kPostQuestionnairePage =>
                                    null,
                                  // Pre-questionnaire: plain back — nothing was
                                  // created yet.
                                  SessionViewModel.kPreQuestionnairePage =>
                                    HeaderIconButton(
                                      icon: Icons.arrow_back_ios_new,
                                      semanticsLabel: 'Back',
                                      glyphSize: 18,
                                      color: AppColors.primary,
                                      onPressed: () =>
                                          _vm.slidePagesController.slideToPage(
                                            SessionViewModel.kSessionHomePage,
                                          ),
                                    ),
                                  // Training: Cancel when active; Back to the
                                  // questionnaire when idle.
                                  SessionViewModel.kTrainingPage =>
                                    _vm.hasActiveWorkout
                                        ? (_vm.canDelete
                                              ? HeaderIconButton(
                                                  // A red X, not the square stop
                                                  // glyph (2026-10-23): the
                                                  // square read as "pause/stop
                                                  // the timer", the X reads as
                                                  // "close this session".
                                                  icon: Icons.close,
                                                  semanticsLabel:
                                                      'Cancel workout',
                                                  color: AppColors.danger,
                                                  onPressed:
                                                      _confirmCancelWorkout,
                                                )
                                              : HeaderIconButton(
                                                  // Coach mode has no discard
                                                  // (2026-10-28): the tick ends
                                                  // the session, never deletes
                                                  // it.
                                                  icon: Icons.check,
                                                  semanticsLabel: 'End session',
                                                  color: AppColors.success,
                                                  onPressed:
                                                      _confirmEndWorkout,
                                                ))
                                        : HeaderIconButton(
                                            icon: Icons.arrow_back_ios_new,
                                            semanticsLabel: 'Back',
                                            glyphSize: 18,
                                            color: AppColors.primary,
                                            onPressed: () {
                                              // Home/pre-Q always shows the latest
                                              // completed session — a THIS SESSION
                                              // position from the summary page can't
                                              // leak onto it.
                                              _vm.showLatestReflection();
                                              _vm.slidePagesController
                                                  .slideToPage(
                                                    SessionViewModel
                                                        .kPreQuestionnairePage,
                                                  );
                                            },
                                          ),
                                  // Summary: resume training (the back-door).
                                  _ => HeaderIconButton(
                                    icon: Icons.arrow_back_ios_new,
                                    semanticsLabel: 'Back',
                                    glyphSize: 18,
                                    color: AppColors.primary,
                                    onPressed: () =>
                                        _vm.slidePagesController.slideToPage(
                                          SessionViewModel.kTrainingPage,
                                        ),
                                  ),
                                },
                                // Wizard path: START (Home) → questionnaire →
                                // CONTINUE → choose workout → START (Training) →
                                // FINISH → summary → FINISH SESSION → post
                                // questionnaire → DONE → Home.
                                right: switch (page) {
                                  // With a session live, Home is the browse the
                                  // Session tab's re-tap opens, and the door turns
                                  // around: Start would begin a SECOND session, so
                                  // the control reads Resume — the word alone, no
                                  // glyph (2026-10-23): it is the one primary
                                  // action on the browse, and the word is the
                                  // whole of it. Returns to Training, leaving the
                                  // session untouched.
                                  SessionViewModel.kSessionHomePage =>
                                    _vm.hasActiveWorkout
                                        ? GlassButton(
                                            label: 'Resume',
                                            color: AppColors.success,
                                            compact: true,
                                            onPressed: () => _vm
                                                .slidePagesController
                                                .slideToPage(
                                                  SessionViewModel
                                                      .kTrainingPage,
                                                ),
                                          )
                                        : HeaderIconButton(
                                            icon: Icons.add,
                                            semanticsLabel: 'Start',
                                            glyphSize: 22,
                                            color: AppColors.success,
                                            onPressed: () => _vm
                                                .slidePagesController
                                                .slideToPage(
                                                  SessionViewModel
                                                      .kPreQuestionnairePage,
                                                ),
                                          ),
                                  SessionViewModel.kPreQuestionnairePage =>
                                    HeaderIconButton(
                                      icon: Icons.arrow_forward_ios,
                                      semanticsLabel: 'Continue',
                                      glyphSize: 18,
                                      color: AppColors.success,
                                      onPressed: () =>
                                          _vm.slidePagesController.slideToPage(
                                            SessionViewModel.kTrainingPage,
                                          ),
                                    ),
                                  SessionViewModel.kTrainingPage =>
                                    _vm.hasActiveWorkout
                                        ? HeaderIconButton(
                                            icon: Icons.arrow_forward_ios,
                                            semanticsLabel: 'Summary',
                                            glyphSize: 18,
                                            color: AppColors.success,
                                            onPressed: _goToSummary,
                                          )
                                        : HeaderIconButton(
                                            icon: Icons.play_arrow,
                                            semanticsLabel: 'Start workout',
                                            glyphSize: 22,
                                            color: AppColors.success,
                                            onPressed: _vm.startWorkout,
                                          ),
                                  SessionViewModel.kSummaryPage =>
                                    _vm.hasActiveWorkout
                                        ? HeaderIconButton(
                                            icon: Icons.check,
                                            semanticsLabel: 'End workout',
                                            glyphSize: 22,
                                            color: AppColors.success,
                                            onPressed: _finishFromSummary,
                                          )
                                        : null,
                                  _ => HeaderIconButton(
                                    icon: Icons.check,
                                    semanticsLabel: 'Done',
                                    glyphSize: 22,
                                    color: AppColors.success,
                                    onPressed: _completePost,
                                  ),
                                },
                              );
                            },
                          );
                        },
                      ),
                      if (_vm.error != null)
                        GestureDetector(
                          onTap: _vm.clearError,
                          child: Container(
                            width: double.infinity,
                            color: AppColors.dangerBg,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                            child: Text(
                              _vm.error!,
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: AppTextStyles.sm,
                              ),
                            ),
                          ),
                        ),
                      // The another-device notice is NOT drawn here
                      // (2026-10-27): it floats above the nav bar as a shell
                      // storey ([sessionAboveBarNotice]), so the wizard's
                      // pages keep their full height and clear it through the
                      // same content inset that clears the bar.
                      Expanded(
                        // Key keeps the SlidePages element stable across rebuilds —
                        // otherwise the PageView is recreated and its page position
                        // resets to Prep.
                        key: const ValueKey('sessionPages'),
                        child: SlidePages(
                          controller: _vm.slidePagesController,
                          // Strict wizard: steps advance via the header buttons and
                          // (unlocked) tabs only — no swipe navigation.
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _HomePage(
                              vm: _vm,
                              openRecord: widget.openRecord,
                            ),
                            _PreEvaluationPage(
                              vm: _vm,
                              startNotesCtrl: _startNotesCtrl,
                              openRecord: widget.openRecord,
                            ),
                            _TrainingPage(
                              vm: _vm,
                              peekTitle: _peekTitle,
                              // Coach mode never removes an exercise
                              // (2026-10-28): the picker's Remove is not drawn.
                              onRemoveExercise: _vm.canDelete
                                  ? _confirmRemoveExercise
                                  : null,
                              onOpenRatings: _openRatings,
                            ),
                            _SummaryPage(
                              vm: _vm,
                              openRecord: widget.openRecord,
                            ),
                            _PostQuestionnairePage(
                              vm: _vm,
                              notesCtrl: _endNotesCtrl,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

/// The another-device notice (2026-10-15) — a floating message above the nav
/// bar while a live session started on ANOTHER device exists (2026-10-27; a
/// strip in the page's flow until then). It never acts on its own: **Preview**
/// opens the session read-only, and **Stay** dismisses every foreign session
/// it is showing, for the rest of the run.
///
/// The shell draws it from [sessionAboveBarNotice], outside the wizard's
/// build, so the widget watches the VM itself — a Stay, a switch or a foreign
/// session ending elsewhere re-words it in place. The open is the wizard's
/// ([onPreview]): the shell's own context sits above the tab branch's
/// navigator, and the preview has to land inside it, under the floating bar
/// rather than over it.
class _ForeignSessionNotice extends StatelessWidget {
  const _ForeignSessionNotice({required this.vm, required this.onPreview});

  final SessionViewModel vm;

  /// Opens the session read-only, in the wizard's navigator.
  final ValueChanged<Session> onPreview;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        // The newest is the one a Switch takes; extra ones only change the
        // wording.
        final foreign = [...vm.foreignActiveSessions]
          ..sort((a, b) => b.createdDatetime.compareTo(a.createdDatetime));
        if (foreign.isEmpty) return const SizedBox.shrink();
        final latest = foreign.first;
        final started = DateFormat.jm().format(
          latest.createdDatetime.toLocal(),
        );
        // The nav bar's own container, one storey up: the floor reads as one
        // surface whatever is standing on it (2026-10-27).
        return FloatingGlass(
          radius: FloatingBar.cornerRadius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  foreign.length > 1
                      ? 'Sessions are live on other devices — the newest '
                            'started $started.'
                      : 'A session is live on another device — started '
                            '$started.',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nothing syncs on its own — preview it, then switch if you '
                  'want it here.',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    GlassButton(
                      label: 'Preview',
                      compact: true,
                      onPressed: () => onPreview(latest),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    GlassButton(
                      label: 'Stay',
                      compact: true,
                      onPressed: () {
                        for (final s in foreign) {
                          vm.dismissForeignSession(s.sessionId);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Page 0: Home ──────────────────────────────────────────────────────────────

/// The wizard's landing page — the ALL SESSIONS browse: the full logs view
/// (filters on top, session cards below; a card opens the past-session
/// viewer) fills the page, with Start (header) kicking off the
/// active-session flow. With a session live it is also the browse a re-tap
/// of the Session tab opens, and the header's door reads Resume instead
/// (2026-10-23). Keyed by the past-sets version so a session that starts or
/// ends remounts it with fresh data; a refresh that only re-reads (a delete,
/// a return from the viewer) leaves the key alone and keeps the scroll
/// position and filters (2026-10-25).
class _HomePage extends StatelessWidget {
  const _HomePage({required this.vm, this.openRecord});

  final SessionViewModel vm;

  /// How a record opens; null keeps the default `/logs/:id` route. Coach mode
  /// pushes its own viewer (2026-10-28).
  final void Function(String sessionId)? openRecord;

  @override
  Widget build(BuildContext context) {
    return LogsScreen(
      key: ValueKey('home-logs-${vm.pastSetsVersion}'),
      showHeader: false,
      // The list is the VM's owner's — the athlete's in coach mode, whose
      // deletes are hidden while every other action stays live (2026-10-28).
      userId: vm.userId,
      canDelete: vm.canDelete,
      onOpenSession: openRecord,
      // A deleted session must leave the reflection card too — the recap
      // and the live PR baselines both read the VM's timeline, which only
      // this list's own reload doesn't touch. The reload is asked for
      // WITHOUT a version bump: the list already reloaded itself from the
      // same fresh read (LogsViewModel.deleteSession), so a bump would only
      // remount the browse at offset 0 and drop its filters.
      onSessionDeleted: (_) => vm.refreshShownReflection(bumpVersion: false),
    );
  }
}

// ── Page 1: Pre-Evaluation ───────────────────────────────────────────────────

/// The fillable pre-workout questionnaire — rating + notes, centered
/// vertically. Nothing here writes to the DB; the answers are captured at
/// session creation (Training's Start). A small toggle right under the
/// notes question swaps the CENTERED content in place for the previous
/// session's answers (marked as coming from the last session) — the layout
/// frame never changes.
class _PreEvaluationPage extends StatefulWidget {
  const _PreEvaluationPage({
    required this.vm,
    required this.startNotesCtrl,
    this.openRecord,
  });

  final SessionViewModel vm;
  final TextEditingController startNotesCtrl;

  /// How the "last session" card opens a record; null keeps the default
  /// route. Coach mode passes its viewer (2026-10-28).
  final void Function(String sessionId)? openRecord;

  @override
  State<_PreEvaluationPage> createState() => _PreEvaluationPageState();
}

class _PreEvaluationPageState extends State<_PreEvaluationPage> {
  bool _showLastSession = false;

  SessionViewModel get vm => widget.vm;

  @override
  Widget build(BuildContext context) {
    final lastSession = vm.reflectionSession;
    return Column(
      children: [
        Expanded(
          child: Padding(
            // The keyboard shrinks the scrolling viewport to its own top
            // instead of lifting the page (2026-10-25): the notes field is
            // revealed inside the viewport, so a viewport ending above the
            // keyboard is what keeps the field clear of it.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  ScrollShrinkNavBar.contentInset(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // One of the two fills the SAME slot — previewing the
                    // last session hides the fillable form entirely.
                    if (!_showLastSession)
                      _FeelingForm(
                        rating: vm.sessionFeeling,
                        onRatingChanged: vm.setSessionFeeling,
                        notesCtrl: widget.startNotesCtrl,
                        onNotesChanged: (v) => vm.startNotes = v,
                        placeholder:
                            'Sleep and eat well?\nHydrated?\nGoals today?',
                        question: 'How well do you think you\'re going to do',
                        notesLabel: 'Why do you feel that way',
                      )
                    else if (lastSession != null)
                      _lastSessionPreview(lastSession),
                    if (lastSession != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _showLastSession = !_showLastSession,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: glassBox(AppColors.primary),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showLastSession
                                      ? Icons.arrow_back
                                      : Icons.history,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showLastSession ? 'Back' : 'Last Session',
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.xs,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The previous session's answers, read back with the same
  /// wording/styling as the live form — clearly marked as not this
  /// session's.
  Widget _lastSessionPreview(Session session) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 11, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(
                'FROM LAST SESSION',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SessionBookend(
            label: 'PRE-WORKOUT',
            feeling: session.preFeeling,
            notes: session.preNotes,
            emptyNotes: 'No pre-workout notes',
            question: 'How well do you think you\'re going to do',
            notesLabel: 'Why do you feel that way',
          ),
          const SizedBox(height: AppSpacing.lg),
          SessionBookend(
            label: 'POST-WORKOUT',
            feeling: session.feeling,
            notes: session.postNotes,
            emptyNotes: 'No post-workout notes',
            question: 'How well did you do this session',
            notesLabel: 'What could have made this session better',
          ),
        ],
      ),
    );
  }
}

// ── Shared prep/reflection pieces (two pages of ONE screen, so these stay
// file-level private rather than in shared/widgets — that folder is for
// components spanning the three screens) ──────────────────────────────────

/// Centered section label with a hairline rule on both sides — the
/// The questionnaire form — rating question, rating, notes question + input.
/// The exact prep-page block; the reflection page reuses it for POST-WORKOUT
/// so the two pages can never drift apart. Pre and post pass their own
/// [question]/[notesLabel] copy.
class _FeelingForm extends StatelessWidget {
  const _FeelingForm({
    required this.rating,
    required this.onRatingChanged,
    required this.notesCtrl,
    required this.onNotesChanged,
    required this.placeholder,
    required this.question,
    required this.notesLabel,
  });

  final int? rating;
  final ValueChanged<int?> onRatingChanged;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onNotesChanged;
  final String placeholder;
  final String question;
  final String notesLabel;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        question,
        style: TextStyle(
          fontSize: AppTextStyles.sm,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      FeelingRating(value: rating, onChanged: onRatingChanged),
      const SizedBox(height: AppSpacing.lg),
      LambdaInput(
        controller: notesCtrl,
        label: notesLabel,
        placeholder: placeholder,
        onChanged: onNotesChanged,
      ),
    ],
  );
}

/// The session viewer shared by the prep page (PREVIOUS SESSION) and the
/// reflection page (THIS SESSION). Card 1 — all-sessions picker, pager
/// chevrons, planned source — taps through to the past-session viewer
/// (disabled for the still-active session); card 2 holds the PRS/NOTES
/// reflection; card 3 shows the session's pre/post bookends. Chevrons page
/// left = older, right = newer without leaving the page.
class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({
    required this.vm,
    this.showPostBookend = true,
    this.openRecord,
  });

  final SessionViewModel vm;

  /// How the shown record opens; null keeps the `/logs/:id` route. Coach mode
  /// pushes its own viewer (2026-10-28).
  final void Function(String sessionId)? openRecord;

  /// Whether card 3 renders the POST-WORKOUT bookend. False while the
  /// current (still-active) session is shown — its post rating/notes are
  /// being entered in the form above, not stored yet.
  final bool showPostBookend;

  @override
  Widget build(BuildContext context) {
    final session = vm.reflectionSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: session identity — pager, planned source, feeling.
        // Tapping opens the shown session in the past-session viewer.
        AppCard(
          // The still-active session must not open the past-session viewer —
          // its edit mode would let the user change sets the live VM doesn't
          // know about mid-workout.
          onTap: session == null || vm.reflectionIsCurrent
              ? null
              : () async {
                  final open = openRecord;
                  if (open != null) {
                    open(session.sessionId);
                  } else {
                    await context.push(
                      '/logs/${session.sessionId}',
                      extra: AppRouter.fromLiveExtra,
                    );
                  }
                  // Note/feeling edits made in the past-session viewer show
                  // immediately when the viewer card recomputes on return —
                  // without re-keying the Home browse underneath (it reloads
                  // itself on the same pop).
                  vm.refreshShownReflection(bumpVersion: false);
                },
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    // The shown session's date anchors the pager.
                    child: Text(
                      session == null
                          ? ''
                          // Local, like the card it describes and the
                          // viewer's date bar (2026-10-22).
                          : DateFormat(
                              'MMM d',
                            ).format(session.createdDatetime.toLocal()),
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.caption,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                  // All-sessions picker — jumps the card to any completed
                  // session instead of paging one step at a time.
                  _pagerButton(
                    Icons.list_alt,
                    vm.completedSessionCount > 0,
                    () => _openSessionPicker(context, vm),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _pagerButton(
                    Icons.chevron_left,
                    vm.reflectionCanGoOlder,
                    vm.showOlderReflectionSession,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _pagerButton(
                    Icons.chevron_right,
                    vm.reflectionCanGoNewer,
                    vm.showNewerReflectionSession,
                  ),
                ],
              ),
              // The planned session (if any) this session was started from.
              if (session?.plannedSessionName != null) ...[
                const SizedBox(height: AppSpacing.sm),
                PlannedBanner(name: session!.plannedSessionName!),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Card 2: the PRS and 'NOTES' sections — a separate container; the
        // sections carry their own empty notes.
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ReflectionSummary(
            exerciseIds: vm.reflectionExercises,
            prsByExercise: vm.reflectionPrsByExercise,
            notesByExercise: vm.reflectionNotesByExercise,
            exerciseNameFor: (id) => vm.reflectionExerciseNames[id] ?? '',
          ),
        ),
        if (session != null) ...[
          const SizedBox(height: AppSpacing.md),
          // Card 3: the session's bookends — pre and post ratings and notes,
          // shown after the PRS/NOTES reflection. Always rendered, with the
          // same explicit empty note as the reflection sections ("No
          // pre/post-workout notes") so a sparse session still reads complete.
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SessionBookend(
                  label: 'PRE-WORKOUT',
                  feeling: session.preFeeling,
                  notes: session.preNotes,
                  emptyNotes: 'No pre-workout notes',
                  question: 'How well do you think you\'re going to do',
                  notesLabel: 'Why do you feel that way',
                ),
                if (showPostBookend) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SessionBookend(
                    label: 'POST-WORKOUT',
                    feeling: session.feeling,
                    notes: session.postNotes,
                    emptyNotes: 'No post-workout notes',
                    question: 'How well did you do this session',
                    notesLabel: 'What could have made this session better',
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The all-sessions sheet — training-logs-style rows (date, planned name,
/// exercises × sets, pre/post ratings) that jump the card to the tapped
/// session. Shared by the last-session card and the Home header.
void _openSessionPicker(BuildContext context, SessionViewModel vm) {
  showLambdaModal<void>(
    context,
    fitContent: true,
    // Page background under the rows so the surface cards separate from
    // the sheet itself.
    backgroundColor: AppColors.bg,
    child: _SessionPickerSheet(vm: vm),
  );
}

/// The Training page's "From past session" list (2026-10-26): the same
/// training-log cards, newest first, read for a different verb — the row
/// tapped seeds today's session instead of opening the record.
Future<void> _openPastSessionPicker(BuildContext context, SessionViewModel vm) {
  return showLambdaModal<void>(
    context,
    fitContent: true,
    backgroundColor: AppColors.bg,
    child: _SessionPickerSheet(vm: vm, seedMode: true),
  );
}

/// Bordered pager chevron — the glass recipe when actionable, hairline +
/// muted when disabled — so the enabled state reads as a real button.
Widget _pagerButton(IconData icon, bool enabled, VoidCallback onTap) {
  return GestureDetector(
    // Disabled chevrons still claim the tap with a no-op handler — a
    // GestureDetector with no recognizers lets the tap fall through to the
    // card's PressSquash, which would navigate into the session.
    onTap: enabled ? onTap : () {},
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      // The glass recipe — the same chrome as every other pressable.
      decoration: enabled
          ? glassBox(AppColors.primary, radius: 6)
          : BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
      child: Icon(
        icon,
        size: 20,
        color: enabled ? AppColors.primary : AppColors.muted,
      ),
    ),
  );
}

/// The all-sessions picker sheet — completed sessions newest-first in
/// training-logs style: date, planned pill, exercise × set summaries, and
/// the pre/post ratings (notes are omitted from the preview). Tapping a row
/// selects that session in the viewer card.
///
/// In [seedMode] the list is the Training page's "From past session" door
/// (2026-10-26): the same rows, but a tap hands the record to the view model
/// to repeat, so the card's own verbs (delete, the PR trophy, the current
/// selection) are not drawn — none of them is about picking a record to copy.
class _SessionPickerSheet extends StatefulWidget {
  const _SessionPickerSheet({required this.vm, this.seedMode = false});

  final SessionViewModel vm;

  /// Picking seeds today's session rather than selecting the viewer's
  /// record.
  final bool seedMode;

  @override
  State<_SessionPickerSheet> createState() => _SessionPickerSheetState();
}

class _SessionPickerSheetState extends State<_SessionPickerSheet> {
  /// Null until the first load lands — drives the sheet's spinner.
  List<SessionWithSets>? _sessions;

  /// One global walk per load — the VM's timeline is loaded well before the
  /// picker can be reached (it lives on the Summary page).
  Map<String, Map<String, int>> _prCounts = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Refetches the rows and the trophy counts. Called on open and after a
  /// delete; `deleteCompletedSession` has already rebuilt the VM's timeline
  /// by the time we read the counts, so they can't be stale.
  Future<void> _reload() async {
    final sessions = await widget.vm.loadCompletedSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _prCounts = widget.vm.prCountsByCompletedSession();
    });
  }

  /// The card's ⋮ → Delete Session. Safe from this sheet: the picker lists
  /// completed sessions only, so the in-progress workout can never be the
  /// row behind the menu.
  Future<void> _confirmDelete(SessionWithSets w) async {
    final ok = await confirmDeleteSession(context, setCount: w.sets.length);
    if (!ok || !mounted) return;
    await widget.vm.deleteCompletedSession(w.session.sessionId);
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                widget.seedMode ? 'FROM PAST SESSION' : 'ALL SESSIONS',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
            ),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final list = _sessions;
    if (list == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text(
            widget.seedMode
                ? 'No completed sessions to repeat'
                : 'No completed sessions yet',
            style: TextStyle(
              color: AppColors.inkSecondary,
              fontSize: AppTextStyles.sm,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) => _pickerRow(context, list[i]),
    );
  }

  Widget _pickerRow(BuildContext context, SessionWithSets w) {
    final seedMode = widget.seedMode;
    return SessionLogCard(
      workout: w,
      selected:
          !seedMode &&
          w.session.sessionId == widget.vm.reflectionSession?.sessionId,
      prsByExercise: seedMode
          ? null
          : _prCounts[w.session.sessionId] ?? const {},
      onDelete: seedMode ? null : () => _confirmDelete(w),
      onTap: () async {
        if (seedMode) {
          // Read first, close second: the page behind must never be visible
          // with a Start that would still begin a freestyle session because
          // the seed had not landed yet (2026-10-26).
          await widget.vm.selectPastSession(w);
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          return;
        }
        Navigator.of(context, rootNavigator: true).pop();
        widget.vm.selectReflectionSession(w.session.sessionId);
      },
    );
  }
}

/// The Training page's idle header — the session-template selector as a
/// pill across the title slot (2026-10-23). It opens the same picker
/// sheet the body card used to, so the page opens straight onto the preview
/// and the picker costs the body no space. A selected template wears the
/// planned container (its blue is the plan's provenance); freestyle wears
/// the ghost box. An active session keeps the plain title — a template
/// cannot change mid-session.
class _TrainingHeaderSelector extends StatelessWidget {
  const _TrainingHeaderSelector({required this.vm, required this.onTap});

  final SessionViewModel vm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final planned =
        vm.selectedPlannedSession != null ||
        vm.selectedStandaloneWorkout != null;
    final name =
        vm.selectedPlannedSession?.name ??
        vm.selectedStandaloneWorkout?.name ??
        'Freestyle Session';
    return Semantics(
      button: true,
      label: '$name — choose session',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('training-session-selector'),
        onTap: onTap,
        child: Container(
          // The pill spends the whole title band and the header's own target
          // height (44 — the `HeaderIconButton` bare size), so the bar reads
          // as one row of controls. The band is its ceiling: the 88pt gutters
          // hold the 44pt buttons, so it stays narrower than the card's
          // exercise selector below, which runs the card's full width. The
          // rest of the recipe is the exercise-detail header selector's: the
          // ghost box, 16px w600 ink and the drop arrow, so the app's header
          // selectors are one species. The planned container swaps in while a
          // template is selected — the same pair the session's selector field
          // wears.
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: planned
              ? lambdaBox(ContainerTone.planned, radius: AppRadius.md)
              : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
          child: Row(
            // The field grammar the exercise selector below already wears:
            // the name at the start, the drop arrow at the end. A stretched
            // pill with a floating centred label would read as a button; this
            // reads as the selector it is.
            children: [
              Flexible(
                child: UserNameText(
                  name,
                  tooltip: true,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Page 1: Training ───────────────────────────────────────────────────────────

class _TrainingPage extends StatefulWidget {
  const _TrainingPage({
    required this.vm,
    required this.peekTitle,
    required this.onRemoveExercise,
    required this.onOpenRatings,
  });

  final SessionViewModel vm;

  /// The header's title, while a completed record is hosted in place; the
  /// screen's own notifier, written here as the peek is entered, walked and
  /// left (2026-10-23). Null means today — the live session names the header.
  final ValueNotifier<String?> peekTitle;

  /// Null in coach mode: the exercise picker does not offer Remove there
  /// (2026-10-28).
  final void Function(int index)? onRemoveExercise;

  /// The floor bar's pencil — opened by the screen's State, which holds the
  /// wizard's note controllers and so can keep them in step with the sheet.
  final VoidCallback onOpenRatings;

  @override
  State<_TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<_TrainingPage> {
  SessionViewModel get vm => widget.vm;

  /// The record the date bar has stepped onto, read by the viewer's own view
  /// model (2026-10-22). Null = today, where the live sets are the card.
  ///
  /// A step never leaves this page: the record swaps under the same route,
  /// header and wizard — the PR Lab's pager, not a navigation. The live
  /// session keeps running underneath the whole time, and stepping forward
  /// off the newest record only drops this reader.
  SessionDetailViewModel? _peek;

  @override
  void initState() {
    super.initState();
    vm.slidePagesController.addListener(_onWizardStep);
    vm.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    vm.slidePagesController.removeListener(_onWizardStep);
    vm.removeListener(_onSessionChanged);
    // No title write here: the screen's notifier is per-State and dies with
    // this page; only the listener needs releasing.
    _peek?.state.removeListener(_publishPeekTitle);
    _peek?.dispose();
    super.dispose();
  }

  /// The peek belongs to the Training page: leaving it (Summary, the post
  /// questionnaire, Home) drops the record, so coming back opens on today.
  void _onWizardStep() {
    if (vm.slidePagesController.currentPage != SessionViewModel.kTrainingPage) {
      _exitPeek();
    }
  }

  /// A cancelled (or otherwise ended) session leaves this page in its idle
  /// state without a wizard step — the peek has nothing left to stand on, so
  /// it goes with the live sets.
  void _onSessionChanged() {
    if (!vm.hasActiveWorkout) _exitPeek();
  }

  /// The left arrow on today's bar: open the newest completed record **in
  /// place**. The live body stays on screen until the first read lands, so
  /// the step never flashes an empty page; a failed read leaves the live
  /// sets where they were.
  Future<void> _enterPeek() async {
    final id = vm.previousSessionId;
    if (id == null || _peek != null) return;
    // A keystroke commit may still be settling; the peek replaces the card
    // that owns the focused cell, so land the write first — the same rule
    // the wizard's page changes follow.
    await vm.flushPendingCommits();
    if (!mounted || _peek != null || !vm.hasActiveWorkout) return;
    // The peek is the viewer, and it opens on the stack the live bar was
    // walking when the step was taken (2026-10-23) — a peek is only ever
    // entered from SESSION mode, so its own bar reads SESSION and its
    // arrows keep walking records.
    final peek = vm.createRecordPeek()..setDateBarMode(vm.dateBarMode);
    // The header follows the record (2026-10-23): every in-place step and
    // every read the VM lands republishes its name. Until the first read
    // lands `sessionTitle` is null, so the live name simply stays — the same
    // "live stays until the record is there" rule the body follows.
    peek.state.addListener(_publishPeekTitle);
    setState(() => _peek = peek);
    await peek.load(id);
    if (!mounted) return;
    // A missing record reads as a null session, not an error (2026-10-23):
    // the stamp list this arrow was built from can outlive a row that a
    // sync round removed. Both failures drop the peek and say so — a peek
    // held on a record that will never land sits invisibly over the live
    // sets, and the bar's arrow would press into a no-op for the rest of
    // the session. The stamps are re-read so the arrow heals onto the next
    // record (or spends).
    if (peek.state.value.error != null || peek.state.value.session == null) {
      peek.state.removeListener(_publishPeekTitle);
      setState(() => _peek = null);
      widget.peekTitle.value = null;
      peek.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that session')),
      );
      vm.refreshPreviousSession();
    }
  }

  /// Keeps the header's title in step with the hosted record (2026-10-23):
  /// the record's plan-name snapshot, or Freestyle — and back to null (the
  /// live session's own name) the moment the peek is left.
  void _publishPeekTitle() {
    final peek = _peek;
    if (!mounted || peek == null) return;
    final title = peek.state.value.sessionTitle;
    if (widget.peekTitle.value != title) widget.peekTitle.value = title;
  }

  /// The newest record's right arrow (or leaving the page): back onto the
  /// live sets. Nothing about the live session changed while peeking.
  void _exitPeek() {
    final peek = _peek;
    if (peek == null) return;
    peek.state.removeListener(_publishPeekTitle);
    setState(() => _peek = null);
    widget.peekTitle.value = null;
    peek.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peek = _peek;
    if (peek == null || !vm.hasActiveWorkout) return _buildLive(context);
    // The viewer's body, swapped for the live one — and swapped back as soon
    // as the record is left. Until the record's first read lands there is
    // nothing to draw, so the live sets simply stay (no spinner, no empty
    // page: the same in-place rule the viewer's own steps follow).
    return ValueListenableBuilder<SessionDetailState>(
      valueListenable: peek.state,
      builder: (context, state, _) {
        if (state.session == null) return _buildLive(context);
        return SessionHistoryPeek(
          viewModel: peek,
          state: state,
          onExit: _exitPeek,
        );
      },
    );
  }

  Widget _buildLive(BuildContext context) {
    // The Start Session button lives in the header (top right) while idle;
    // there is no bottom bar on this page.
    return vm.hasActiveWorkout ? _buildActive(context) : _buildIdle(context);
  }

  /// Idle: read-only planned-set preview of the selection; the template
  /// picker is the header's title (2026-10-23).
  Widget _buildIdle(BuildContext context) {
    return ListView(
      // The shell's bar floats over the page, so the last card has to be
      // able to scroll clear of it.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        ScrollShrinkNavBar.contentInset(context),
      ),
      children: [
        // The template selector is the header's title while idle (2026-10-23)
        // — the page opens straight onto the preview.
        _SessionPreview(vm: vm),
      ],
    );
  }

  /// Active: the exercise card fills the screen; the session stats bar
  /// (PRS/NOTES) sticks to the very bottom. The pinned note lives in
  /// the exercise card, right under the exercise.
  Widget _buildActive(BuildContext context) {
    final exerciseMode = vm.dateBarMode == SessionDateMode.exercise;
    final viewed = vm.viewedExerciseHistory;
    return KeyboardFloorLayout(
      // The page above the floor: the keyboard shrinks this viewport to its
      // top, so the focused set cell is revealed above it while the floor
      // below keeps its place under it (2026-10-25).
      page: SingleChildScrollView(
        // 16 top, not 12: the selector needs one more step of air under
        // the header's hairline — the lab's own correction, carried over
        // (2026-10-22).
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: vm.deletedViewSeId != null
            // The deleted view (2026-10-14): the trash menu's row opened
            // the exercise — red rows, the selector listing every deleted
            // exercise by name (another is one tap away), and the Restore
            // button below, which restores the one on screen. Looking is
            // not writing.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeletedExerciseCard(vm: vm),
                  const SizedBox(height: AppSpacing.md),
                  GlassButton(
                    label: 'Restore',
                    onPressed: vm.restoreViewedDeletedExercise,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  vm.activeSlot == null
                      ? _PlaceholderExerciseCard(vm: vm)
                      // Key per exercise slot: switching tabs recreates
                      // the card state so an open history view doesn't
                      // carry over.
                      : LiveExerciseCard(
                          key: ValueKey(vm.activeSlot!.id),
                          vm: vm,
                          slot: vm.activeSlot!,
                          onRemoveExercise: widget.onRemoveExercise,
                        ),
                  // The way back for deleted sets: the card shows them
                  // red in place, and this brings everything under the
                  // exercise back (2026-10-14).
                  if (vm.activeSlotHasDeletedSets) ...[
                    const SizedBox(height: AppSpacing.md),
                    GlassButton(
                      label: 'Restore',
                      onPressed: vm.restoreDeletedSetsForActiveExercise,
                    ),
                  ],
                ],
              ),
      ),
      // Sticky bottom: the session stats bar. It sits above the shell's
      // floating bar rather than behind it.
      floor: Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          ScrollShrinkNavBar.contentInset(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The floor leads with the session's place in time — the same
            // bar the past-session viewer draws, so the two surfaces are
            // one page in two modes (2026-10-22). A session resumed the
            // next day still says TODAY: it is the session being logged,
            // which is the fact the phrase reports.
            //
            // The bar walks the session stack on both surfaces, and a
            // step is **in place** on both (2026-10-22): today is the
            // newest, so the right arrow is spent here; the left steps
            // onto the newest completed record without leaving the page —
            // the sets under this card swap to the record's, the viewer's
            // own reading draws them, and the record's right arrow comes
            // back to these sets. No route changes anywhere.
            //
            // EXERCISE is the live default (2026-10-23): the arrows walk
            // the active exercise's own past performances and only the
            // card's sets swap — the page, header and live session stay.
            // SESSION is the record walk above, through the peek. The
            // radios under the date are the switch between the two stacks.
            SessionDateBar(
              isToday: viewed == null,
              date: viewed?.date ?? vm.workoutStartedAt ?? DateTime.now(),
              mode: vm.dateBarMode,
              onToggleMode: vm.toggleDateBarMode,
              onOlder: exerciseMode
                  ? (vm.canStepExerciseOlder
                        ? () => unawaited(vm.stepExerciseHistory(1))
                        : null)
                  : (vm.previousSessionId == null ? null : _enterPeek),
              onNewer: exerciseMode && vm.canStepExerciseNewer
                  ? () => unawaited(vm.stepExerciseHistory(-1))
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                UndoRedoButtons(
                  // Greyed while the deleted view is up: the mode is a
                  // reading, and an undo here would rewrite the very thing
                  // being read (2026-10-14).
                  canUndo: vm.canUndo && vm.deletedViewSeId == null,
                  canRedo: vm.canRedo && vm.deletedViewSeId == null,
                  onUndo: vm.undo,
                  onRedo: vm.redo,
                  // The trash menu: every deleted planned exercise, most
                  // recently deleted first — a row opens it for reading, and
                  // the Restore button under the card brings it back (the
                  // view-then-restore flow, 2026-10-14).
                  deletedExercises: [
                    for (final e in vm.deletedPlannedExerciseEntries) e.name,
                  ],
                  onPickDeletedExercise: vm.viewDeletedPlannedExerciseAt,
                ),
                const SizedBox(width: AppSpacing.sm),
                // The ratings star (2026-10-23, was the pencil): the sheet
                // it opens is five feeling stars — the door wears the same
                // glyph it leads to, and a star shares no silhouette with
                // the trophy or the pin beside it. Neutral glass: the star
                // stays white while the three score doors take the accent
                // (2026-10-27).
                BarIconButton(
                  key: const ValueKey('ratings-button'),
                  icon: Icons.star_rounded,
                  semanticsLabel: 'Session ratings',
                  onPressed: widget.onOpenRatings,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: SessionStatsBar(vm: vm)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The picker's "From past session" choice — a door out of the sheet, not a
/// template: it closes the picker and opens the record list instead.
const _kSeedFromPastSession = 'from-past-session';

/// Lets the user pick which session template to log — a standalone
/// template or none (free-form); the last row opens the past-session list
/// that seeds today's session from a record (2026-10-26). Programs are out of
/// the UI (2026-10-26), so there is no program section.
Future<void> _showWorkoutPickerSheet(
  BuildContext context,
  SessionViewModel vm,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    // Header and the record door stay put; the lists between them scroll,
    // so a long library can never outgrow the sheet (2026-10-26 — a
    // fixed-height column overflowed by 169pt once the door made it a row
    // taller).
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Select session',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () {
                        vm.clearTemplateSelection();
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.xs,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        // Pressable picker rows — the glass recipe, accent when
                        // selected.
                        decoration: glassBox(
                          vm.selectedPlannedSession == null &&
                                  vm.selectedStandaloneWorkout == null
                              ? AppColors.accent
                              : AppColors.primary,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_off_outlined,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'No planned session',
                                style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            if (vm.selectedPlannedSession == null &&
                                vm.selectedStandaloneWorkout == null)
                              Icon(
                                Icons.check,
                                size: 18,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (vm.standaloneWorkouts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.xs,
                        ),
                        child: Text(
                          'Workouts',
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.caption,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      for (final w in vm.standaloneWorkouts)
                        InkWell(
                          onTap: () {
                            vm.selectStandaloneWorkout(w);
                            Navigator.of(ctx).pop();
                          },
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              0,
                              AppSpacing.lg,
                              AppSpacing.xs,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            // Pressable picker rows — the glass recipe, accent when
                            // selected.
                            decoration: glassBox(
                              w.sessionId ==
                                      vm.selectedStandaloneWorkout?.sessionId
                                  ? AppColors.accent
                                  : AppColors.primary,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: UserNameText(
                                    toProperCase(w.name),
                                    tooltip: true,
                                    style: AppFonts.ui(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                if (w.sessionId ==
                                    vm.selectedStandaloneWorkout?.sessionId)
                                  Icon(
                                    Icons.check,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
            // A door, not a value: this row closes the picker and opens the
            // record list that seeds today's session from a past one
            // (2026-10-26). It sits last because it is the odd one out.
            InkWell(
              key: const ValueKey('picker-from-past-session'),
              onTap: () => Navigator.of(ctx).pop(_kSeedFromPastSession),
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                // Pressable picker rows — the glass recipe.
                decoration: glassBox(AppColors.primary),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'From past session',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    ),
  );
  // The picker closed on the record door: the list of completed sessions is
  // the next step, and picking one there is what seeds the page.
  if (choice == _kSeedFromPastSession && context.mounted) {
    await _openPastSessionPicker(context, vm);
  }
}

/// The Training page's pre-start preview, rendered like the live session:
/// exercise pill bar + the exercise card's grid.
///
/// Planned template: read-only planned rows (plannedBg fill + planned
/// outline) with static values — no editing, no reorder/remove/add.
/// Freestyle (no template): a ghosted, non-interactive version of the same
/// shared card — recently-used exercise names and an empty 3-row grid — so
/// the page still reads like a session without pretending anything is
/// planned.
/// An adapter over the shared [SessionExerciseCard] + [SessionSetRow] — the
/// exact chrome the live session uses, read-only by construction (nulls grey
/// the shared card's controls).
class _SessionPreview extends StatefulWidget {
  const _SessionPreview({required this.vm});

  final SessionViewModel vm;

  @override
  State<_SessionPreview> createState() => _SessionPreviewState();
}

class _SessionPreviewState extends State<_SessionPreview> {
  int _selectedIndex = 0;

  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    // A record picked to repeat draws what Start will write (2026-10-26):
    // the record's arrangement and weights, not the plan's targets.
    final seed = vm.pastSessionSeed;
    if (seed != null) return _seededPreview(vm, seed);
    final order = vm.plannedExerciseOrder;
    if (order.isEmpty) return _freestylePreview(vm);
    final activeIndex = _selectedIndex.clamp(0, order.length - 1);
    final exerciseId = order[activeIndex];
    return SessionExerciseCard(
      exerciseNames: [
        for (final id in order) toProperCase(vm.exerciseDisplayName(id)),
      ],
      activeIndex: activeIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      // No onMove/onAdd — the preview is read-only (the shared card greys
      // the reorder arrows and the Add row).
      planned: true,
      // The same flat card the live session wears once Start is pressed —
      // the preview is that view, not a third style (2026-10-22).
      flat: true,
      rows: _previewRows(vm, exerciseId),
      // No pills / history / ADD SET — all greyed or hidden via nulls.
    );
  }

  /// A repeated record, previewed as the live card will draw it the moment
  /// Start is pressed: each set's kg as a real value (the planned chip when
  /// it meets the plan), reps empty with the plan's target ghosted in, and
  /// the recorded variation. It asks [PastSessionSeed.exercisesToCopy] — the
  /// same question Start's write asks — so the preview can never promise a
  /// row Start does not write (2026-10-26).
  Widget _seededPreview(SessionViewModel vm, PastSessionSeed seed) {
    final groups = seed.exercisesToCopy(vm.plannedSetById);
    if (groups.isEmpty) return _freestylePreview(vm);
    final activeIndex = _selectedIndex.clamp(0, groups.length - 1);
    final group = groups[activeIndex];
    return SessionExerciseCard(
      exerciseNames: [
        for (final g in groups)
          toProperCase(vm.exerciseDisplayName(g.exerciseId)),
      ],
      activeIndex: activeIndex,
      onSelect: (i) => setState(() => _selectedIndex = i),
      // The plan's blue reads off the record's plan link: a freestyle record
      // repeats flat, exactly as it will after Start.
      planned: seed.plan != null,
      flat: true,
      rows: [
        for (var i = 0; i < group.sets.length; i++)
          _seededRow(vm, group.sets[i], i + 1),
      ],
    );
  }

  /// One row of a repeated record — the live row read-only, so the value
  /// grammar (chips, tints, ghosts) is the one the session will wear.
  Widget _seededRow(SessionViewModel vm, SeedSet row, int index) {
    final set = row.source;
    return SessionSetRow(
      key: ValueKey('seed-${set.sessionExerciseSetId}'),
      mode: SetRowMode.live,
      exerciseId: set.exerciseId ?? '',
      displayIndex: index,
      isDraft: false,
      initialWeightText: set.weight != null ? _fmtNum(set.weight!) : '',
      // Never the record's: reps are today's performance.
      initialRepsText: '',
      initialVariationId: row.variationId,
      initialVariationName: row.variationId == null ? null : set.variationName,
      initialNotes: null,
      hasNotes: false,
      plannedTarget: vm.plannedSetById[set.plannedSetId],
      readOnly: true,
      onCommit: (_, _, {bool immediate = false}) async {},
      onVariationChanged: (_) {},
      onNotesSave: (_) {},
      onDelete: () async {},
      onDuplicate: (_) {},
      variationOptions: _noVariationOptions,
      allVariations: const [],
      findSimilarVariations: (_) => const [],
      submitNewVariation: _inertSubmitVariation,
    );
  }

  /// The selected exercise's planned sets as the shared read-only rows —
  /// planned mode gives the exact planned-row chrome (plannedBg fill +
  /// planned outline) with every callback inert.
  List<Widget> _previewRows(SessionViewModel vm, String exerciseId) {
    final sets = (vm.plannedSetsByExercise[exerciseId] ?? const [])
        .where((s) => !s.isArchived)
        .where(_hasTargetData)
        .toList();
    return [
      for (var i = 0; i < sets.length; i++)
        _readOnlyPlannedRow(i + 1, sets[i], 'preview-${sets[i].plannedSetId}'),
    ];
  }

  /// A planned row with no target data at all (weight, reps, notes,
  /// variation) is a keep-alive stub from group creation, not a plan —
  /// never preview it.
  static bool _hasTargetData(PlannedSessionExerciseSet s) =>
      s.targetWeight != null ||
      s.targetReps != null ||
      (s.targetNotes?.isNotEmpty ?? false) ||
      s.variationId != null;

  Widget _readOnlyPlannedRow(
    int index,
    PlannedSessionExerciseSet set,
    String keySuffix,
  ) {
    return SessionSetRow(
      key: ValueKey(keySuffix),
      mode: SetRowMode.planned,
      exerciseId: set.exerciseId ?? '',
      displayIndex: index,
      isDraft: false,
      initialWeightText: set.targetWeight ?? '',
      initialRepsText: set.targetReps ?? '',
      initialVariationId: set.variationId,
      initialVariationName: set.variationName,
      initialNotes: set.targetNotes,
      hasNotes: set.targetNotes?.isNotEmpty ?? false,
      readOnly: true,
      onCommit: (_, _, {bool immediate = false}) async {},
      onVariationChanged: (_) {},
      onNotesSave: (_) {},
      onDelete: () async {},
      onDuplicate: (_) {},
      variationOptions: _noVariationOptions,
      allVariations: const [],
      findSimilarVariations: (_) => const [],
      submitNewVariation: _inertSubmitVariation,
    );
  }

  /// Most-recently-used exercises, newest first — the freestyle "sample" set.
  List<String> _recentExerciseIds(SessionViewModel vm) {
    final entries = vm.lastUsedByExercise.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key].take(6).toList();
  }

  /// Freestyle ghosts: the shared card, inert and dimmed — showing what a
  /// session will look like without pretending anything is planned.
  Widget _freestylePreview(SessionViewModel vm) {
    final recentIds = _recentExerciseIds(vm);
    return IgnorePointer(
      child: Opacity(
        opacity: 0.45,
        child: SessionExerciseCard(
          exerciseNames: [
            if (recentIds.isEmpty)
              'Exercise'
            else
              for (final id in recentIds)
                toProperCase(vm.exerciseDisplayName(id)),
          ],
          activeIndex: 0,
          onSelect: (_) {},
          flat: true,
          // Three empty neutral rows so the grid keeps its shape.
          rows: [
            for (var i = 0; i < 3; i++)
              SessionSetRow(
                key: ValueKey('ghost-$i'),
                mode: SetRowMode.history,
                exerciseId: '',
                displayIndex: i + 1,
                isDraft: false,
                initialWeightText: '',
                initialRepsText: '',
                initialVariationId: null,
                hasNotes: false,
                readOnly: true,
                onCommit: (_, _, {bool immediate = false}) async {},
                onVariationChanged: (_) {},
                onNotesSave: (_) {},
                onDelete: () async {},
                onDuplicate: (_) {},
                variationOptions: _noVariationOptions,
                allVariations: const [],
                findSimilarVariations: (_) => const [],
                submitNewVariation: _inertSubmitVariation,
              ),
          ],
        ),
      ),
    );
  }
}

/// The training page's exercise-card placeholder shown before the first
/// exercise is added — the shared card chrome (selector, greyed pills,
/// set-grid column labels) so the page never reads as completely empty.
/// The selector's popover carries the pinned Add Exercise row.
class _PlaceholderExerciseCard extends StatelessWidget {
  const _PlaceholderExerciseCard({required this.vm});

  final SessionViewModel vm;

  @override
  Widget build(BuildContext context) {
    return SessionExerciseCard(
      // The selector's pill doubles as the call to action — tapping it opens
      // the popover whose Add Exercise row creates the first exercise.
      exerciseNames: const ['Add your first exercise'],
      activeIndex: 0,
      onSelect: (_) {},
      onAdd: () => showSessionExercisePicker(context, vm),
      flat: true,
      rows: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'No exercises yet — add one to start logging',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              height: 1.4,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inert set-row plumbing for the read-only preview rows — the shared row
/// requires these callbacks even when nothing can ever fire them.
const _noVariationOptions = [
  DropdownOption<String?>(label: 'No Variation', value: null),
];

Future<String?> _inertSubmitVariation(
  String _, {
  required String exerciseId,
  String? useExistingId,
}) async => null;

// ── Page 3: Summary ──────────────────────────────────────────────────────────

/// The THIS SESSION recap shown before finishing — the shared viewer card
/// (PRS/NOTES + PRE-WORKOUT bookend; no POST bookend for the still-active
/// session). The Finish Session action is the header's right button.
class _SummaryPage extends StatelessWidget {
  const _SummaryPage({required this.vm, this.openRecord});

  final SessionViewModel vm;

  /// How the shown record opens; null keeps the `/logs/:id` route (2026-10-28).
  final void Function(String sessionId)? openRecord;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (!vm.hasActiveWorkout) {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              ScrollShrinkNavBar.contentInset(context),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(
                  child: Text(
                    'Nothing to reflect on yet — finish a session here.',
                    style: TextStyle(
                      color: AppColors.inkSecondary,
                      fontSize: AppTextStyles.sm,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        // The divider names what the viewer shows — THIS SESSION while the
        // still-active workout is selected, PREVIOUS SESSION once the
        // chevrons page into completed history.
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            ScrollShrinkNavBar.contentInset(context),
          ),
          children: [
            SectionDivider(
              vm.reflectionIsCurrent ? 'THIS SESSION' : 'PREVIOUS SESSION',
            ),
            const SizedBox(height: AppSpacing.sm),
            _LastSessionCard(
              vm: vm,
              showPostBookend: !vm.reflectionIsCurrent,
              openRecord: openRecord,
            ),
          ],
        );
      },
    );
  }
}

// ── Page 4: Post-questionnaire ───────────────────────────────────────────────

/// The fillable post-workout questionnaire after the session ends — the
/// same swap-in-place treatment as Pre-Evaluation: rating + notes centered
/// vertically, and a toggle under the notes question that swaps the content
/// for the previous session's answers (marked as coming from that session).
/// Done (header right) writes the answers and lands Home.
class _PostQuestionnairePage extends StatefulWidget {
  const _PostQuestionnairePage({required this.vm, required this.notesCtrl});

  final SessionViewModel vm;
  final TextEditingController notesCtrl;

  @override
  State<_PostQuestionnairePage> createState() => _PostQuestionnairePageState();
}

class _PostQuestionnairePageState extends State<_PostQuestionnairePage> {
  bool _showPreviousSession = false;

  SessionViewModel get vm => widget.vm;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final previous = vm.previousCompletedSession;
        return Column(
          children: [
            Expanded(
              child: Padding(
                // The keyboard shrinks this viewport to its top, so the
                // notes field rises clear of it while the shell's bar keeps
                // its place underneath (2026-10-25).
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      ScrollShrinkNavBar.contentInset(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // One of the two fills the SAME slot — previewing the
                        // previous session hides the fillable form entirely.
                        if (!_showPreviousSession)
                          _FeelingForm(
                            rating: vm.endFeeling,
                            onRatingChanged: vm.setEndFeeling,
                            notesCtrl: widget.notesCtrl,
                            onNotesChanged: (v) => vm.endNotes = v,
                            placeholder:
                                'How did it go?\nStrong sets?\nAnything to fix?',
                            question: 'How well did you do this session',
                            notesLabel:
                                'What could have made this session better',
                          )
                        else if (previous != null)
                          _previousSessionPreview(previous),
                        if (previous != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _showPreviousSession =
                                    !_showPreviousSession,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: glassBox(AppColors.primary),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showPreviousSession
                                          ? Icons.arrow_back
                                          : Icons.history,
                                      size: 13,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _showPreviousSession
                                          ? 'Back'
                                          : 'Last Session',
                                      style: AppFonts.ui(
                                        fontSize: AppTextStyles.xs,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The previous session's answers, read back with the same
  /// wording/styling as the live form — clearly marked as not this
  /// session's.
  Widget _previousSessionPreview(Session session) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 11, color: AppColors.muted),
              const SizedBox(width: 4),
              Text(
                'FROM LAST SESSION',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SessionBookend(
            label: 'PRE-WORKOUT',
            feeling: session.preFeeling,
            notes: session.preNotes,
            emptyNotes: 'No pre-workout notes',
            question: 'How well do you think you\'re going to do',
            notesLabel: 'Why do you feel that way',
          ),
          const SizedBox(height: AppSpacing.lg),
          SessionBookend(
            label: 'POST-WORKOUT',
            feeling: session.feeling,
            notes: session.postNotes,
            emptyNotes: 'No post-workout notes',
            question: 'How well did you do this session',
            notesLabel: 'What could have made this session better',
          ),
        ],
      ),
    );
  }
}
