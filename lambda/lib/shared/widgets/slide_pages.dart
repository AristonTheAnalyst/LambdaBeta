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

  /// Animates to [page] and notifies listeners.
  void slideToPage(int page) {
    _currentPage = page;
    notifyListeners();
    pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
  });

  final SlidePagesController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller.pageController,
      physics: const PageScrollPhysics(),
      children: children,
    );
  }
}
