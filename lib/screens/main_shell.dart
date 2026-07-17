import 'package:flutter/material.dart';

import 'profile_screen.dart';
import 'recognition_feed_screen.dart';
import 'recognition_submit_screen.dart';
import 'safewalk_screen.dart';
import 'search_screen.dart';
import '../widgets/custom_bottom_nav.dart';

/// Top-level authenticated shell: a custom 5-slot bottom nav (Feed, Search,
/// center give-recognition action, SafeWalk, Profile).
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.groupId});

  final String groupId;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      RecognitionFeedScreen(groupId: widget.groupId),
      const SearchScreen(),
      const SafeWalkScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: CustomBottomNav(
        selectedIndex: _index,
        onTabSelected: (index) => setState(() => _index = index),
        onCenterTap: () => showRecognitionSubmitSheet(context, groupId: widget.groupId),
      ),
    );
  }
}
