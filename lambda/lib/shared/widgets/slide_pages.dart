import 'package:flutter/material.dart';

class SlidePagesController {
  SlidePagesController() {
    _pageController = PageController(initialPage: 0);
  }

  late final PageController _pageController;
  PageController get pageController => _pageController;

  void slideIn() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void slideOut() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void resetToPage(int page) {
    if (_pageController.hasClients) {
      _pageController.jumpToPage(page);
    }
  }

  void dispose() => _pageController.dispose();
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
