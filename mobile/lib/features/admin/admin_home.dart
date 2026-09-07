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
import 'admin_compliance_tab.dart';
import 'admin_leave_tab.dart';
import 'admin_fees_tab.dart';
import 'admin_salary_tab.dart';
import 'admin_reports_tab.dart';
import 'admin_chat_tab.dart';
import 'admin_settings_tab.dart';
import 'admin_about_tab.dart';

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

  final _items = const [
    _NavItem('Dashboard', Icons.dashboard_outlined, AdminDashboardTab()),
    _NavItem('Students', Icons.groups_outlined, AdminStudentsTab()),
    _NavItem('Coaches', Icons.sports_outlined, AdminCoachesTab()),
    _NavItem('Activities', Icons.event_outlined, AdminActivitiesTab()),
    _NavItem('Batches', Icons.calendar_month_outlined, AdminBatchesTab()),
    _NavItem('Attendance', Icons.fact_check_outlined, AdminAttendanceTab()),
    _NavItem('Compliance', Icons.rule_folder_outlined, AdminComplianceTab()),
    _NavItem('Leave', Icons.beach_access_outlined, AdminLeaveTab()),
    _NavItem('Fees', Icons.payments_outlined, AdminFeesTab()),
    _NavItem('Salary', Icons.account_balance_wallet_outlined, AdminSalaryTab()),
    _NavItem('Reports', Icons.bar_chart_outlined, AdminReportsTab()),
    _NavItem('Chat', Icons.chat_bubble_outline, AdminChatTab()),
    _NavItem('Settings', Icons.settings_outlined, AdminSettingsTab()),
    _NavItem('About', Icons.info_outline, AdminAboutTab()),
  ];

  Future<void> _logout() async {
    Navigator.of(context).pop();
    await AuthApi.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_items[_index].label)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: AppColors.brandOrange,
                child: const Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text('VIMJ Admin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      ListTile(
                        leading: Icon(_items[i].icon, color: i == _index ? AppColors.brandOrange : null),
                        title: Text(
                          _items[i].label,
                          style: TextStyle(
                            color: i == _index ? AppColors.brandOrange : AppColors.text,
                            fontWeight: i == _index ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: i == _index,
                        onTap: () {
                          setState(() => _index = i);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.danger),
                title: const Text('Logout', style: TextStyle(color: AppColors.danger)),
                onTap: _logout,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: _items.map((e) => e.page).toList(),
      ),
    );
  }
}
