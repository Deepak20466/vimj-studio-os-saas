import 'package:flutter/material.dart';
import 'coach_dashboard_tab.dart';
import 'classes_tab.dart';
import 'leave_tab.dart';
import 'swap_tab.dart';
import 'coach_profile_tab.dart';

class CoachHome extends StatefulWidget {
  const CoachHome({super.key});

  @override
  State<CoachHome> createState() => _CoachHomeState();
}

class _CoachHomeState extends State<CoachHome> {
  int _index = 0;

  final _tabs = const [
    CoachDashboardTab(),
    ClassesTab(),
    LeaveTab(),
    SwapTab(),
    CoachProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Classes'),
          NavigationDestination(icon: Icon(Icons.beach_access_outlined), selectedIcon: Icon(Icons.beach_access), label: 'Leave'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Swaps'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
