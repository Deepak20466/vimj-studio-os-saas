import 'dart:async';

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

class _AdminDashboardTabState extends State<AdminDashboardTab>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _insightsLoaded = false;
  bool _insightsFailed = false;
  bool _missingLoaded = false;
  bool _missingFailed = false;
  bool _revenueFailed = false;
  bool _revenueLoading = false;
  bool _sendingReminders = false;
  bool _insightsRefreshing = false;
  String _insightFilter = '';
  Map<String, dynamic>? _insights;
  Map<String, double>? _insightChange;
  DateTime? _insightsUpdatedAt;
  Timer? _insightsTimer;
  String _insightFocus = 'risk';
  List<dynamic> _missing = [];
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
      'Rs ${(value is num ? value : double.tryParse('$value') ?? 0).toStringAsFixed(2)}';

  String _deltaDescription(double? value) {
    if (value == null || value == 0) return 'unchanged';
    final direction = value > 0 ? 'up' : 'down';
    return '$direction ${_money(value.abs())}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _insightsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_insightsRefreshing &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refreshInsights();
      }
    });
  }

  @override
  void dispose() {
    _insightsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _insights != null) {
      _refreshInsights();
    }
  }

  Future<void> _refreshInsights() async {
    if (_insightsRefreshing || _loading) return;
    if (mounted) setState(() => _insightsRefreshing = true);
    try {
      final next = await ApiClient.instance.get('/insights/revenue-risk')
          as Map<String, dynamic>;
      if (!mounted) return;
      final previous = _insights;
      setState(() {
        if (previous != null) {
          _insightChange = {
            'risk': _metric(next, 'summary', 'total_at_risk') -
                _metric(previous, 'summary', 'total_at_risk'),
            'forecast': _metric(next, 'forecast', 'next_month_revenue') -
                _metric(previous, 'forecast', 'next_month_revenue'),
          };
        }
        _insights = next;
        _insightsUpdatedAt = DateTime.now();
        _insightsFailed = false;
        _insightsLoaded = true;
      });
    } catch (_) {
      // Keep the last good dashboard snapshot visible until the next refresh.
    } finally {
      if (mounted) setState(() => _insightsRefreshing = false);
    }
  }

  double _metric(Map<String, dynamic> root, String group, String key) {
    final values = root[group];
    if (values is! Map<String, dynamic>) return 0;
    final value = values[key];
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _insightsFailed = false;
      _missingFailed = false;
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
              content: Text('Unable to load a dashboard section.'),
            ),
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
          ApiClient.instance.get('/insights/revenue-risk'),
          (v) async {
            final next = v as Map<String, dynamic>;
            final previous = _insights;
            if (previous != null) {
              _insightChange = {
                'risk': _metric(next, 'summary', 'total_at_risk') -
                    _metric(previous, 'summary', 'total_at_risk'),
                'forecast': _metric(next, 'forecast', 'next_month_revenue') -
                    _metric(previous, 'forecast', 'next_month_revenue'),
              };
            }
            _insights = next;
            _insightsUpdatedAt = DateTime.now();
          },
          () => _insightsLoaded = true,
          () => _insightsFailed = true,
        ),
        loadPart(
          ApiClient.instance.get('/attendance/daily-missing'),
          (v) async {
            _missing = await DismissedItems.filter(
              _missingAttendanceDismissKey,
              v as List<dynamic>,
              (m) => (m as Map<String, dynamic>)['class_id'] as int,
            );
          },
          () => _missingLoaded = true,
          () => _missingFailed = true,
        ),
        loadPart(
          ApiClient.instance.get(
            '/dashboard/revenue',
            query: {
              'period': 'month',
              'month': DateTime.now().month,
              'year': DateTime.now().year,
            },
          ),
          (v) async => _revenue = v as Map<String, dynamic>,
          () {
            _revenueLoading = false;
          },
          () => _revenueFailed = true,
        ),
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
      _revenue = await ApiClient.instance.get(
        '/dashboard/revenue',
        query: {
          'period': period,
          if (period == 'month') 'month': _revenueMonth.month,
          if (period != 'overall') 'year': _revenueMonth.year,
        },
      ) as Map<String, dynamic>;
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
      _missingAttendanceDismissKey,
      m['class_id'] as int,
    );
    if (mounted)
      setState(
        () => _missing = _missing
            .where(
              (x) => (x as Map<String, dynamic>)['class_id'] != m['class_id'],
            )
            .toList(),
      );
  }

  Future<void> _sendReminders(Map<String, dynamic> risk) async {
    final feeIds = (risk['fee_ids'] as List<dynamic>? ?? [])
        .map((id) => int.tryParse('$id'))
        .whereType<int>()
        .toSet()
        .toList();
    if (feeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no overdue fees to remind.')),
      );
      return;
    }

    setState(() => _sendingReminders = true);
    var queued = 0;
    for (final feeId in feeIds) {
      try {
        await ApiClient.instance.post('/fees/$feeId/remind');
        queued++;
      } catch (_) {
        // Keep processing so one bad record cannot block the remaining reminders.
      }
    }
    if (!mounted) return;
    setState(() => _sendingReminders = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$queued of ${feeIds.length} fee reminder(s) queued.'),
      ),
    );
    if (queued > 0) _refreshInsights();
  }

  Widget _sectionCard({required String title, required Widget child}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );

  Widget _statCard(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 30,
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: valueColor ?? AppColors.brandOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchProfitabilityChart(List<dynamic> batches) {
    if (batches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('No batch analytics available yet.')),
      );
    }
    final sortedBatches = [...batches]
      ..sort((a, b) =>
          (((b as Map<String, dynamic>)['estimated_profit'] as num?)
                  ?.toDouble() ??
              0)
              .compareTo(
                  ((a as Map<String, dynamic>)['estimated_profit'] as num?)
                          ?.toDouble() ??
                      0));
    final maxProfit = sortedBatches.fold<double>(0, (maxValue, value) {
      final row = value as Map<String, dynamic>;
      final profit = (row['estimated_profit'] as num?)?.toDouble() ?? 0;
      return profit > maxValue ? profit : maxValue;
    });

    return Column(
      children: [
        const Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _ChartLegend(
              color: AppColors.brandOrange,
              label: 'Estimated revenue share',
            ),
            _ChartLegend(color: AppColors.success, label: 'Attendance'),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Estimated monthly revenue share from enrolled fees; expense data is not stored.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        for (final value in sortedBatches) ...[
          _BatchMetricBars(
            row: value as Map<String, dynamic>,
            maxProfit: maxProfit,
            money: _money,
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final insights = _insights ?? {};
    final kpis = insights['kpis'] is Map<String, dynamic>
        ? insights['kpis'] as Map<String, dynamic>
        : <String, dynamic>{};
    final summary = insights['summary'] is Map<String, dynamic>
        ? insights['summary'] as Map<String, dynamic>
        : <String, dynamic>{};
    final forecast = insights['forecast'] is Map<String, dynamic>
        ? insights['forecast'] as Map<String, dynamic>
        : <String, dynamic>{};
    final batchAnalytics = insights['batch_analytics'] is Map<String, dynamic>
        ? insights['batch_analytics'] as Map<String, dynamic>
        : <String, dynamic>{};
    final risks = insights['risks'] as List<dynamic>? ?? [];
    final feeRisk = risks.whereType<Map<String, dynamic>>().cast<Map<String, dynamic>>().firstWhere(
      (risk) => risk['type'] == 'fee_default',
      orElse: () => <String, dynamic>{},
    );
    final filterText = _insightFilter.trim().toLowerCase();
    final riskRows = <Map<String, dynamic>>[];
    final feeStudents = feeRisk['students'] as List<dynamic>? ?? [];
    for (final value in feeStudents) {
      if (value is! Map<String, dynamic>) continue;
      riskRows.add({
        'key': 'student-${value['student_id']}',
        'label': '${value['student_name'] ?? 'Student'}',
        'detail': '${(value['fees'] as List<dynamic>?)?.length ?? (value['fee_ids'] as List<dynamic>?)?.length ?? 0} overdue fee record(s)',
        'amount': value['pending_amount'],
        'type': 'Fee default',
      });
    }
    for (final value in risks) {
      if (value is! Map<String, dynamic> || value['type'] != 'attendance_drop') continue;
      for (final batchValue in value['batches'] as List<dynamic>? ?? []) {
        if (batchValue is! Map<String, dynamic>) continue;
        final weekdays = batchValue['attendance_drop_weekdays'] as List<dynamic>? ?? [];
        riskRows.add({
          'key': 'batch-risk-${batchValue['batch_id']}',
          'label': '${batchValue['batch_name'] ?? 'Batch'}',
          'detail': 'Attendance down ${((batchValue['attendance_drop_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}%${weekdays.isEmpty ? '' : ' on ${weekdays.join(', ')}'}',
          'amount': batchValue['revenue_at_risk'],
          'type': 'Attendance drop',
        });
      }
    }
    riskRows.sort((a, b) => ((b['amount'] as num?)?.toDouble() ?? 0)
        .compareTo((a['amount'] as num?)?.toDouble() ?? 0));
    final filteredRiskRows = riskRows.where((row) =>
      '${row['label']} ${row['detail']} ${row['type']}'.toLowerCase().contains(filterText)).toList();
    final batches = batchAnalytics['batches'] as List<dynamic>? ?? [];
    final profitRows = batches.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => ((b['estimated_profit'] as num?)?.toDouble() ?? 0)
          .compareTo((a['estimated_profit'] as num?)?.toDouble() ?? 0));
    final filteredProfitRows = profitRows.where((row) =>
      '${row['batch_name'] ?? ''}'.toLowerCase().contains(filterText)).toList();
    final monthlyCollections = (forecast['monthly_collections'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => ((b['collected'] as num?)?.toDouble() ?? 0)
          .compareTo((a['collected'] as num?)?.toDouble() ?? 0));
    final filteredForecastRows = monthlyCollections.where((row) =>
      '${row['month'] ?? ''}'.toLowerCase().contains(filterText)).toList();
    final totalAtRisk = (summary['total_at_risk'] as num?)?.toDouble() ?? 0;
    final predictedRevenue =
        (forecast['next_month_revenue'] as num?)?.toDouble() ?? 0;
    final forecastDelta = _insightChange?['forecast'];
    final riskDelta = _insightChange?['risk'];
    final forecastTrend = forecastDelta == null
        ? Icons.trending_flat
        : forecastDelta > 0
        ? Icons.trending_up
        : forecastDelta < 0
        ? Icons.trending_down
        : Icons.trending_flat;
    final forecastTrendColor = forecastDelta == null || forecastDelta == 0
        ? AppColors.textMuted
        : forecastDelta > 0
        ? AppColors.success
        : AppColors.danger;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Admin AI Command Center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (_insightsUpdatedAt != null)
                Text(
                  TimeOfDay.fromDateTime(_insightsUpdatedAt!).format(context),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              IconButton(
                tooltip: 'Refresh live insights',
                onPressed: _insightsRefreshing ? null : _refreshInsights,
                icon: _insightsRefreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_insightsFailed && _insights == null)
            Card(
              child: ListTile(
                title: const Text('Admin insights are unavailable'),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
            children: [
              _statCard(
                'Total Students',
                _insights != null ? '${kpis['total_students'] ?? '—'}' : '…',
              ),
              _statCard(
                'Today Present',
                _insights != null ? '${kpis['today_present'] ?? '—'}' : '…',
              ),
              _statCard(
                'Fee Pending Amount',
                _insights != null ? _money(kpis['fee_pending_amount']) : '…',
              ),
              _statCard(
                'Revenue at Risk',
                _insights != null ? _money(totalAtRisk) : '…',
                valueColor: totalAtRisk > 0
                    ? AppColors.danger
                    : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionCard(
            title: 'AI Command Center',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Most Risk'),
                      selected: _insightFocus == 'risk',
                      onSelected: (_) => setState(() => _insightFocus = 'risk'),
                    ),
                    ChoiceChip(
                      label: const Text('Most Profit'),
                      selected: _insightFocus == 'profit',
                      onSelected: (_) => setState(() => _insightFocus = 'profit'),
                    ),
                    ChoiceChip(
                      label: const Text('Future Forecast'),
                      selected: _insightFocus == 'forecast',
                      onSelected: (_) => setState(() => _insightFocus = 'forecast'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Filter this list',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _insightFilter.isEmpty ? null : IconButton(
                      tooltip: 'Clear filter',
                      onPressed: () => setState(() => _insightFilter = ''),
                      icon: const Icon(Icons.clear),
                    ),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _insightFilter = value),
                ),
                const SizedBox(height: 10),
                if (_insightsFailed && _insights == null)
                  const Text('Unable to load insights. Pull down to retry.')
                else if (!_insightsLoaded)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_insightFocus == 'risk')
                  filteredRiskRows.isEmpty
                      ? Text(riskRows.isEmpty ? 'No active risk signals.' : 'No matching risks.')
                      : Column(children: [
                          for (var i = 0; i < filteredRiskRows.length; i++)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.warning.withOpacity(0.12),
                                child: Text('${i + 1}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                              ),
                              title: Text('${filteredRiskRows[i]['label']}'),
                              subtitle: Text('${filteredRiskRows[i]['type']} · ${filteredRiskRows[i]['detail']}'),
                              trailing: Text(_money(filteredRiskRows[i]['amount']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger)),
                            ),
                          if ((feeRisk['fee_ids'] as List<dynamic>? ?? []).isNotEmpty)
                            Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
                              onPressed: _sendingReminders ? null : () => _sendReminders(feeRisk),
                              icon: _sendingReminders ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.notifications_active_outlined),
                              label: const Text('Send Reminders'),
                            )),
                        ])
                else if (_insightFocus == 'profit')
                  filteredProfitRows.isEmpty
                      ? Text(profitRows.isEmpty ? 'No active batches are available for comparison.' : 'No matching batches.')
                      : Column(children: [
                          for (var i = 0; i < filteredProfitRows.length; i++)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text('${filteredProfitRows[i]['batch_name'] ?? 'Batch'}'),
                              subtitle: Text('${((filteredProfitRows[i]['attendance_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}% recent attendance'),
                              trailing: Text(_money(filteredProfitRows[i]['estimated_profit']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                            ),
                        ])
                else
                  Column(children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.auto_graph)),
                      title: Text('Predicted: ${_money(predictedRevenue)}'),
                      subtitle: const Text('Average of the last three monthly collections.'),
                    ),
                    if (filteredForecastRows.isEmpty)
                      Text(monthlyCollections.isEmpty ? 'Monthly collection history is not available.' : 'No matching months.')
                    else
                      for (var i = 0; i < filteredForecastRows.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text('${filteredForecastRows[i]['month'] ?? 'Month'}'),
                          subtitle: const Text('Collected fees'),
                          trailing: Text(_money(filteredForecastRows[i]['collected']), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'AI Forecast',
            child: _insightsFailed && _insights == null
                ? const Text('Unable to load insights. Pull down to retry.')
                : !_insightsLoaded
                ? const Text('Forecast will appear when insights load.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(forecastTrend, color: forecastTrendColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Predicted: ${_money(predictedRevenue)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_insightChange != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Forecast ${_deltaDescription(forecastDelta)} since last update',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'At Risk: ${_money(totalAtRisk)}${riskDelta == null ? '' : ' / ${_deltaDescription(riskDelta)} since refresh'}',
                        style: TextStyle(
                          color: totalAtRisk > 0 ? AppColors.danger : AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Local rule-based forecast; updates every 30 seconds while the app is open.'),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          _sectionCard(
            title: 'Batch Profitability vs Attendance',
            child: _insightsFailed && _insights == null
                ? const Text(
                    'Unable to load batch analytics. Pull down to retry.',
                  )
                : _insightsLoaded
                ? _batchProfitabilityChart(batches)
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revenue period',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _revenuePeriod == 'month'
                        ? '${_revenueMonth.month}/${_revenueMonth.year}'
                        : _revenuePeriod == 'year'
                        ? '${_revenueMonth.year}'
                        : 'All collected revenue',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Current month'),
                        selected:
                            _revenuePeriod == 'month' &&
                            _revenueMonth.month == DateTime.now().month &&
                            _revenueMonth.year == DateTime.now().year,
                        onSelected: (_) =>
                            _loadRevenue('month', month: DateTime.now()),
                      ),
                      ChoiceChip(
                        label: const Text('Choose month'),
                        selected:
                            _revenuePeriod == 'month' &&
                            !(_revenueMonth.month == DateTime.now().month &&
                                _revenueMonth.year == DateTime.now().year),
                        onSelected: (_) async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _revenueMonth,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) _loadRevenue('month', month: d);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Yearly'),
                        selected: _revenuePeriod == 'year',
                        onSelected: (_) => _loadRevenue('year'),
                      ),
                      ChoiceChip(
                        label: const Text('Overall'),
                        selected: _revenuePeriod == 'overall',
                        onSelected: (_) => _loadRevenue('overall'),
                      ),
                    ],
                  ),
                  if (_revenueLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_revenueFailed && _revenue == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Revenue details are unavailable. Pull to retry.',
                      ),
                    ),
                  if (_revenue != null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text('Fees ${_money(_revenue!['fee_revenue'])}'),
                        Text(
                          'Products ${_money(_revenue!['product_revenue'])}',
                        ),
                        Text(
                          'Total ${_money(_revenue!['total_revenue'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PinnedSearchSection(
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  search: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Coaches Missing Attendance Today',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
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
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                        onChanged: (v) => setState(() => _missingSearch = v),
                      ),
                    ],
                  ),
                  results: Column(
                    children: [
                      if (!_missingLoaded)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_missingFailed && _missing.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Attendance alerts are unavailable. Pull to retry.',
                          ),
                        )
                      else if (_missing.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'All coaches have marked attendance for ended classes today.',
                          ),
                        )
                      else if (_visibleMissing.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No results found.'),
                        )
                      else
                        ..._visibleMissing.map(
                          (m) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(m['coach_name'] ?? '-'),
                            subtitle: Text(
                              '${m['activity_name'] ?? '-'} · ${m['date'] ?? ''} · ends ${m['end_time'] ?? ''}',
                            ),
                            leading: const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.warning,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                              ),
                              tooltip: 'Dismiss this alert',
                              onPressed: () =>
                                  _dismissMissing(m as Map<String, dynamic>),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    ],
  );
}

class _BatchMetricBars extends StatelessWidget {
  final Map<String, dynamic> row;
  final double maxProfit;
  final String Function(dynamic) money;

  const _BatchMetricBars({
    required this.row,
    required this.maxProfit,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final profit = (row['estimated_profit'] as num?)?.toDouble() ?? 0;
    final attendance = (row['attendance_pct'] as num?)?.toDouble() ?? 0;
    final profitProgress = maxProfit > 0
        ? (profit / maxProfit).clamp(0, 1)
        : 0.0;
    final attendanceProgress = (attendance / 100).clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${row['batch_name'] ?? 'Batch'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money(profit),
              style: const TextStyle(
                color: AppColors.brandOrange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: profitProgress.toDouble(),
            minHeight: 7,
            color: AppColors.brandOrange,
            backgroundColor: AppColors.brandLight,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Attendance',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            Text(
              '${attendance.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: attendanceProgress.toDouble(),
            minHeight: 5,
            color: AppColors.success,
            backgroundColor: const Color(0xFFE7F3EA),
          ),
        ),
      ],
    );
  }
}
