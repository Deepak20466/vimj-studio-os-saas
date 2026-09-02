import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth_api.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';
import '../auth/login_screen.dart';
import '../shared/theme_toggle_tile.dart';

class CoachProfileTab extends StatefulWidget {
  const CoachProfileTab({super.key});

  @override
  State<CoachProfileTab> createState() => _CoachProfileTabState();
}

class _CoachProfileTabState extends State<CoachProfileTab> {
  String _name = '';
  int? _coachId;
  double? _attendancePct;
  List<SalaryRecord> _salary = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      _name = session?.name ?? '';
      _coachId = session?.userId;
      if (_coachId != null) {
        final report = await ApiClient.instance.get('/reports/coach/$_coachId') as Map<String, dynamic>;
        _attendancePct = (report['student_attendance_pct'] as num).toDouble();
        final salaryData = await ApiClient.instance.get('/coaches/$_coachId/salary') as List;
        _salary = salaryData.map((e) => SalaryRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(SalaryRecord record) async {
    try {
      await ApiClient.instance.post('/salary/acknowledge', body: {'salary_id': record.id});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logout() async {
    await AuthApi.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CircleAvatar(radius: 32, child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?')),
                  const SizedBox(height: 8),
                  Text(_name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.insights_outlined),
                      title: const Text('Student Attendance %'),
                      trailing: Text('${_attendancePct?.toStringAsFixed(1) ?? '-'}%', style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Salary History', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_salary.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No salary records yet.'))
                  else
                    ..._salary.map(
                      (s) => Card(
                        child: ListTile(
                          title: Text('${s.month}/${s.year} — ₹${s.amount}'),
                          subtitle: Text(s.acknowledgedDate != null ? 'Acknowledged' : 'Pending acknowledgment'),
                          trailing: s.acknowledgedDate != null
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : TextButton(onPressed: () => _acknowledge(s), child: const Text('Acknowledge')),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Card(child: ThemeToggleTile()),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Log out')),
                ],
              ),
            ),
    );
  }
}
