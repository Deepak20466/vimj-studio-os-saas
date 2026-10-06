import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/export_helper.dart';
class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});
  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}
class _AdminReportsTabState extends State<AdminReportsTab> {
  DateTime _period = DateTime.now();
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  String _activitySearch = '';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _busy = true; _data = null; _error = null; });
    try {
      final data = await ApiClient.instance.get('/reports', query: {'month': _period.month, 'year': _period.year});
      if (mounted) setState(() => _data = data as Map<String, dynamic>);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _pdf(String kind) async {
    try { final bytes = await ApiClient.instance.getBytes('/reports', query: {'month': _period.month, 'year': _period.year, 'kind': kind, 'fmt': 'pdf'}); await shareExportedFile(bytes, '${kind}_${_period.year}_${_period.month}.pdf'); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Text('Reports - ${_period.month}/${_period.year}', style: Theme.of(context).textTheme.titleLarge),
    Wrap(spacing: 8, children: [
      TextButton(onPressed: _busy ? null : () { _period = DateTime(_period.year, _period.month - 1); _load(); }, child: const Text('Previous Month')),
      TextButton(onPressed: _busy ? null : () async { final d = await showDatePicker(context: context, initialDate: _period, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) { _period = d; _load(); } }, child: const Text('Select Month')),
      TextButton(onPressed: _busy ? null : () { _period = DateTime(_period.year, _period.month + 1); _load(); }, child: const Text('Next Month')),
    ]),
    if (_busy) const Center(child: CircularProgressIndicator()),
    if (_error != null) Text(_error!),
    if (_data != null) ...[
      Text('Overall revenue: Rs ${_data!["total_revenue"]}', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text('Products included: Rs ${_data!["product_revenue"]}'),
      Text(_data!["revenue_basis"].toString()),
      Text('Classes done: ${_data!["classes_done"]} · Fees paid: Rs ${_data!["fee_paid_total"]} · Fees pending: Rs ${_data!["fee_pending_total"]}'),
      for (final kind in ['students_summary', 'attendance', 'classes', 'fees_paid', 'fees_pending', 'revenue']) ElevatedButton(onPressed: () => _pdf(kind), child: Text({'students_summary': 'Student Attendance & Classes', 'attendance': 'Activity Attendance', 'classes': 'Classes Done', 'fees_paid': 'Fees Paid', 'fees_pending': 'Fees Pending', 'revenue': 'Activity & Overall Revenue'}[kind]! + ' PDF')),
      TextField(decoration: InputDecoration(labelText: 'Search activity report', prefixIcon: const Icon(Icons.search), suffixIcon: _activitySearch.isEmpty ? null : IconButton(onPressed: () => setState(() => _activitySearch = ''), icon: const Icon(Icons.clear))), onChanged: (v) => setState(() => _activitySearch = v)),
      if ((_data!["activities"] as List).where((a) => a['activity'].toString().toLowerCase().contains(_activitySearch.trim().toLowerCase())).isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No results found.')),
      for (final a in (_data!["activities"] as List).where((a) => a['activity'].toString().toLowerCase().contains(_activitySearch.trim().toLowerCase()))) Card(child: ListTile(title: Text(a['activity'].toString()), subtitle: Text('Present ${a["present"]}, Absent ${a["absent"]}, Leave ${a["leave"]}, Not Confirm ${a["not_confirm"]}\nRevenue: Rs ${a["revenue"]}'))),
      Text('Unassigned revenue: Rs ${_data!["unassigned_revenue"]}'),
    ],
  ]);
}
