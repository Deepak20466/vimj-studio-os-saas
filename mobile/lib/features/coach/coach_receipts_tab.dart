import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';

class CoachReceiptsTab extends StatefulWidget {
  const CoachReceiptsTab({super.key});

  @override
  State<CoachReceiptsTab> createState() => _CoachReceiptsTabState();
}

class _CoachReceiptsTabState extends State<CoachReceiptsTab> {
  List<FeeReceiptRecord> _receipts = [];
  List<RosterStudent> _students = [];
  bool _loading = true;
  int? _downloadingId;
  int? _downloadingCsvId;
  String _search = '';
  String _statusFilter = 'ALL';
  int? _monthFilter;
  int? _yearFilter;

  List<FeeReceiptRecord> get _visibleReceipts {
    final query = _search.trim().toLowerCase();
    return _receipts.where((r) {
      final student =
          (r.studentName ?? 'Student #${r.studentId}').toLowerCase();
      final matchesSearch = query.isEmpty ||
          student.contains(query) ||
          r.paymentMode.toLowerCase().contains(query) ||
          (r.productName ?? '').toLowerCase().contains(query) ||
          (r.billingDate ?? '${r.month}/${r.year}')
              .toLowerCase()
              .contains(query);
      return matchesSearch &&
          (_statusFilter == 'ALL' || r.status == _statusFilter) &&
          (_monthFilter == null || r.month == _monthFilter) &&
          (_yearFilter == null || r.year == _yearFilter);
    }).toList();
  }

  Future<void> _chooseMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_yearFilter ?? now.year, _monthFilter ?? now.month),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _monthFilter = picked.month;
        _yearFilter = picked.year;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = await AuthStorage.load();
      final results = await Future.wait([
        ApiClient.instance.get('/receipts/my'),
        session != null
            ? ApiClient.instance.get('/coaches/${session.userId}/activities')
            : Future.value([]),
      ]);
      _receipts = (results[0] as List)
          .map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      final activities = (results[1] as List)
          .map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>))
          .toList();
      final rosters = await Future.wait(activities.map(
          (a) => ApiClient.instance.get('/activities/${a.activityId}/roster')));
      final seen = <int>{};
      _students = [];
      for (final r in rosters) {
        for (final e in (r as List)) {
          final s = RosterStudent.fromJson(e as Map<String, dynamic>);
          if (seen.add(s.id)) _students.add(s);
        }
      }
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleRecordPaymentTap() {
    if (_students.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No students yet'),
          content: const Text(
              "You don't have any students yet — add one under My Students before recording a payment."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'))
          ],
        ),
      );
      return;
    }
    _openForm();
  }

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceiptForm(students: _students),
    );
    if (saved == true) _load();
  }

  Future<void> _downloadPdf(FeeReceiptRecord r) async {
    setState(() => _downloadingId = r.id);
    try {
      final bytes = await ApiClient.instance.getBytes('/receipts/${r.id}/pdf');
      await shareExportedFile(bytes, 'receipt_${r.id}.pdf');
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  Future<void> _downloadCsv(FeeReceiptRecord r) async {
    setState(() => _downloadingCsvId = r.id);
    try {
      final bytes = await ApiClient.instance
          .getBytes('/receipts/${r.id}/pdf', query: {'fmt': 'csv'});
      await shareExportedFile(bytes, 'receipt_${r.id}.csv');
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _downloadingCsvId = null);
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
      appBar: AppBar(
          title: const Text('Fee Receipts'),
          actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-receipts-fab',
        onPressed: _handleRecordPaymentTap,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: _loading && _receipts.isEmpty && _students.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _students.isEmpty
                  ? ListView(children: const [
                      Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text(
                                  "You don't have any students yet — add one under My Students before recording a payment.")))
                    ])
                  : _receipts.isEmpty
                      ? ListView(children: const [
                          Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(
                                  child:
                                      Text('No fee receipts submitted yet.')))
                        ])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          children: [
                            TextField(
                              decoration: InputDecoration(
                                hintText:
                                    'Search student, product, date, or mode',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _search.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () =>
                                            setState(() => _search = ''),
                                      ),
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (value) =>
                                  setState(() => _search = value),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                DropdownButton<String>(
                                  value: _statusFilter,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'ALL',
                                        child: Text('All statuses')),
                                    DropdownMenuItem(
                                        value: 'PENDING',
                                        child: Text('Pending')),
                                    DropdownMenuItem(
                                        value: 'APPROVED',
                                        child: Text('Approved')),
                                    DropdownMenuItem(
                                        value: 'REJECTED',
                                        child: Text('Rejected')),
                                  ],
                                  onChanged: (value) => setState(
                                      () => _statusFilter = value ?? 'ALL'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _chooseMonth,
                                  icon: const Icon(Icons.calendar_month),
                                  label: Text(_monthFilter == null
                                      ? 'Any month'
                                      : '$_monthFilter/$_yearFilter'),
                                ),
                                if (_monthFilter != null ||
                                    _statusFilter != 'ALL')
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _monthFilter = null;
                                      _yearFilter = null;
                                      _statusFilter = 'ALL';
                                    }),
                                    child: const Text('Clear filters'),
                                  ),
                              ],
                            ),
                            if (_visibleReceipts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                    child: Text(
                                        'No receipts match these search and filter options.')),
                              ),
                            ..._visibleReceipts.map((r) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(
                                        '${r.studentName ?? "Student #${r.studentId}"} — ${r.productName?.isNotEmpty == true ? "${r.productName}: " : ""}₹${r.amount} + product ${r.productAmount} = ${(double.parse(r.amount) + double.parse(r.productAmount)).toStringAsFixed(2)}'),
                                    subtitle: Text(
                                        '${r.billingDate ?? "${r.month}/${r.year}"} · ${r.paymentMode}${r.decisionNote != null ? "\n${r.decisionNote}" : ""}'),
                                    isThreeLine: r.decisionNote != null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _downloadingId == r.id
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : IconButton(
                                                icon: const Icon(Icons
                                                    .picture_as_pdf_outlined),
                                                tooltip: 'Receipt (PDF)',
                                                onPressed: () =>
                                                    _downloadPdf(r)),
                                        _downloadingCsvId == r.id
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : IconButton(
                                                icon: const Icon(
                                                    Icons.table_chart_outlined),
                                                tooltip: 'Receipt (CSV)',
                                                onPressed: () =>
                                                    _downloadCsv(r)),
                                        Chip(
                                            label: Text(r.status,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white)),
                                            backgroundColor:
                                                _statusColor(r.status)),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ),
            ),
    );
  }
}

