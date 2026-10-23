import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/session/view/session_screen.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// A re-tap of the Session nav tab while the wizard is already on screen
/// means "show me my past sessions", not "end this one" (2026-10-23). The
/// wizard steps to Home — the embedded Training Logs browse — with a live
/// session still running underneath, and Home's header offers Resume back to
/// Training. The guard is a pure rule so the states that must NOT move are
/// pinned without a database: a re-tap with no live session, with the browse
/// already showing, or on the one-way post-questionnaire all do nothing.
void main() {
  group('browseOnSessionTabRetap', () {
    test('a live session on Training steps to the browse', () {
      expect(
        browseOnSessionTabRetap(
          live: true,
          page: SessionViewModel.kTrainingPage,
        ),
        isTrue,
      );
    });

    test('a live session on Summary steps to the browse too', () {
      expect(
        browseOnSessionTabRetap(
          live: true,
          page: SessionViewModel.kSummaryPage,
        ),
        isTrue,
      );
    });

    test('Home is already the browse', () {
      expect(
        browseOnSessionTabRetap(
          live: true,
          page: SessionViewModel.kSessionHomePage,
        ),
        isFalse,
      );
    });

    test('the post-questionnaire is a one-way door', () {
      // The session has already ended; Done is the only way off that page.
      expect(
        browseOnSessionTabRetap(
          live: true,
          page: SessionViewModel.kPostQuestionnairePage,
        ),
        isFalse,
      );
    });

    test('the pre-questionnaire is not one of the live pages', () {
      // It only ever shows before Start, so this is a defensive guard.
      expect(
        browseOnSessionTabRetap(
          live: true,
          page: SessionViewModel.kPreQuestionnairePage,
        ),
        isFalse,
      );
    });

    test('no live session: nothing moves on any page', () {
      for (final page in [
        SessionViewModel.kSessionHomePage,
        SessionViewModel.kPreQuestionnairePage,
        SessionViewModel.kTrainingPage,
        SessionViewModel.kSummaryPage,
        SessionViewModel.kPostQuestionnairePage,
      ]) {
        expect(
          browseOnSessionTabRetap(live: false, page: page),
          isFalse,
          reason: 'page $page',
        );
      }
    });
  });
}
