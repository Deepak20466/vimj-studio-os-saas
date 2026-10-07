import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/dismissed_items.dart';
import '../shared/pinned_search_section.dart';

const _missingAttendanceDismissKey = 'missing_attendance';

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  bool _loading = false;
  bool _summaryLoaded = false;
  bool _summaryFailed = false;
  bool _feeGraphLoaded = false;
  bool _feeGraphFailed = false;
  bool _missingLoaded = false;
  bool _missingFailed = false;
  bool _activityLoaded = false;
  bool _activityFailed = false;
  bool _revenueFailed = false;
  bool _revenueLoading = false;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _feeGraph;
  List<dynamic> _missing = [];
  List<dynamic> _activityBreakdown = [];
  String _revenuePeriod = 'month';
  DateTime _revenueMonth = DateTime.now();
  Map<String, dynamic>? _revenue;
  String _missingSearch = '';
  List<dynamic> get _visibleMissing => _missing.where((item) {
        final m = item as Map<String, dynamic>;
        return '${m['coach_name'] ?? ''} ${m['activity_name'] ?? ''} ${m['date'] ?? ''} ${m['end_time'] ?? ''}'
            .toLowerCase()
            .contains(_missingSearch.trim().toLowerCase());
      }).toList();

  String _money(dynamic value) =>
      '₹${(value is num ? value : double.tryParse('$value') ?? 0).toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _summaryFailed = false;
      _feeGraphFailed = false;
      _missingFailed = false;
      _activityFailed = false;
      _revenueFailed = false;
      _revenueLoading = true;
    });
    Future<void> loadPart(
      Future<dynamic> request,
      Future<void> Function(dynamic) apply,
      void Function() markLoaded,
      void Function() markFailed,
    ) async {
      try {
        await apply(await request);
      } on ApiException catch (e) {
        markFailed();
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        markFailed();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Unable to load a dashboard section.')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            markLoaded();
          });
        }
      }
    }

    try {
      await Future.wait([
        loadPart(
            ApiClient.instance.get('/dashboard/summary'),
            (v) async => _summary = v as Map<String, dynamic>,
            () => _summaryLoaded = true,
            () => _summaryFailed = true),
        loadPart(
            ApiClient.instance.get('/dashboard/fee-status'),
            (v) async => _feeGraph = v as Map<String, dynamic>,
            () => _feeGraphLoaded = true,
            () => _feeGraphFailed = true),
        loadPart(ApiClient.instance.get('/attendance/daily-missing'),
            (v) async {
          _missing = await DismissedItems.filter(
              _missingAttendanceDismissKey,
              v as List<dynamic>,
              (m) => (m as Map<String, dynamic>)['class_id'] as int);
        }, () => _missingLoaded = true, () => _missingFailed = true),
        loadPart(
            ApiClient.instance.get('/dashboard/activity-attendance'),
            (v) async => _activityBreakdown =
                (v as Map<String, dynamic>)['points'] as List<dynamic>? ?? [],
            () => _activityLoaded = true,
            () => _activityFailed = true),
        loadPart(
            ApiClient.instance.get('/dashboard/revenue', query: {
              'period': 'month',
              'month': DateTime.now().month,
              'year': DateTime.now().year
            }),
            (v) async => _revenue = v as Map<String, dynamic>, () {
          _revenueLoading = false;
        }, () => _revenueFailed = true),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRevenue(String period, {DateTime? month}) async {
    setState(() {
      _revenuePeriod = period;
      _revenueLoading = true;
      _revenueFailed = false;
      if (month != null) _revenueMonth = month;
    });
    try {
      _revenue = await ApiClient.instance.get('/dashboard/revenue', query: {
        'period': period,
        if (period == 'month') 'month': _revenueMonth.month,
        if (period != 'overall') 'year': _revenueMonth.year
      }) as Map<String, dynamic>;
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      _revenueFailed = true;
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      _revenueFailed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revenue details are unavailable.')),
        );
      }
    } finally {
      if (mounted) setState(() => _revenueLoading = false);
    }
  }

  Future<void> _dismissMissing(Map<String, dynamic> m) async {
    await DismissedItems.dismiss(
        _missingAttendanceDismissKey, m['class_id'] as int);
    if (mounted)
      setState(() => _missing = _missing
          .where(
              (x) => (x as Map<String, dynamic>)['class_id'] != m['class_id'])
          .toList());
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              height: 30,
              child: Text(label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4))),
          const SizedBox(height: 6),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandOrange))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary ?? {};
    final fees = _feeGraph ?? {'paid': 0, 'unpaid': 0, 'overdue': 0};
    final paid = (fees['paid'] as num?)?.toDouble() ?? 0;
    final unpaid = (fees['unpaid'] as num?)?.toDouble() ?? 0;
    final overdue = (fees['overdue'] as num?)?.toDouble() ?? 0;
    final total = paid + unpaid + overdue;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_summaryFailed && _summary == null)
            Card(
                child: ListTile(
                    title: const Text('Dashboard data is unavailable'),
                    trailing: IconButton(
                        icon: const Icon(Icons.refresh), onPressed: _load))),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [
              _statCard('Students',
                  _summaryLoaded ? '${s['total_students'] ?? '—'}' : '…'),
              _statCard('Coaches',
                  _summaryLoaded ? '${s['total_coaches'] ?? '—'}' : '…'),
              _statCard(
                  'Classes this month',
                  _summaryLoaded
                      ? '${s['total_classes_this_month'] ?? '—'}'
                      : '…'),
              _statCard(
                  _revenuePeriod == 'month'
                      ? 'Monthly revenue'
                      : _revenuePeriod == 'year'
                          ? 'Yearly revenue'
                          : 'Overall revenue',
                  '₹${_revenue?['total_revenue'] ?? s['monthly_revenue'] ?? 0}'),
              _statCard('Unpaid/overdue fees',
                  _summaryLoaded ? '${s['unpaid_fees_count'] ?? '—'}' : '…'),
            ],
          ),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Revenue period',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                            _revenuePeriod == 'month'
                                ? '${_revenueMonth.month}/${_revenueMonth.year}'
                                : _revenuePeriod == 'year'
                                    ? '${_revenueMonth.year}'
                                    : 'All collected revenue',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, children: [
                          ChoiceChip(
                              label: const Text('Current month'),
                              selected: _revenuePeriod == 'month' &&
                                  _revenueMonth.month == DateTime.now().month &&
                                  _revenueMonth.year == DateTime.now().year,
                              onSelected: (_) =>
                                  _loadRevenue('month', month: DateTime.now())),
                          ChoiceChip(
                              label: const Text('Choose month'),
                              selected: _revenuePeriod == 'month' &&
                                  !(_revenueMonth.month ==
                                          DateTime.now().month &&
                                      _revenueMonth.year ==
                                          DateTime.now().year),
                              onSelected: (_) async {
                                final d = await showDatePicker(
                                    context: context,
                                    initialDate: _revenueMonth,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100));
                                if (d != null) _loadRevenue('month', month: d);
                              }),
                          ChoiceChip(
                              label: const Text('Yearly'),
                              selected: _revenuePeriod == 'year',
                              onSelected: (_) => _loadRevenue('year')),
                          ChoiceChip(
                              label: const Text('Overall'),
                              selected: _revenuePeriod == 'overall',
                              onSelected: (_) => _loadRevenue('overall')),
                        ]),
                        if (_revenueLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(),
                          ),
                        if (_revenueFailed && _revenue == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text(
                                'Revenue details are unavailable. Pull to retry.'),
                          ),
                        if (_revenue != null)
                          Wrap(spacing: 12, runSpacing: 4, children: [
                            Text('Fees ${_money(_revenue!['fee_revenue'])}'),
                            Text(
                                'Products ${_money(_revenue!['product_revenue'])}'),
                            Text('Total ${_money(_revenue!['total_revenue'])}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold))
                          ]),
                      ]))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fee Status',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (!_feeGraphLoaded)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()))
                else if (_feeGraphFailed && _feeGraph == null)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text(
                              'Fee status is unavailable. Pull to retry.')))
                else if (total == 0)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No fee data yet.')))
                else
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: [
                          if (paid > 0)
                            PieChartSectionData(
                                value: paid,
                                color: AppColors.success,
                                title: 'Paid\n${paid.toInt()}',
                                radius: 70,
                                titleStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          if (unpaid > 0)
                            PieChartSectionData(
                                value: unpaid,
                                color: AppColors.warning,
                                title: 'Unpaid\n${unpaid.toInt()}',
                                radius: 70,
                                titleStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          if (overdue > 0)
                            PieChartSectionData(
                                value: overdue,
                                color: AppColors.danger,
                                title: 'Overdue\n${overdue.toInt()}',
                                radius: 70,
                                titleStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                        ],
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Activity Attendance %',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (!_activityLoaded)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()))
                else if (_activityFailed && _activityBreakdown.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text(
                              'Activity data is unavailable. Pull to retry.')))
                else if (_activityBreakdown.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text('No activity data for this period.')))
                else
                  SizedBox(
                    height: 180,
                    child: BarChart(
                      BarChartData(
                        barGroups: [
                          for (int i = 0; i < _activityBreakdown.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                  toY: (_activityBreakdown[i]
                                          ['avg_attendance_pct'] as num)
                                      .toDouble(),
                                  color: AppColors.brandOrange,
                                  width: 18,
                                  borderRadius: BorderRadius.circular(4)),
                            ]),
                        ],
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= _activityBreakdown.length)
                                  return const SizedBox.shrink();
                                final name = _activityBreakdown[idx]
                                    ['activity_name'] as String;
                                return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                        name.length > 8
                                            ? '${name.substring(0, 8)}…'
                                            : name,
                                        style: const TextStyle(fontSize: 9)));
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  getTitlesWidget: (v, m) => Text(
                                      '${v.toInt()}%',
                                      style: const TextStyle(fontSize: 9)))),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PinnedSearchSection(
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  search: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Coaches Missing Attendance Today',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextField(
                          decoration: InputDecoration(
                              labelText: 'Search coach, activity, or date',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _missingSearch.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () =>
                                          setState(() => _missingSearch = ''),
                                      icon: const Icon(Icons.clear))),
                          onChanged: (v) => setState(() => _missingSearch = v)),
                    ],
                  ),
                  results: Column(children: [
                    if (!_missingLoaded)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()))
                    else if (_missingFailed && _missing.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Attendance alerts are unavailable. Pull to retry.'))
                    else if (_missing.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'All coaches have marked attendance for ended classes today.'))
                    else if (_visibleMissing.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No results found.'))
                    else
                      ..._visibleMissing.map((m) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(m['coach_name'] ?? '-'),
                            subtitle: Text(
                                '${m['activity_name'] ?? '-'} · ${m['date'] ?? ''} · ends ${m['end_time'] ?? ''}'),
                            leading: const Icon(Icons.warning_amber_rounded,
                                color: AppColors.warning),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.danger),
                              tooltip: 'Dismiss this alert',
                              onPressed: () =>
                                  _dismissMissing(m as Map<String, dynamic>),
                            ),
                          )),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
