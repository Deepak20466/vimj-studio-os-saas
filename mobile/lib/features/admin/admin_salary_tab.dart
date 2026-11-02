import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/export_helper.dart';
import '../../core/models.dart';
import '../shared/salary_filter_header.dart';

String _formatDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  return parsed == null ? isoDate : DateFormat('MMM d, yyyy').format(parsed);
}

class AdminSalaryTab extends StatefulWidget {
  const AdminSalaryTab({super.key});

  @override
  State<AdminSalaryTab> createState() => _AdminSalaryTabState();
}

class _AdminSalaryTabState extends State<AdminSalaryTab> {
  bool _loading = true;
  List<AdminSalaryRecord> _records = [];
  String? _error;
  String? _exporting;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  DateTime? _fromMonth;
  DateTime? _toMonth;

  List<AdminSalaryRecord> get _visibleRecords => _records.where((record) {
        final period = DateTime(record.year, record.month);
        final monthName = DateFormat('MMMM').format(period);
        final status = record.acknowledgedDate == null
            ? 'pending not acknowledged'
            : 'acknowledged paid received';
        return salaryMatchesFilters(
          year: record.year,
          month: record.month,
          search: _search,
          fromMonth: _fromMonth,
          toMonth: _toMonth,
          searchFields: [
            record.coachName,
            monthName,
            monthName.substring(0, 3),
            '${record.month}/${record.year}',
            '${monthName} ${record.year}',
            record.amount,
            status,
            record.notifiedAt,
            record.acknowledgedDate,
          ],
        );
      }).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFromMonth() async {
    final picked = await pickSalaryMonth(
      context,
      selectedMonth: _fromMonth,
      helpText: 'Select starting month',
    );
    if (picked == null) return;
    setState(() {
      _fromMonth = picked;
      if (_toMonth != null && _toMonth!.isBefore(picked)) _toMonth = picked;
    });
  }

  Future<void> _pickToMonth() async {
    final picked = await pickSalaryMonth(
      context,
      selectedMonth: _toMonth,
      helpText: 'Select ending month',
    );
    if (picked == null) return;
    setState(() {
      _toMonth = picked;
      if (_fromMonth != null && _fromMonth!.isAfter(picked)) {
        _fromMonth = picked;
      }
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _fromMonth = null;
      _toMonth = null;
    });
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiClient.instance.get('/salary') as List;
      _records = data
          .map((e) => AdminSalaryRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e is ApiException
          ? e.message
          : 'Could not load salary records. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SalaryForm(),
    );
    if (saved == true) await _load();
  }

