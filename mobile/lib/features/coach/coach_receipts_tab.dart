import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';
import '../shared/notification_bell_action.dart';
import '../shared/pinned_search_section.dart';

class CoachReceiptsTab extends StatefulWidget {
  const CoachReceiptsTab({super.key});

  @override
  State<CoachReceiptsTab> createState() => _CoachReceiptsTabState();
}

class _CoachReceiptsTabState extends State<CoachReceiptsTab> {
  List<FeeReceiptRecord> _receipts = [];
  List<AdminFeeRecord> _fees = [];
  List<RosterStudent> _students = [];
  bool _loading = true;
  String? _loadError;
  int? _downloadingId;
  int? _downloadingCsvId;
  String _search = '';
  String _statusFilter = 'ALL';
  int? _monthFilter;
  int? _yearFilter;
  String _feeSearch = '';
  String _feeStatusFilter = 'ALL';
  int? _feeMonthFilter;
  int? _feeYearFilter;

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

  List<AdminFeeRecord> get _visibleFees {
    final query = _feeSearch.trim().toLowerCase();
    return _fees.where((fee) {
      final student =
          (fee.studentName ?? 'Student #${fee.studentId}').toLowerCase();
      final period = '${fee.month}/${fee.year}';
      return (query.isEmpty ||
              student.contains(query) ||
              period.contains(query) ||
              (fee.productName ?? '').toLowerCase().contains(query)) &&
          (_feeStatusFilter == 'ALL' || fee.status == _feeStatusFilter) &&
          (_feeMonthFilter == null || fee.month == _feeMonthFilter) &&
          (_feeYearFilter == null || fee.year == _feeYearFilter);
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

  Future<void> _chooseFeeMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
          _feeYearFilter ?? now.year, _feeMonthFilter ?? now.month),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _feeMonthFilter = picked.month;
        _feeYearFilter = picked.year;
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
    final errors = <String>[];
    await Future.wait([
      _loadFeeLedger(errors),
      _loadReceipts(errors),
      _loadStudents(errors),
    ]);
    if (mounted) {
      setState(() {
        _loading = false;
        _loadError = errors.isEmpty ? null : errors.join('\n');
      });
    }
  }

  Future<void> _loadFeeLedger(List<String> errors) async {
    try {
      final data = await ApiClient.instance.getAllPages('/fees/my');
      _fees = data
          .map((e) => AdminFeeRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      errors.add('Admin fee records: ${e.message}');
    } catch (_) {
      errors.add('Admin fee records could not be loaded. Pull to retry.');
    }
  }

  Future<void> _loadReceipts(List<String> errors) async {
    try {
      final data = await ApiClient.instance.get('/receipts/my') as List;
      _receipts = data
          .map((e) => FeeReceiptRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      errors.add('Payment receipts: ${e.message}');
    } catch (_) {
      errors.add('Payment receipts could not be loaded. Pull to retry.');
    }
  }

  Future<void> _loadStudents(List<String> errors) async {
    try {
      final session = await AuthStorage.load();
      if (session == null) {
        _students = [];
        return;
      }
      final activityData = await ApiClient.instance
          .get('/coaches/${session.userId}/activities') as List;
      final activities = activityData
          .map((e) => CoachActivityLink.fromJson(e as Map<String, dynamic>))
          .toList();
      final rosterResults = await Future.wait(activities.map((activity) async {
        try {
          return await ApiClient.instance
              .get('/activities/${activity.activityId}/roster') as List;
        } on ApiException catch (e) {
          errors.add('Student roster: ${e.message}');
          return <dynamic>[];
        } catch (_) {
          errors.add('A student roster could not be loaded. Pull to retry.');
          return <dynamic>[];
        }
      }));
      final seen = <int>{};
      _students = [];
      for (final roster in rosterResults) {
        for (final row in roster) {
          final student = RosterStudent.fromJson(row as Map<String, dynamic>);
          if (seen.add(student.id)) _students.add(student);
        }
      }
    } on ApiException catch (e) {
      errors.add('Student roster: ${e.message}');
    } catch (_) {
      errors.add('Student roster could not be loaded. Pull to retry.');
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

  Color _feeStatusColor(String status) {
    switch (status) {
      case 'PAID':
        return AppColors.success;
      case 'OVERDUE':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Fees & Receipts'),
          actions: const [NotificationBellAction(), SizedBox(width: 4)]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'coach-receipts-fab',
        onPressed: _handleRecordPaymentTap,
        icon: const Icon(Icons.add),
        label: const Text('Record Payment'),
      ),
      body: _loading && _fees.isEmpty && _receipts.isEmpty && _students.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  if (_loadError != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.sync_problem),
                        title: Text(_loadError!),
                        trailing: IconButton(
                          tooltip: 'Retry loading fees and receipts',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  _buildFeeLedger(),
                  const Divider(height: 32),
                  _buildReceipts(),
                ],
              ),
            ),
    );
  }

  Widget _buildFeeLedger() {
    final fees = _visibleFees;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Fees from Admin', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Fee records for students in your assigned activities.'),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search student, product, or billing period',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _feeSearch.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _feeSearch = ''),
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _feeSearch = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: _feeStatusFilter,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All fee statuses')),
                DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                DropdownMenuItem(value: 'OVERDUE', child: Text('Overdue')),
              ],
              onChanged: (value) =>
                  setState(() => _feeStatusFilter = value ?? 'ALL'),
            ),
            OutlinedButton.icon(
              onPressed: _chooseFeeMonth,
              icon: const Icon(Icons.calendar_month),
              label: Text(_feeMonthFilter == null
                  ? 'Any month'
                  : '$_feeMonthFilter/$_feeYearFilter'),
            ),
            if (_feeMonthFilter != null ||
                _feeStatusFilter != 'ALL' ||
                _feeSearch.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _feeMonthFilter = null;
                  _feeYearFilter = null;
                  _feeStatusFilter = 'ALL';
                  _feeSearch = '';
                }),
                child: const Text('Clear filters'),
              ),
          ],
        ),
        if (_fees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(_loading
                  ? 'Loading fee records...'
                  : 'No fee records have been shared for your assigned students.'),
            ),
          )
        else if (fees.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No fees match these filters.')),
          )
        else
          ...fees.map((fee) {
            final total = ((double.tryParse(fee.amount) ?? 0) +
                    (double.tryParse(fee.productAmount) ?? 0))
                .toStringAsFixed(2);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                    '${fee.studentName ?? "Student #${fee.studentId}"} - ${fee.month}/${fee.year}'),
                subtitle: Text(
                    'Total Rs $total | Balance Rs ${fee.balanceAmount}\nDue ${fee.dueDate}${fee.productName?.isNotEmpty == true ? " | ${fee.productName}" : ""}'),
                isThreeLine: true,
                trailing: Chip(
                  label: Text(fee.status,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white)),
                  backgroundColor: _feeStatusColor(fee.status),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildReceipts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Payment Receipts', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Payments you submit are sent to Admin for review.'),
        if (_students.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'No assigned students are available for recording a payment. Your existing receipt history remains available.'),
          ),
        const SizedBox(height: 8),
        PinnedSearchSection(
          padding: EdgeInsets.zero,
          search: TextField(
            decoration: InputDecoration(
              hintText: 'Search student, product, date, or mode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _search = ''),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          results: Column(
            children: [
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
                          value: 'ALL', child: Text('All statuses')),
                      DropdownMenuItem(
                          value: 'PENDING', child: Text('Pending')),
                      DropdownMenuItem(
                          value: 'APPROVED', child: Text('Approved')),
                      DropdownMenuItem(
                          value: 'REJECTED', child: Text('Rejected')),
                    ],
                    onChanged: (value) =>
                        setState(() => _statusFilter = value ?? 'ALL'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseMonth,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_monthFilter == null
                        ? 'Any month'
                        : '$_monthFilter/$_yearFilter'),
                  ),
                  if (_monthFilter != null || _statusFilter != 'ALL')
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
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(_receipts.isEmpty
                        ? 'No fee receipts submitted yet.'
                        : 'No receipts match these search and filter options.'),
                  ),
                ),
              ..._visibleReceipts.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                          '${r.studentName ?? "Student #${r.studentId}"} - ${r.productName?.isNotEmpty == true ? "${r.productName}: " : ""}Rs ${r.amount} + product ${r.productAmount} = ${(double.parse(r.amount) + double.parse(r.productAmount)).toStringAsFixed(2)}'),
                      subtitle: Text(
                          '${r.billingDate ?? "${r.month}/${r.year}"} | ${r.paymentMode}${r.decisionNote != null ? "\n${r.decisionNote}" : ""}'),
                      isThreeLine: r.decisionNote != null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _downloadingId == r.id
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon:
                                      const Icon(Icons.picture_as_pdf_outlined),
                                  tooltip: 'Receipt (PDF)',
                                  onPressed: () => _downloadPdf(r)),
                          _downloadingCsvId == r.id
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.table_chart_outlined),
                                  tooltip: 'Receipt (CSV)',
                                  onPressed: () => _downloadCsv(r)),
                          Chip(
                            label: Text(r.status,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white)),
                            backgroundColor: _statusColor(r.status),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ],
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
