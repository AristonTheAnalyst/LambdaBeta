import 'package:flutter/material.dart';

class SlidePagesController {
  SlidePagesController();

  int _initialPage = 0;
  PageController? _pageController;

  PageController get pageController {
    _pageController ??= PageController(initialPage: _initialPage);
    return _pageController!;
  }

  void slideIn() {
    pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void slideOut() {
    pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Jumps to [page]. If the PageView hasn't been laid out yet, stores the
  /// target so the next PageController construction picks it up.
  void resetToPage(int page) {
    _initialPage = page;
    if (_pageController != null && _pageController!.hasClients) {
      _pageController!.jumpToPage(page);
    }
  }

  /// The page the controller is currently on (or will be after the PageView
  /// is laid out) — 0 = start, 1 = active.
  int get currentPage => _initialPage;

  void dispose() => _pageController?.dispose();
}

class SlidePages extends StatelessWidget {
  const SlidePages({
    super.key,
    required this.controller,
    required this.children,
  }) : assert(children.length == 2, 'SlidePages requires exactly 2 children');

  final SlidePagesController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: controller.pageController,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}
