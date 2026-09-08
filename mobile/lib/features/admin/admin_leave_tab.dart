import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class AdminLeaveTab extends StatefulWidget {
  const AdminLeaveTab({super.key});

  @override
  State<AdminLeaveTab> createState() => _AdminLeaveTabState();
}

class _AdminLeaveTabState extends State<AdminLeaveTab> {
  bool _loading = true;
  bool _pendingOnly = true;
  List<AdminLeaveRequest> _leaves = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get(_pendingOnly ? '/leave/pending' : '/leave') as List;
      _leaves = data.map((e) => AdminLeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(AdminLeaveRequest l, bool approve) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(approve ? 'Approve leave' : 'Reject leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l.coachName ?? "Coach #${l.coachId}"} · ${l.startDate} to ${l.endDate}'),
            const SizedBox(height: 4),
            Text(l.reason, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Reject', style: TextStyle(color: approve ? AppColors.success : AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteCtrl.dispose();
      return;
    }
    try {
      final path = approve ? '/leave/${l.id}/approve' : '/leave/${l.id}/reject';
      await ApiClient.instance.put(path, body: {'note': noteCtrl.text.trim()});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      noteCtrl.dispose();
    }
  }

  Future<void> _openEdit(AdminLeaveRequest l) async {
    final startCtrl = TextEditingController(text: l.startDate);
    final endCtrl = TextEditingController(text: l.endDate);
    final reasonCtrl = TextEditingController(text: l.reason);

    Future<void> pickDate(TextEditingController ctrl) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) ctrl.text = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Leave Request — ${l.coachName ?? "Coach #${l.coachId}"}', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: startCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Start date', suffixIcon: Icon(Icons.calendar_today)),
                  onTap: () async {
                    await pickDate(startCtrl);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'End date', suffixIcon: Icon(Icons.calendar_today)),
                  onTap: () async {
                    await pickDate(endCtrl);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason'), maxLines: 3),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await ApiClient.instance.put('/leave/${l.id}', body: {
                        'start_date': startCtrl.text.trim(),
                        'end_date': endCtrl.text.trim(),
                        'reason': reasonCtrl.text.trim(),
                      });
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } on ApiException catch (e) {
                      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    startCtrl.dispose();
    endCtrl.dispose();
    reasonCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _remove(AdminLeaveRequest l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete leave request?'),
        content: Text('Delete this leave request from ${l.coachName ?? "Coach #${l.coachId}"}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/leave/${l.id}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request deleted')));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Show pending only', style: TextStyle(fontSize: 12)),
              Switch(
                value: _pendingOnly,
                onChanged: (v) {
                  setState(() => _pendingOnly = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _leaves.isEmpty
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No leave requests${_pendingOnly ? " pending" : ""}.')))])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _leaves.length,
                          itemBuilder: (context, i) {
                            final l = _leaves[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(l.coachName ?? 'Coach #${l.coachId}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                        Chip(
                                          label: Text(l.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                          backgroundColor: _statusColor(l.status),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${l.startDate} to ${l.endDate}', style: const TextStyle(color: AppColors.textMuted)),
                                    const SizedBox(height: 4),
                                    Text(l.reason),
                                    const SizedBox(height: 12),
                                    if (l.status == 'PENDING')
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _decide(l, false),
                                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                              child: const Text('Reject'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _decide(l, true),
                                              child: const Text('Approve'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(child: TextButton(onPressed: () => _openEdit(l), child: const Text('Edit'))),
                                        Expanded(
                                          child: TextButton(
                                            onPressed: () => _remove(l),
                                            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                            child: const Text('Delete'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
