import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/session/view/session_screen.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// The another-device notice is a door to start from, not chrome over a live
/// session (2026-10-27): it floats above the nav bar on the wizard's screens
/// BEFORE the live one — Home and the pre-questionnaire — and steps aside
/// once the session is running, so Training, Summary and the post-
/// questionnaire never carry it.
void main() {
  group('showsForeignSessionNotice', () {
    test('Home and the pre-questionnaire carry the notice', () {
      for (final page in [
        SessionViewModel.kSessionHomePage,
        SessionViewModel.kPreQuestionnairePage,
      ]) {
        expect(
          showsForeignSessionNotice(hasForeign: true, page: page),
          isTrue,
          reason: 'page $page',
        );
      }
    });

    test('the live pages never do — Training, Summary and the post page', () {
      for (final page in [
        SessionViewModel.kTrainingPage,
        SessionViewModel.kSummaryPage,
        SessionViewModel.kPostQuestionnairePage,
      ]) {
        expect(
          showsForeignSessionNotice(hasForeign: true, page: page),
          isFalse,
          reason: 'page $page',
        );
      }
    });

    test('no foreign session: nothing shows on any page', () {
      for (final page in [
        SessionViewModel.kSessionHomePage,
        SessionViewModel.kPreQuestionnairePage,
        SessionViewModel.kTrainingPage,
        SessionViewModel.kSummaryPage,
        SessionViewModel.kPostQuestionnairePage,
      ]) {
        expect(
          showsForeignSessionNotice(hasForeign: false, page: page),
          isFalse,
          reason: 'page $page',
        );
      }
    });
  });
}