  Future<void> _openEdit(AdminSalaryRecord r) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SalaryForm(editing: r),
    );
    if (saved == true) await _load();
  }

  Future<void> _remove(AdminSalaryRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete salary record?'),
        content: Text(
            'Delete the ${r.month}/${r.year} salary record for ${r.coachName ?? "Coach #${r.coachId}"}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('/salary/${r.id}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Salary record deleted')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Could not delete the salary record.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = format);
    try {
      final bytes = await ApiClient.instance
          .getBytes('/salary/export', query: {'fmt': format});
      final filename =
          format == 'csv' ? 'salary_records.csv' : 'salary_records.pdf';
      await shareExportedFile(bytes, filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is ApiException
                  ? e.message
                  : 'Salary export failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRecords = _visibleRecords;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-salary-fab',
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Add Salary'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SalaryFilterHeader(
                    searchController: _searchController,
                    onSearchChanged: (value) => setState(() => _search = value),
                    fromMonth: _fromMonth,
                    toMonth: _toMonth,
                    onPickFromMonth: _pickFromMonth,
                    onPickToMonth: _pickToMonth,
                    onClear: _clearFilters,
                    hasFilters: _search.isNotEmpty ||
                        _fromMonth != null ||
                        _toMonth != null,
                    visibleCount: visibleRecords.length,
                    totalCount: _records.length,
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _records.isEmpty || _exporting != null
                                  ? null
                                  : () => _export('pdf'),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: Text(_exporting == 'pdf'
                                  ? 'Preparing PDF...'
                                  : 'Download PDF'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _records.isEmpty || _exporting != null
                                  ? null
                                  : () => _export('csv'),
                              icon: const Icon(Icons.table_view_outlined),
                              label: Text(_exporting == 'csv'
                                  ? 'Preparing CSV...'
                                  : 'Download CSV'),
                            ),
                          ],
                        ),
                        if (_error != null)
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.cloud_off_outlined),
                              title: Text(_error!),
                              trailing: IconButton(
                                tooltip: 'Retry',
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                              ),
                            ),
                          ),
                        if (_error == null && _records.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child:
                                Center(child: Text('No salary records yet.')),
                          ),
                        if (_records.isNotEmpty && visibleRecords.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                                child: Text(
                                    'No salary records match these search and date filters.')),
                          ),
                        for (final r in visibleRecords)
                          Card(
                            margin: const EdgeInsets.only(top: 10),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: AppColors.brandLight,
                                    child: Icon(Icons.account_balance_wallet,
                                        color: AppColors.brandOrange),
                                  ),
                                  title: Text(
                                      r.coachName ?? 'Coach #${r.coachId}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                          '${r.month}/${r.year} · ₹${r.amount}'),
                                      Text(
                                        'Notified: ${r.notifiedAt != null ? _formatDate(r.notifiedAt!) : "-"}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: r.acknowledgedDate != null
                                      ? const Chip(
                                          label: Text('Acknowledged',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          backgroundColor: AppColors.success,
                                          visualDensity: VisualDensity.compact)
                                      : const Chip(
                                          label: Text('Pending',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          backgroundColor: AppColors.warning,
                                          visualDensity: VisualDensity.compact),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: r.acknowledgedDate != null
                                            ? null
                                            : () => _openEdit(r),
                                        child: const Text('Edit'),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton(
                                        onPressed: r.acknowledgedDate != null
                                            ? null
                                            : () => _remove(r),
                                        style: TextButton.styleFrom(
                                            foregroundColor: AppColors.danger),
                                        child: const Text('Delete'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SalaryForm extends StatefulWidget {
  final AdminSalaryRecord? editing;
  const _SalaryForm({this.editing});

  @override
  State<_SalaryForm> createState() => _SalaryFormState();
}

class _SalaryFormState extends State<_SalaryForm> {
  List<Coach> _coaches = [];
  int? _coachId;
  final _now = DateTime.now();
  late final _monthCtrl = TextEditingController(
      text: (widget.editing?.month ?? _now.month).toString());
  late final _yearCtrl = TextEditingController(
      text: (widget.editing?.year ?? _now.year).toString());
  late final _amountCtrl =
      TextEditingController(text: widget.editing?.amount ?? '');
  bool _loadingCoaches = true;
  bool _saving = false;
  String? _coachLoadError;

  @override
  void initState() {
    super.initState();
    _coachId = widget.editing?.coachId;
    if (widget.editing == null) {
      _loadCoaches();
    } else {
      _loadingCoaches = false;
    }
  }

  Future<void> _loadCoaches() async {
    if (mounted) {
      setState(() {
        _loadingCoaches = true;
        _coachLoadError = null;
      });
    }
    try {
      final data = await ApiClient.instance.get('/coaches') as List;
      _coaches =
          data.map((e) => Coach.fromJson(e as Map<String, dynamic>)).toList();
      if (_coaches.isEmpty) {
        _coachLoadError = 'Add an active coach before recording salary.';
      }
    } catch (e) {
      _coachLoadError = e is ApiException
          ? e.message
          : 'Could not load coaches. Tap Retry and try again.';
    } finally {
      if (mounted) setState(() => _loadingCoaches = false);
    }
  }

  Future<void> _submit() async {
    final month = int.tryParse(_monthCtrl.text.trim());
    final year = int.tryParse(_yearCtrl.text.trim());
    final amount = double.tryParse(_amountCtrl.text.trim());
    final validationError = _coachId == null && widget.editing == null
        ? 'Select a coach.'
        : month == null || month < 1 || month > 12
            ? 'Enter a month from 1 to 12.'
            : year == null || year < 2000 || year > 2200
                ? 'Enter a valid year from 2000 to 2200.'
                : amount == null || amount <= 0 || !amount.isFinite
                    ? 'Enter an amount greater than zero.'
                    : null;
    if (validationError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'month': month,
        'year': year,
        'amount': _amountCtrl.text.trim(),
      };
      if (widget.editing != null) {
        await ApiClient.instance
            .put('/salary/${widget.editing!.id}', body: body);
      } else {
        await ApiClient.instance
            .post('/salary', body: {...body, 'coach_id': _coachId});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final message = e is ApiException
            ? e.message
            : 'Could not save salary. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    _amountCtrl.dispose();
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
            Text(widget.editing != null ? 'Edit Salary Record' : 'Add Salary',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (widget.editing != null)
              TextField(
                enabled: false,
                controller: TextEditingController(
                    text: widget.editing!.coachName ??
                        'Coach #${widget.editing!.coachId}'),
                decoration: const InputDecoration(labelText: 'Coach'),
              )
            else if (_loadingCoaches)
              const Center(child: CircularProgressIndicator())
            else if (_coachLoadError != null)
              Card(
                child: ListTile(
                  title: Text(_coachLoadError!),
                  trailing: _coaches.isNotEmpty
                      ? null
                      : TextButton(
                          onPressed: _loadCoaches, child: const Text('Retry')),
                ),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _coachId,
                decoration: const InputDecoration(labelText: 'Coach'),
                items: _coaches
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _coachId = v),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Month'),
                    keyboardType: TextInputType.number,
                    controller: _monthCtrl,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                    controller: _yearCtrl,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Amount', prefixText: '₹ '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ||
                      _loadingCoaches ||
                      (widget.editing == null && _coaches.isEmpty)
                  ? null
                  : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.editing != null ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
