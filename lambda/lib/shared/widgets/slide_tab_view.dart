import 'package:flutter/material.dart';

class SlideTabController {
  SlideTabController({int initialIndex = 0}) {
    _pageController = PageController(initialPage: initialIndex);
  }

  late final PageController _pageController;
  PageController get pageController => _pageController;

  void jumpTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void dispose() => _pageController.dispose();
}

class SlideTabView extends StatelessWidget {
  const SlideTabView({
    super.key,
    required this.tabs,
    required this.controller,
    required this.onPageChanged,
  });

  final List<Widget> tabs;
  final SlideTabController controller;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PageView(
        controller: controller.pageController,
        onPageChanged: onPageChanged,
        children: tabs,
      ),
    );
  }
}
