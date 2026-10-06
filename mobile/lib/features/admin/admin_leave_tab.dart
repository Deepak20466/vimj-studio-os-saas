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
  bool _pendingLoading = true;
  List<AdminLeaveRequest> _pending = [];
  int? _busyId;

  bool _historyLoading = true;
  List<AdminLeaveRequest> _history = [];
  String? _statusFilter;
  String _pendingSearch = '';
  String _historySearch = '';
  DateTime? _pendingFrom;
  DateTime? _pendingTo;
  DateTime? _historyFrom;
  DateTime? _historyTo;

  Future<void> _pickDate({required bool pending, required bool from}) async {
    final current = pending ? (from ? _pendingFrom : _pendingTo) : (from ? _historyFrom : _historyTo);
    final picked = await showDatePicker(context: context, initialDate: current ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() {
      if (pending) { if (from) { _pendingFrom = picked; } else { _pendingTo = picked; } }
      else { if (from) { _historyFrom = picked; } else { _historyTo = picked; } }
    });
  }

  List<AdminLeaveRequest> _filter(List<AdminLeaveRequest> input, String query, DateTime? from, DateTime? to) => input.where((l) {
        final q = query.trim().toLowerCase();
        return (q.isEmpty || '${l.coachName ?? ''} ${l.reason} ${l.decisionNote ?? ''} ${l.startDate} ${l.endDate} ${l.status}'.toLowerCase().contains(q)) &&
            (from == null || l.startDate.compareTo(from.toIso8601String().substring(0, 10)) >= 0) &&
            (to == null || l.endDate.compareTo(to.toIso8601String().substring(0, 10)) <= 0);
      }).toList();

  @override
  void initState() {
    super.initState();
    _loadPending();
    _loadHistory();
  }

  Future<void> _loadPending() async {
    setState(() => _pendingLoading = true);
    try {
      final data = await ApiClient.instance.get('/leave/pending') as List;
      _pending = data.map((e) => AdminLeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _pendingLoading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      final query = <String, dynamic>{};
      if (_statusFilter != null) query['status_filter'] = _statusFilter;
      final data = await ApiClient.instance.get('/leave', query: query) as List;
      _history = data.map((e) => AdminLeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadPending();
    await _loadHistory();
  }

  Future<String?> _promptReason(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Confirm')),
        ],
      ),
    ).then((value) {
      ctrl.dispose();
      return value;
    });
  }

  Future<void> _decide(AdminLeaveRequest l, bool approve) async {
    setState(() => _busyId = l.id);
    try {
      if (approve) {
        await ApiClient.instance.put('/leave/${l.id}/approve', body: {'note': null});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave approved')));
      } else {
        final note = await _promptReason('Reason for rejecting');
        if (note == null) {
          setState(() => _busyId = null);
          return; // cancelled the dialog
        }
        await ApiClient.instance.put('/leave/${l.id}/reject', body: {'note': note.isEmpty ? null : note});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave rejected')));
      }
      await _refreshAll();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
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
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Pending Leave Requests', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              "Approve or reject a coach's leave request. Coaches are notified either way.",
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(decoration: InputDecoration(labelText: 'Search pending requests', prefixIcon: const Icon(Icons.search), suffixIcon: _pendingSearch.isEmpty ? null : IconButton(onPressed: () => setState(() => _pendingSearch = ''), icon: const Icon(Icons.clear))), onChanged: (v) => setState(() => _pendingSearch = v)),
            Wrap(spacing: 8, children: [OutlinedButton(onPressed: () => _pickDate(pending: true, from: true), child: Text(_pendingFrom == null ? 'From date' : _pendingFrom!.toIso8601String().substring(0, 10))), OutlinedButton(onPressed: () => _pickDate(pending: true, from: false), child: Text(_pendingTo == null ? 'To date' : _pendingTo!.toIso8601String().substring(0, 10))), if (_pendingSearch.isNotEmpty || _pendingFrom != null || _pendingTo != null) TextButton(onPressed: () => setState(() { _pendingSearch = ''; _pendingFrom = null; _pendingTo = null; }), child: const Text('Clear filters'))]),
            if (_pendingLoading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_pending.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No leave requests awaiting a decision.')))
            else if (_filter(_pending, _pendingSearch, _pendingFrom, _pendingTo).isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No results found.')))
            else
              ..._filter(_pending, _pendingSearch, _pendingFrom, _pendingTo).map((l) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.coachName ?? 'Coach #${l.coachId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${l.startDate} to ${l.endDate}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          const SizedBox(height: 4),
                          Text(l.reason),
                          const SizedBox(height: 8),
                          _busyId == l.id
                              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                              : Wrap(
                                  spacing: 8,
                                  children: [
                                    ElevatedButton(onPressed: () => _decide(l, true), child: const Text('Approve')),
                                    OutlinedButton(
                                      onPressed: () => _decide(l, false),
                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                      child: const Text('Reject'),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                Text('Leave History', style: Theme.of(context).textTheme.titleLarge),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('All statuses'),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                    DropdownMenuItem<String?>(value: 'PENDING', child: Text('Pending')),
                    DropdownMenuItem<String?>(value: 'APPROVED', child: Text('Approved')),
                    DropdownMenuItem<String?>(value: 'REJECTED', child: Text('Rejected')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _loadHistory();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(decoration: InputDecoration(labelText: 'Search leave history', prefixIcon: const Icon(Icons.search), suffixIcon: _historySearch.isEmpty ? null : IconButton(onPressed: () => setState(() => _historySearch = ''), icon: const Icon(Icons.clear))), onChanged: (v) => setState(() => _historySearch = v)),
            Wrap(spacing: 8, children: [OutlinedButton(onPressed: () => _pickDate(pending: false, from: true), child: Text(_historyFrom == null ? 'From date' : _historyFrom!.toIso8601String().substring(0, 10))), OutlinedButton(onPressed: () => _pickDate(pending: false, from: false), child: Text(_historyTo == null ? 'To date' : _historyTo!.toIso8601String().substring(0, 10))), if (_historySearch.isNotEmpty || _historyFrom != null || _historyTo != null || _statusFilter != null) TextButton(onPressed: () { setState(() { _historySearch = ''; _historyFrom = null; _historyTo = null; _statusFilter = null; }); _loadHistory(); }, child: const Text('Clear filters'))]),
            if (_historyLoading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No leave requests found.')))
            else if (_filter(_history, _historySearch, _historyFrom, _historyTo).isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No results found.')))
            else
              ..._filter(_history, _historySearch, _historyFrom, _historyTo).map((l) {
                final decisionNote = l.decisionNote;
                final createdAt = l.createdAt;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(l.coachName ?? 'Coach #${l.coachId}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Chip(
                              label: Text(l.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                              backgroundColor: _statusColor(l.status),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${l.startDate} to ${l.endDate}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Text(l.reason),
                        if (decisionNote != null && decisionNote.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Note: $decisionNote', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                        if (createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Submitted ${DateTime.tryParse(createdAt)?.toLocal().toString().substring(0, 16) ?? createdAt}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
