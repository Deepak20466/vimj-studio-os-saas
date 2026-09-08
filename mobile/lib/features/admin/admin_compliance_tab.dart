import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

class AdminComplianceTab extends StatefulWidget {
  const AdminComplianceTab({super.key});

  @override
  State<AdminComplianceTab> createState() => _AdminComplianceTabState();
}

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

class _AdminComplianceTabState extends State<AdminComplianceTab> {
  ComplianceSummary? _summary;
  List<PendingLateSubmission> _pending = [];
  List<Activity> _activities = [];
  bool _loading = true;
  int? _busyId;
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _dateTo = DateTime.now();
  int? _activityFilter;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final data = await ApiClient.instance.get('/activities') as List;
      _activities = data.map((e) => Activity.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException {
      // filters just won't have options; not fatal
    }
    _loadPending();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    try {
      final query = <String, dynamic>{
        'start_date': _isoDate(_dateFrom),
        'end_date': _isoDate(_dateTo),
      };
      if (_activityFilter != null) query['activity_id'] = _activityFilter;
      final data = await ApiClient.instance.get('/compliance/summary', query: query);
      _summary = ComplianceSummary.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPending() async {
    try {
      final data = await ApiClient.instance.get('/compliance/pending') as List;
      if (mounted) setState(() => _pending = data.map((e) => PendingLateSubmission.fromJson(e as Map<String, dynamic>)).toList());
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _load() async {
    await _loadPending();
    await _loadSummary();
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _dateFrom : _dateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
    _loadSummary();
  }

  Future<void> _decide(PendingLateSubmission p, bool approve) async {
    String note = '';
    if (!approve) {
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject late attendance'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Confirm')),
          ],
        ),
      );
      if (result == null) return;
      note = result;
    }
    setState(() => _busyId = p.id);
    try {
      await ApiClient.instance.put('/compliance/late/${p.id}/${approve ? 'approve' : 'reject'}', body: {'decision_note': note});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _viewPhotos(int classId) async {
    List<ClassPhoto> photos;
    try {
      final data = await ApiClient.instance.get('/compliance/class/$classId/photos') as List;
      photos = data.map((e) => ClassPhoto.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No photos uploaded for this class.')));
      return;
    }
    final session = await AuthStorage.load();
    final headers = {'Authorization': 'Bearer ${session?.accessToken ?? ''}'};
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batch Photos'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: photos.length,
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '${ApiConfig.baseUrl}/compliance/class-photo/${photos[i].id}',
                headers: headers,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'SUBMITTED':
      case 'LATE_APPROVED':
        return AppColors.success;
      case 'PENDING':
        return AppColors.warning;
      case 'DELAYED':
        return AppColors.danger;
      case 'NOT_CONDUCTED':
      case 'LATE_REJECTED':
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_pending.isNotEmpty) ...[
                  Text('Pending Late-Attendance Approvals', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._pending.map(
                    (p) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${p.coachName} · ${p.activityName}'),
                        subtitle: Text('${p.classDate}${p.lateReason != null ? "\nReason: ${p.lateReason}" : ""}'),
                        isThreeLine: p.lateReason != null,
                        trailing: _busyId == p.id
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.check_circle, color: AppColors.success), onPressed: () => _decide(p, true)),
                                  IconButton(icon: const Icon(Icons.cancel, color: AppColors.danger), onPressed: () => _decide(p, false)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Compliance Overview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<int?>(
                      value: _activityFilter,
                      hint: const Text('All activities'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('All activities')),
                        ..._activities.map((a) => DropdownMenuItem<int?>(value: a.id, child: Text(a.name))),
                      ],
                      onChanged: (v) {
                        setState(() => _activityFilter = v);
                        _loadSummary();
                      },
                    ),
                    OutlinedButton(onPressed: () => _pickDate(true), child: Text('From ${_isoDate(_dateFrom)}')),
                    OutlinedButton(onPressed: () => _pickDate(false), child: Text('To ${_isoDate(_dateTo)}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (_summary != null)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      _statCard('Submitted', _summary!.submitted, AppColors.success),
                      _statCard('Pending', _summary!.pending, AppColors.warning),
                      _statCard('Delayed', _summary!.delayed, AppColors.danger),
                      _statCard('Not Conducted', _summary!.notConducted, AppColors.textMuted),
                    ],
                  ),
                const SizedBox(height: 12),
                if (_summary != null)
                  ..._summary!.rows.map(
                    (r) => Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text('${r.activityName} · ${r.coachName}'),
                        subtitle: Text('${r.classDate} · ends ${r.endTime}${r.skipReason != null ? "\n${r.skipReason}" : ""}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.photo_library_outlined), tooltip: 'Photos', onPressed: () => _viewPhotos(r.classId)),
                            Chip(
                              label: Text(r.state, style: const TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: _stateColor(r.state),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
  }

  Widget _statCard(String label, int value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
