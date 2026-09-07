import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';

class AdminAboutTab extends StatefulWidget {
  const AdminAboutTab({super.key});

  @override
  State<AdminAboutTab> createState() => _AdminAboutTabState();
}

class _AdminAboutTabState extends State<AdminAboutTab> {
  bool _loading = true;
  bool _saving = false;
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/academy') as Map<String, dynamic>;
      final academy = AcademySettings.fromJson(data);
      _nameCtrl.text = academy.name;
      _addressCtrl.text = academy.address ?? '';
      _phoneCtrl.text = academy.phone ?? '';
      _emailCtrl.text = academy.email ?? '';
      _descriptionCtrl.text = academy.description ?? '';
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/academy', body: {
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Academy details updated')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Academy Name')),
        const SizedBox(height: 12),
        TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
        const SizedBox(height: 12),
        TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        TextField(controller: _descriptionCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 4),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}