class _ReceiptForm extends StatefulWidget {
  final List<RosterStudent> students;
  const _ReceiptForm({required this.students});

  @override
  State<_ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends State<_ReceiptForm> {
  late int? _studentId =
      widget.students.isNotEmpty ? widget.students.first.id : null;
  final _amountCtrl = TextEditingController();
  final _productCtrl = TextEditingController(text: "0");
  final _productNameCtrl = TextEditingController();
  String _studentSearch = "";
  final _noteCtrl = TextEditingController();
  DateTime? _billingDate;
  String _paymentMode = 'CASH';
  bool _saving = false;
  String? _error;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(text: _now.month.toString());
  late final _yearCtrl = TextEditingController(text: _now.year.toString());

  Future<void> _submit() async {
    if (_studentId == null || _amountCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Student and amount are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.post('/receipts', body: {
        'billing_date': _billingDate?.toIso8601String().split('T').first,
        'student_id': _studentId,
        'amount': _amountCtrl.text.trim(),
        'product_amount': _productCtrl.text.trim(),
        'product_name': _productNameCtrl.text.trim().isEmpty
            ? null
            : _productNameCtrl.text.trim(),
        'month': int.tryParse(_monthCtrl.text.trim()) ?? _now.month,
        'year': int.tryParse(_yearCtrl.text.trim()) ?? _now.year,
        'payment_mode': _paymentMode,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _productCtrl.dispose();
    _productNameCtrl.dispose();
    _noteCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New Fee Receipt',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
                decoration: const InputDecoration(labelText: "Search student"),
                onChanged: (v) => setState(() => _studentSearch = v)),
            TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _billingDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (d != null)
                    setState(() {
                      _billingDate = d;
                      _monthCtrl.text = d.month.toString();
                      _yearCtrl.text = d.year.toString();
                    });
                },
                child: Text(_billingDate == null
                    ? "Select billing date (optional)"
                    : _billingDate!.toIso8601String().split("T").first)),
            DropdownButtonFormField<int>(
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
              items: widget.students
                  .where((s) =>
                      s.id == _studentId ||
                      s.name
                          .toLowerCase()
                          .contains(_studentSearch.toLowerCase()))
                  .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _studentId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _monthCtrl,
                    decoration: const InputDecoration(labelText: 'Month'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _yearCtrl,
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _productCtrl,
                decoration: const InputDecoration(labelText: "Product Amount"),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            TextField(
                controller: _productNameCtrl,
                decoration: const InputDecoration(
                    labelText: "Product Name (optional)")),
            TextField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                DropdownMenuItem(value: 'CARD', child: Text('Card')),
                DropdownMenuItem(
                    value: 'BANK_TRANSFER', child: Text('Bank Transfer')),
              ],
              onChanged: (v) => setState(() => _paymentMode = v!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit for Approval'),
            ),
          ],
        ),
      ),
    );
  }
}
