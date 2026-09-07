import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminActivitiesTab extends StatefulWidget {
  const AdminActivitiesTab({super.key});

  @override
  State<AdminActivitiesTab> createState() => _AdminActivitiesTabState();
}

class _AdminActivitiesTabState extends State<AdminActivitiesTab> {
  List<Activity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/activities') as List;
      _activities = data.map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Activity? activity}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ActivityForm(activity: activity),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(Activity a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove activity?'),
        content: Text('Remove ${a.name}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/activities/${a.id}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-activities-fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Activity'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _activities.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No activities yet.')))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _activities.length,
                      itemBuilder: (context, i) {
                        final a = _activities[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(backgroundColor: AppColors.brandLight, child: Icon(Icons.event, color: AppColors.brandOrange)),
                            title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Capacity: ${a.capacity} · Monthly fee: ₹${a.monthlyFee}'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _openForm(activity: a);
                                if (v == 'delete') _remove(a);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _ActivityForm extends StatefulWidget {
  final Activity? activity;
  const _ActivityForm({this.activity});

  @override
  State<_ActivityForm> createState() => _ActivityFormState();
}

class _ActivityFormState extends State<_ActivityForm> {
  late final _nameCtrl = TextEditingController(text: widget.activity?.name ?? '');
  late final _capacityCtrl = TextEditingController(text: widget.activity?.capacity.toString() ?? '20');
  late final _feeCtrl = TextEditingController(text: widget.activity?.monthlyFee ?? '0');
  bool _saving = false;

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'name': _nameCtrl.text.trim(),
        'capacity': int.tryParse(_capacityCtrl.text.trim()) ?? 20,
        'monthly_fee': _feeCtrl.text.trim(),
      };
      if (widget.activity != null) {
        await ApiClient.instance.put('/activities/${widget.activity!.id}', body: body);
      } else {
        await ApiClient.instance.post('/activities', body: body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.activity != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit Activity' : 'Add Activity', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: _capacityCtrl, decoration: const InputDecoration(labelText: 'Capacity'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: _feeCtrl, decoration: const InputDecoration(labelText: 'Monthly Fee (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(editing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
