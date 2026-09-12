import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/auth_api.dart';
import '../auth/login_screen.dart';
import 'admin_dashboard_tab.dart';
import 'admin_students_tab.dart';
import 'admin_coaches_tab.dart';
import 'admin_activities_tab.dart';
import 'admin_batches_tab.dart';
import 'admin_attendance_tab.dart';
import 'admin_fees_tab.dart';
import 'admin_leave_tab.dart';
import 'admin_settings_tab.dart';
import '../shared/notification_bell_action.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget page;
  const _NavItem(this.label, this.icon, this.page);
}

class _AdminHomeState extends State<AdminHome> {
  int _index = 0;

  // Same bottom-nav-plus-"More"-sheet pattern as the web dashboard's Layout.jsx and the
  // coach app's CoachHome — the admin app used to be the only screen in VIMJ using a left
  // drawer, which felt inconsistent switching between admin and coach on the same phone.
  static const int _maxTabs = 4;

  final _items = const [
    _NavItem('Dashboard', Icons.dashboard_outlined, AdminDashboardTab()),
    _NavItem('Students', Icons.groups_outlined, AdminStudentsTab()),
    _NavItem('Coaches', Icons.sports_outlined, AdminCoachesTab()),
    _NavItem('Attendance', Icons.fact_check_outlined, AdminAttendanceTab()),
    _NavItem('Activities', Icons.event_outlined, AdminActivitiesTab()),
    _NavItem('Batches', Icons.calendar_month_outlined, AdminBatchesTab()),
    _NavItem('Fees', Icons.payments_outlined, AdminFeesTab()),
    _NavItem('Leave', Icons.beach_access_outlined, AdminLeaveTab()),
    _NavItem('Settings', Icons.settings_outlined, AdminSettingsTab()),
  ];

  List<_NavItem> get _tabs => _items.sublist(0, _maxTabs);
  List<_NavItem> get _moreItems => _items.sublist(_maxTabs);

  Future<void> _logout() async {
    await AuthApi.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openMore() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text('More', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            for (int i = 0; i < _moreItems.length; i++)
              ListTile(
                leading: Icon(_moreItems[i].icon),
                title: Text(_moreItems[i].label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _index = _maxTabs + i);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Logout', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(sheetContext);
                _logout();
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
    final inMore = _index >= _maxTabs;
    return Scaffold(
      appBar: AppBar(title: Text(_items[_index].label), actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      body: IndexedStack(
        index: _index,
        children: _items.map((e) => e.page).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: inMore ? _maxTabs : _index,
        onDestinationSelected: (i) {
          if (i == _maxTabs) {
            _openMore();
            return;
          }
          setState(() => _index = i);
        },
        destinations: [
          for (final item in _tabs) NavigationDestination(icon: Icon(item.icon), label: item.label),
          NavigationDestination(
            icon: Icon(inMore ? _items[_index].icon : Icons.more_horiz),
            label: inMore ? _items[_index].label : 'More',
          ),
        ],
      ),
    );
  }
}
