import 'package:flutter/material.dart';
import '../../core/auth_api.dart';
import '../../core/auth_storage.dart';
import '../auth/login_screen.dart';
import '../shared/theme_toggle_tile.dart';

class StudentProfileTab extends StatefulWidget {
  const StudentProfileTab({super.key});

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
  String _name = '';
  String _role = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await AuthStorage.load();
    if (!mounted) return;
    setState(() {
      _name = session?.name ?? '';
      _role = session?.role ?? '';
    });
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(radius: 32, child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : '?')),
          const SizedBox(height: 8),
          Text(_name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          Text(_role, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          const Card(child: ThemeToggleTile()),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Log out')),
        ],
      ),
    );
  }
}
