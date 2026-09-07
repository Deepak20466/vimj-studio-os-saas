import 'package:flutter/material.dart';
import 'coach_dashboard_tab.dart';
import 'classes_tab.dart';
import 'leave_tab.dart';
import 'swap_tab.dart';
import 'coach_profile_tab.dart';
import 'coach_students_tab.dart';
import 'coach_receipts_tab.dart';
import 'coach_fee_reminders_tab.dart';
import 'coach_chat_tab.dart';

class CoachHome extends StatefulWidget {
  const CoachHome({super.key});

  @override
  State<CoachHome> createState() => _CoachHomeState();
}

class _MoreItem {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  const _MoreItem(this.label, this.icon, this.builder);
}

class _CoachHomeState extends State<CoachHome> {
  int _index = 0;

  final _tabs = const [
    CoachDashboardTab(),
    ClassesTab(),
    LeaveTab(),
    SwapTab(),
  ];

  final _moreItems = const [
    _MoreItem('My Students', Icons.groups_outlined, _buildStudents),
    _MoreItem('Fee Receipts', Icons.receipt_long_outlined, _buildReceipts),
    _MoreItem('Fee Reminders', Icons.notifications_active_outlined, _buildReminders),
    _MoreItem('Chat', Icons.chat_bubble_outline, _buildChat),
    _MoreItem('Profile', Icons.person_outline, _buildProfile),
  ];

  static Widget _buildStudents(BuildContext context) => const CoachStudentsTab();
  static Widget _buildReceipts(BuildContext context) => const CoachReceiptsTab();
  static Widget _buildReminders(BuildContext context) => const CoachFeeRemindersTab();
  static Widget _buildChat(BuildContext context) => const CoachChatTab();
  static Widget _buildProfile(BuildContext context) => const CoachProfileTab();

  void _openMore() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text('More', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            for (final item in _moreItems)
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute(builder: item.builder));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 4) {
            _openMore();
            return;
          }
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Classes'),
          NavigationDestination(icon: Icon(Icons.beach_access_outlined), selectedIcon: Icon(Icons.beach_access), label: 'Leave'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Swaps'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
