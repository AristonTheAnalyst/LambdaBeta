import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/utils/session_format.dart';

/// The two ways a user enters a run: beginning one, or picking a paused one
/// back up.
///
/// It supplies the title's verb, the confirm button, and which sentence the
/// body opens with — nothing else, and all of it in one place, so the two
/// screens that ask cannot drift apart in wording.
enum RunEntry {
  begin('Begin'),
  resume('Resume');

  const RunEntry(this.verb);

  /// The act's own word: `Begin "Base"?` over a button that says Begin.
  final String verb;
}

/// Asks before a run begins or resumes, and says what that does to everything
/// else.
///
/// Asked every time, whatever else is open, and before the config sheet — it is
/// the decision, and "how long" is a detail of an act already chosen. It used
/// to be asked only when another program's run was *current*, so a user
/// entering a run while something else sat paused got no question at all and
/// no way to tell that nothing had happened to it. One deliberate tap is the
/// price of a gate that is always in the same place.
///
/// A rule the user only hears about afterwards reads as a notification, not a
/// choice: "Lambda paused X" arriving once the other program has already begun
/// describes something that has happened. So the consequence that matters most
/// — the run being stepped aside — is said first, and named when a name could
/// be read, because "another program" is not something a decision can be
/// weighed against.
///
/// [displacesCurrentRun] is whether this entry will pause some other program's
/// current run, and [displacedName] that program's name when it could be read
/// — null is a displacement that could not be named, which is not the same
/// fact as no displacement, and the two are separate parameters because of it.
/// [otherRunPaused] adds the one sentence that has no other place to be said:
/// that entering a run leaves anything already paused exactly where it is. It
/// is only consulted when nothing is displaced, where "paused, not ended" has
/// not already said it.
///
/// Returns true when the action should go ahead; false covers Cancel and
/// dismissal.
Future<bool> confirmStartRun(
  BuildContext context, {
  required RunEntry entry,
  required String programName,
  required bool displacesCurrentRun,
  required String? displacedName,
  required bool otherRunPaused,
}) async {
  // Named when a name could be read, generically when it could not — the
  // sentence has to make sense either way, and the quoting is the dialog's
  // business, not each caller's.
  final displaced =
      displacedName == null ? 'another program' : '"$displacedName"';

  final String body;
  if (displacesCurrentRun) {
    // "Pauses", not "ends": the run being left keeps everything — its id, its
    // config, its block, every session logged against it — and the question
    // says so, because copy that cried destruction over a pause is how a user
    // learns to fear switching.
    body = 'Your current run on $displaced will be paused, not ended. You can '
        'pick it back up any time — the sessions you logged stay intact.';
  } else {
    final act = switch (entry) {
      RunEntry.begin => 'This starts a new run, from your first workout.',
      RunEntry.resume => 'This picks your run back up where you left off.',
    };
    // "Other" is load-bearing on a resume: the program being resumed is itself
    // paused, and a bare "your paused programs stay paused" would read as
    // including the one about to start running again.
    final leftPaused = entry == RunEntry.resume
        ? 'Your other paused programs stay paused.'
        : 'Your paused programs stay paused.';
    body = otherRunPaused ? '$act $leftPaused' : act;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '${entry.verb} "${toProperCase(programName)}"?',
        style: AppFonts.ui(
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
      content: Text(body, style: AppFonts.ui(color: AppColors.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(entry.verb, style: AppFonts.ui(color: AppColors.accent)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
