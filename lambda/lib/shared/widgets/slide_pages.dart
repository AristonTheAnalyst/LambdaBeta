import 'package:flutter/material.dart';

/// Controller for [SlidePages] — a swipeable horizontal pager whose current
/// page is observable ([ChangeNotifier]) so callers can render tab indicators
/// and navigate programmatically.
class SlidePagesController extends ChangeNotifier {
  SlidePagesController();

  int _initialPage = 0;
  int _currentPage = 0;
  PageController? _pageController;

  PageController get pageController {
    _pageController ??=
        PageController(initialPage: _initialPage)..addListener(_onPageChanged);
    return _pageController!;
  }

  void _onPageChanged() {
    final page = _pageController!.page;
    if (page == null) return;
    // Only accept near-integer positions — mid-animation values like 1.5
    // round ambiguously and would flicker the tab indicator (and the whole
    // screen via listeners) back and forth while the page animates.
    final p = page.round();
    if ((page - p).abs() > 0.05) return;
    if (p != _currentPage) {
      _currentPage = p;
      notifyListeners();
    }
  }

  /// Slides to page 1 (the second page).
  void slideIn() => slideToPage(1);

  /// Slides back to page 0.
  void slideOut() => slideToPage(0);

  /// Cuts instantly to [page] and notifies listeners — no slide animation,
  /// per the session-flow design.
  void slideToPage(int page) {
    _currentPage = page;
    notifyListeners();
    if (pageController.hasClients) {
      pageController.jumpToPage(page);
    } else {
      _initialPage = page;
    }
  }

  /// Jumps to [page]. If the PageView hasn't been laid out yet, stores the
  /// target so the next PageController construction picks it up.
  void resetToPage(int page) {
    _initialPage = page;
    _currentPage = page;
    notifyListeners();
    if (_pageController != null && _pageController!.hasClients) {
      _pageController!.jumpToPage(page);
    }
  }

  /// Re-anchors the pager for a fresh [PageView] after the previous one was
  /// disposed (tab re-entry recreates the screen, and a newly attached
  /// PageView always starts at [initialPage] — 0 — not the last page shown).
  /// Drops the stale [PageController] so the next attach starts at
  /// [_currentPage] instead of silently resetting the wizard to its first
  /// page. Call this BEFORE the new PageView attaches — once it has attached
  /// at page 0, the attach overwrites [_currentPage] and the last page is
  /// lost.
  void restorePageView() {
    final c = _pageController;
    if (c != null) {
      c.removeListener(_onPageChanged);
      c.dispose();
      _pageController = null;
    }
    _initialPage = _currentPage;
  }

  /// The page currently showing (0-based).
  int get currentPage => _currentPage;

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }
}

class SlidePages extends StatelessWidget {
  const SlidePages({
    super.key,
    required this.controller,
    required this.children,
    this.physics = const PageScrollPhysics(),
  });

  final SlidePagesController controller;
  final List<Widget> children;

  /// Pass [NeverScrollableScrollPhysics] to make page changes
  /// button-driven only (e.g. the session screen's strict wizard).
  final ScrollPhysics physics;

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller.pageController,
      physics: physics,
      children: children,
    );
  }
}
