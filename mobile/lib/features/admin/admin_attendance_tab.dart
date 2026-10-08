import 'admin_reports_tab.dart';
import 'admin_pending_fees_pdf.dart';
import '../../core/export_helper.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api_client.dart';
import '../../core/admin_attendance_visibility_store.dart';
import '../../core/app_theme.dart';
import '../../core/dismissed_items.dart';
import '../../core/models.dart';
import '../../core/search_utils.dart';

const _missingAttendanceDismissKey = 'missing_attendance';
const _missingSectionStartKey = ValueKey<String>('missing-section-start');
const _missingSectionEndKey = ValueKey<String>('missing-section-end');
const _calendarStudentSectionStartKey =
    ValueKey<String>('calendar-student-section-start');
const _calendarStudentToolbarKey = ValueKey<String>('calendar-student-toolbar');
const _calendarStudentSectionEndKey =
    ValueKey<String>('calendar-student-section-end');
const _studentSectionStartKey = ValueKey<String>('student-section-start');
const _studentSectionHeadingKey = ValueKey<String>('student-section-heading');
const _studentSearchToolbarKey = ValueKey<String>('student-search-toolbar');
const _studentSectionEndKey = ValueKey<String>('student-section-end');
const _coachSectionStartKey = ValueKey<String>('coach-section-start');
const _coachSectionHeadingKey = ValueKey<String>('coach-section-heading');
const _coachSearchToolbarKey = ValueKey<String>('coach-search-toolbar');
const _coachSectionEndKey = ValueKey<String>('coach-section-end');
const _attendancePageSize = 500;
const _attendanceToolbarCollapsedHeight = 68.0;
const _studentAttendanceToolbarExpandedHeight = 294.0;
const _coachAttendanceToolbarExpandedHeight = 188.0;

class AdminAttendanceTab extends StatefulWidget {
  const AdminAttendanceTab({super.key});

  @override
  State<AdminAttendanceTab> createState() => _AdminAttendanceTabState();
}

class _AdminAttendanceTabState extends State<AdminAttendanceTab> {
  bool _loading = true;
  bool _recordsLoading = true;
  bool _recordsHasMore = false;
  bool _loadingMoreRecords = false;
  bool _showAllAttendanceRecords = true;
  bool _studentVisibilityChanged = false;
  final _attendanceVisibilityStore = AdminAttendanceVisibilityStore();
  late final Future<void> _attendanceVisibilityLoad;
  Future<void> _attendanceVisibilityLocalSaveQueue = Future<void>.value();
  Future<void> _attendanceVisibilitySaveQueue = Future<void>.value();
  List<DailyMissingRow> _missing = [];
  List<AdminAttendanceRecord> _records = [];
  List<Activity> _activities = [];
  List<Coach> _coaches = [];

  int? _filterActivityId;
  String? _filterStatus;
  String? _approvalFilter;
  String _attendanceSearch = '';
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  bool _studentFiltersExpanded = false;
  bool _coachFiltersExpanded = false;
  int? _removingId;
  int? _approvalBusyId;
  bool _approvingAll = false;
  Timer? _studentAttendanceSearchDebounce;
  Timer? _coachAttendanceSearchDebounce;
  int _studentRecordsRequestId = 0;
  int _coachRecordsRequestId = 0;

  DateTime _calendarMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _calendarSelectedDate = DateTime.now();
  bool _calendarLoading = true;
  List<AdminAttendanceRecord> _calendarRecords = [];
  List<Map<String, dynamic>> _calendarCoachRecords = [];
  String? _calendarStatusFilter;
  String? _calendarApprovalFilter;
  int? _calendarActivityFilter;
  bool _showCalendarStudentAttendance = true;

  DateTime get _calendarMonthStart =>
      DateTime(_calendarMonth.year, _calendarMonth.month, 1);
  DateTime get _calendarMonthEnd =>
      DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
  int get _calendarDaysInMonth => _calendarMonthEnd.day;
  int get _calendarLeadingBlanks => _calendarMonthStart.weekday % 7;

  String _calendarDateKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  Map<String, List<AdminAttendanceRecord>> get _calendarStudentsByDate {
    final result = <String, List<AdminAttendanceRecord>>{};
    for (final record in _calendarRecords) {
      result.putIfAbsent(record.classDate, () => []).add(record);
    }
    return result;
  }

  Map<String, List<Map<String, dynamic>>> get _calendarCoachesByDate {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final record in _calendarCoachRecords) {
      final date = (record['date'] as String?)?.substring(0, 10);
      if (date != null) result.putIfAbsent(date, () => []).add(record);
    }
    return result;
  }

  List<AdminAttendanceRecord> get _visibleRecords {
    return _records
        .where((r) =>
            matchesSearchQuery(
              [
                r.studentName,
                r.activityName,
                r.coachName,
                r.classDate,
                r.timestamp,
                r.status,
                r.approvalStatus,
                r.id,
                r.studentId,
                r.classId,
                r.activityId,
                r.coachId,
              ],
              _attendanceSearch,
            ) &&
            (_filterActivityId == null || r.activityId == _filterActivityId) &&
            (_filterStatus == null || r.status == _filterStatus) &&
            (_approvalFilter == null || r.approvalStatus == _approvalFilter) &&
            (_filterDateFrom == null ||
                r.classDate.compareTo(
                        _filterDateFrom!.toIso8601String().substring(0, 10)) >=
                    0) &&
            (_filterDateTo == null ||
                r.classDate.compareTo(
                        _filterDateTo!.toIso8601String().substring(0, 10)) <=
                    0))
        .toList();
  }

  // --- Coach attendance (separate CRUD) ---
  bool _coachRecordsLoading = true;
  bool _coachRecordsHasMore = false;
  bool _loadingMoreCoachRecords = false;
  bool _showCoachAttendanceRecords = true;
  bool _coachVisibilityChanged = false;
  List<Map<String, dynamic>> _coachRecords = [];
  int? _coachFilterId;
  String _coachSearch = '';
  String? _coachStatusFilter;
  DateTime? _coachFilterDateFrom;
  DateTime? _coachFilterDateTo;
  int? _removingCoachId;
  List<Map<String, dynamic>> get _visibleCoachRecords => _coachRecords
      .where((r) =>
          matchesSearchQuery(
            [
              r['coach_name'],
              r['coach_id'],
              r['date'],
              r['status'],
              r['entry_time'],
              r['exit_time'],
              r['id'],
            ],
            _coachSearch,
          ) &&
          (_coachStatusFilter == null || r['status'] == _coachStatusFilter) &&
          (_coachFilterId == null || r['coach_id'] == _coachFilterId))
      .toList();

  Future<void> _exportReport(String kind,
      {DateTime? date, bool includeDay = true}) async {
    final selected = date ?? DateTime.now();
    try {
      final query = <String, dynamic>{
        'month': selected.month,
        'year': selected.year,
        'kind': kind,
        'fmt': 'pdf'
      };
      if (date != null && includeDay) query['day'] = selected.day;
      final bytes = await ApiClient.instance.getBytes('/reports', query: query);
      await shareExportedFile(bytes,
          '${kind}_${selected.year}_${selected.month}${date == null || !includeDay ? '' : '_${selected.day}'}.pdf');
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _exportPendingFeesReport() async {
    try {
      await AdminPendingFeesPdf.exportForMonth(_calendarMonth);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create PDF: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _attendanceVisibilityLoad = _loadAttendanceListVisibility();
    _load();
    _loadRecords();
    _loadCoachRecords();
    _loadCalendarData();
  }

  @override
  void dispose() {
    _studentAttendanceSearchDebounce?.cancel();
    _coachAttendanceSearchDebounce?.cancel();
    super.dispose();
  }

  void _onStudentAttendanceSearchChanged(String value) {
    setState(() => _attendanceSearch = value);
    _studentAttendanceSearchDebounce?.cancel();
    _studentAttendanceSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      _loadRecords,
    );
  }

  void _onCoachAttendanceSearchChanged(String value) {
    setState(() => _coachSearch = value);
    _coachAttendanceSearchDebounce?.cancel();
    _coachAttendanceSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      _loadCoachRecords,
    );
  }

  int get _studentAttendanceActiveFilterCount => [
        _attendanceSearch.trim().isNotEmpty,
        _filterActivityId != null,
        _filterStatus != null,
        _approvalFilter != null,
        _filterDateFrom != null,
        _filterDateTo != null,
      ].where((active) => active).length;

  int get _coachAttendanceActiveFilterCount => [
        _coachSearch.trim().isNotEmpty,
        _coachFilterId != null,
        _coachStatusFilter != null,
        _coachFilterDateFrom != null,
        _coachFilterDateTo != null,
      ].where((active) => active).length;

  double get _studentAttendanceToolbarHeight => _studentFiltersExpanded
      ? _studentAttendanceToolbarExpandedHeight
      : _attendanceToolbarCollapsedHeight;

  double get _coachAttendanceToolbarHeight => _coachFiltersExpanded
      ? _coachAttendanceToolbarExpandedHeight
      : _attendanceToolbarCollapsedHeight;

  double get _calendarStudentToolbarHeight =>
      _showCalendarStudentAttendance ? 180 : 74;

  double get _coachAttendanceHeadingHeight {
    if (_showCoachAttendanceRecords) return 48;
    return MediaQuery.sizeOf(context).width < 384 ? 100 : 72;
  }

  String _activeFilterMessage(int count) => count == 0
      ? 'No active filters'
      : 'Clear $count active filter${count == 1 ? '' : 's'}';

  Widget _attendanceFilterDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            iconEnabledColor: theme.colorScheme.onSurfaceVariant,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 14,
            ),
            hint: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14)),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _attendanceDateFilter({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: theme.colorScheme.onSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text(
          value == null ? label : DateFormat('yyyy-MM-dd').format(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }

  Widget _attendanceSearchField({
    required String label,
    required String hint,
    required String query,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return TextField(
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Clear search',
                onPressed: () => onChanged(''),
                visualDensity: VisualDensity.compact,
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: onChanged,
    );
  }

  Widget _attendanceToolbarHeader({
    required String searchLabel,
    required String searchHint,
    required String query,
    required ValueChanged<String> onSearchChanged,
    required int activeFilterCount,
    required String filterGroupLabel,
    required bool filtersExpanded,
    required VoidCallback onToggleFilters,
    required Key filtersButtonKey,
    required Key visibilityButtonKey,
    required String visibilityTooltip,
    required VoidCallback onToggleVisibility,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactControls = constraints.maxWidth < 340;
        return SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: _attendanceSearchField(
                  label: searchLabel,
                  hint: searchHint,
                  query: query,
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 6),
              _attendanceFiltersToggle(
                compact: compactControls,
                count: activeFilterCount,
                groupLabel: filterGroupLabel,
                expanded: filtersExpanded,
                buttonKey: filtersButtonKey,
                onPressed: onToggleFilters,
              ),
              const SizedBox(width: 2),
              _attendanceVisibilityToggle(
                compact: compactControls,
                buttonKey: visibilityButtonKey,
                tooltip: visibilityTooltip,
                onPressed: onToggleVisibility,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attendanceSectionHeading({
    required String title,
    required IconData icon,
    Key? titleKey,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
    );

    Widget titleRow() => Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                key: titleKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            _attendanceTakenBadge(),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (trailing == null) return titleRow();
          if (constraints.maxWidth < 340) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleRow(),
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleRow()),
              const SizedBox(width: 8),
              trailing,
            ],
          );
        },
      ),
    );
  }

  Widget _attendanceTakenBadge() {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Attendance taken',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_outlined,
                size: 14, color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 4),
            Text(
              'Taken',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceDateBadge(DateTime date) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final label = DateUtils.isSameDay(date, now)
        ? 'Updated Today'
        : DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))
            ? 'Updated Yesterday'
            : 'Updated ${DateFormat('MMM d').format(date)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 13, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attendanceFiltersToggle({
    required bool compact,
    required int count,
    required String groupLabel,
    required bool expanded,
    required Key buttonKey,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final tooltip =
        '${expanded ? 'Hide' : 'Show'} $groupLabel filters. ${_activeFilterMessage(count)}';
    final filterIcon = Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.tune_rounded, size: 19),
        if (count > 0)
          Positioned(
            right: -10,
            top: -9,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );

    if (compact) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          key: buttonKey,
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.standard,
          icon: filterIcon,
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 44,
        child: OutlinedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            foregroundColor: expanded
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            side: BorderSide(
              color: expanded
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              filterIcon,
              const SizedBox(width: 6),
              Text(count == 0 ? 'Filters' : 'Filters ($count)'),
              const SizedBox(width: 2),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attendanceVisibilityToggle({
    required bool compact,
    required Key buttonKey,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    if (compact) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          key: buttonKey,
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.visibility_off_outlined, size: 20),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        icon: const Icon(Icons.visibility_off_outlined, size: 19),
        label: const Text('Hide'),
      ),
    );
  }

  Widget _attendanceClearFiltersButton({
    required bool compact,
    required Key buttonKey,
    required int activeFilterCount,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final enabled = activeFilterCount > 0;
    final icon = const Icon(Icons.filter_alt_off_outlined, size: 18);
    final tooltip = enabled
        ? _activeFilterMessage(activeFilterCount)
        : 'No filters to clear';

    if (compact) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          key: buttonKey,
          onPressed: enabled ? onPressed : null,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          icon: icon,
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: icon,
        label: const Text('Clear'),
      ),
    );
  }

  void _clearStudentAttendanceFilters() {
    _studentAttendanceSearchDebounce?.cancel();
    setState(() {
      _attendanceSearch = '';
      _filterActivityId = null;
      _filterStatus = null;
      _approvalFilter = null;
      _filterDateFrom = null;
      _filterDateTo = null;
    });
    _loadRecords();
  }

  void _clearCoachAttendanceFilters() {
    _coachAttendanceSearchDebounce?.cancel();
    setState(() {
      _coachSearch = '';
      _coachStatusFilter = null;
      _coachFilterId = null;
      _coachFilterDateFrom = null;
      _coachFilterDateTo = null;
    });
    _loadCoachRecords();
  }

  Widget _buildStudentAttendanceToolbar() {
    final pendingCount =
        _visibleRecords.where((r) => r.approvalStatus == 'PENDING').length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _attendanceToolbarHeader(
          searchLabel: 'Search attendance',
          searchHint: 'Student, activity, coach, date, or status',
          query: _attendanceSearch,
          onSearchChanged: _onStudentAttendanceSearchChanged,
          activeFilterCount: _studentAttendanceActiveFilterCount,
          filterGroupLabel: 'student attendance',
          filtersExpanded: _studentFiltersExpanded,
          onToggleFilters: () => setState(
            () => _studentFiltersExpanded = !_studentFiltersExpanded,
          ),
          filtersButtonKey: const ValueKey('toggle-student-attendance-filters'),
          visibilityButtonKey: const ValueKey('toggle-all-student-attendance'),
          visibilityTooltip: 'Hide all student attendance records',
          onToggleVisibility: _toggleStudentAttendanceRecords,
        ),
        if (_studentFiltersExpanded) ...[
          const SizedBox(height: 8),
          _attendanceFilterDropdown<int?>(
            label: 'All activities',
            value: _filterActivityId,
            items: [
              const DropdownMenuItem<int?>(
                  value: null, child: Text('All activities')),
              ..._activities.map((a) => DropdownMenuItem<int?>(
                  value: a.id,
                  child: Text(a.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (value) {
              setState(() => _filterActivityId = value);
              _loadRecords();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _attendanceFilterDropdown<String?>(
                  label: 'All statuses',
                  value: _filterStatus,
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('All statuses')),
                    DropdownMenuItem<String?>(
                        value: 'PRESENT', child: Text('Present')),
                    DropdownMenuItem<String?>(
                        value: 'ABSENT', child: Text('Absent')),
                    DropdownMenuItem<String?>(
                        value: 'LEAVE', child: Text('Leave')),
                    DropdownMenuItem<String?>(
                        value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterStatus = value);
                    _loadRecords();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _attendanceFilterDropdown<String?>(
                  label: 'All reviews',
                  value: _approvalFilter,
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('All reviews')),
                    DropdownMenuItem<String?>(
                        value: 'PENDING', child: Text('Pending')),
                    DropdownMenuItem<String?>(
                        value: 'APPROVED', child: Text('Approved')),
                    DropdownMenuItem<String?>(
                        value: 'REJECTED', child: Text('Rejected')),
                  ],
                  onChanged: (value) {
                    setState(() => _approvalFilter = value);
                    _loadRecords();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: _attendanceDateFilter(
                    label: 'From date',
                    value: _filterDateFrom,
                    onPressed: () => _pickFilterDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _attendanceDateFilter(
                    label: 'To date',
                    value: _filterDateTo,
                    onPressed: () => _pickFilterDate(false),
                  ),
                ),
                const SizedBox(width: 4),
                _attendanceClearFiltersButton(
                  compact: constraints.maxWidth < 340,
                  buttonKey: const ValueKey('clear-student-attendance-filters'),
                  activeFilterCount: _studentAttendanceActiveFilterCount,
                  onPressed: _clearStudentAttendanceFilters,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: pendingCount == 0 || _approvingAll || _recordsLoading
                  ? null
                  : _approveAllPending,
              icon: _approvingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.done_all_rounded, size: 19),
              label: Text(
                _approvingAll
                    ? 'Approving?'
                    : 'Approve filtered pending ($pendingCount)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCoachAttendanceToolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _attendanceToolbarHeader(
          searchLabel: 'Search coach attendance',
          searchHint: 'Coach or date',
          query: _coachSearch,
          onSearchChanged: _onCoachAttendanceSearchChanged,
          activeFilterCount: _coachAttendanceActiveFilterCount,
          filterGroupLabel: 'coach attendance',
          filtersExpanded: _coachFiltersExpanded,
          onToggleFilters: () => setState(
            () => _coachFiltersExpanded = !_coachFiltersExpanded,
          ),
          filtersButtonKey: const ValueKey('toggle-coach-attendance-filters'),
          visibilityButtonKey: const ValueKey('toggle-coach-attendance'),
          visibilityTooltip: 'Hide coach attendance records',
          onToggleVisibility: _toggleCoachAttendanceRecords,
        ),
        if (_coachFiltersExpanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _attendanceFilterDropdown<int?>(
                  label: 'All coaches',
                  value: _coachFilterId,
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('All coaches')),
                    ..._coaches.map((coach) => DropdownMenuItem<int?>(
                        value: coach.id,
                        child: Text(coach.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (value) {
                    setState(() => _coachFilterId = value);
                    _loadCoachRecords();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _attendanceFilterDropdown<String?>(
                  label: 'All statuses',
                  value: _coachStatusFilter,
                  items: const [
                    DropdownMenuItem<String?>(
                        value: null, child: Text('All statuses')),
                    DropdownMenuItem<String?>(
                        value: 'PRESENT', child: Text('Present')),
                    DropdownMenuItem<String?>(
                        value: 'ABSENT', child: Text('Absent')),
                    DropdownMenuItem<String?>(
                        value: 'LEAVE', child: Text('Leave')),
                    DropdownMenuItem<String?>(
                        value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                  ],
                  onChanged: (value) {
                    setState(() => _coachStatusFilter = value);
                    _loadCoachRecords();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: _attendanceDateFilter(
                    label: 'From date',
                    value: _coachFilterDateFrom,
                    onPressed: () => _pickCoachFilterDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _attendanceDateFilter(
                    label: 'To date',
                    value: _coachFilterDateTo,
                    onPressed: () => _pickCoachFilterDate(false),
                  ),
                ),
                const SizedBox(width: 4),
                _attendanceClearFiltersButton(
                  compact: constraints.maxWidth < 340,
                  buttonKey: const ValueKey('clear-coach-attendance-filters'),
                  activeFilterCount: _coachAttendanceActiveFilterCount,
                  onPressed: _clearCoachAttendanceFilters,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openManualEntryMenu() async {
    final addCoachAttendance = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Student attendance'),
              subtitle: const Text('Add or update a student class record'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Coach attendance'),
              subtitle: const Text('Add a coach facility attendance record'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || addCoachAttendance == null) return;
    if (addCoachAttendance) {
      await _openCoachManualEntry();
    } else {
      await _openManualEntry();
    }
  }

  Future<void> _loadAttendanceListVisibility() async {
    try {
      final visibility = await _attendanceVisibilityStore.load();
      if (!mounted) return;
      setState(() {
        if (!_studentVisibilityChanged) {
          _showAllAttendanceRecords = visibility.showStudentAttendanceRecords;
        }
        if (!_coachVisibilityChanged) {
          _showCoachAttendanceRecords = visibility.showCoachAttendanceRecords;
        }
      });
    } catch (_) {
      // Keep both lists available if local preferences cannot be read.
    }
  }

  void _toggleStudentAttendanceRecords() {
    final visible = !_showAllAttendanceRecords;
    setState(() {
      _studentVisibilityChanged = true;
      _showAllAttendanceRecords = visible;
    });
    _queueAttendanceVisibilitySave();
  }

  void _toggleCoachAttendanceRecords() {
    final visible = !_showCoachAttendanceRecords;
    setState(() {
      _coachVisibilityChanged = true;
      _showCoachAttendanceRecords = visible;
    });
    _queueAttendanceVisibilitySave();
  }

  void _queueAttendanceVisibilitySave() {
    final snapshot = AdminAttendanceListVisibility(
      showStudentAttendanceRecords: _showAllAttendanceRecords,
      showCoachAttendanceRecords: _showCoachAttendanceRecords,
    );
    _attendanceVisibilityLocalSaveQueue = _attendanceVisibilityLocalSaveQueue
        .then((_) => _attendanceVisibilityStore.cacheLocal(snapshot))
        .catchError((Object _) {});
    _attendanceVisibilitySaveQueue =
        _attendanceVisibilitySaveQueue.then((_) async {
      await _attendanceVisibilityLocalSaveQueue;
      await _attendanceVisibilityLoad;
      await _attendanceVisibilityStore.syncRemote(
        AdminAttendanceListVisibility(
          showStudentAttendanceRecords: _showAllAttendanceRecords,
          showCoachAttendanceRecords: _showCoachAttendanceRecords,
        ),
      );
    }).catchError((Object _) {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/attendance/daily-missing'),
        ApiClient.instance.get('/activities'),
        ApiClient.instance.get('/coaches'),
      ]);
      final rawMissing = (results[0] as List)
          .map((e) => DailyMissingRow.fromJson(e as Map<String, dynamic>))
          .toList();
      _missing = await DismissedItems.filter(
          _missingAttendanceDismissKey, rawMissing, (m) => m.classId);
      _activities = (results[1] as List)
          .map((e) => Activity.fromJson(e as Map<String, dynamic>))
          .toList();
      _coaches = (results[2] as List)
          .map((e) => Coach.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismissMissing(DailyMissingRow m) async {
    await DismissedItems.dismiss(_missingAttendanceDismissKey, m.classId);
    if (mounted)
      setState(() =>
          _missing = _missing.where((x) => x.classId != m.classId).toList());
  }

  Future<void> _loadRecords() async {
    _studentAttendanceSearchDebounce?.cancel();
    final requestId = ++_studentRecordsRequestId;
    setState(() {
      _recordsLoading = true;
      _loadingMoreRecords = false;
    });
    try {
      final data = await ApiClient.instance.get('/attendance/students',
          query: _studentRecordsQuery(offset: 0)) as List;
      if (!mounted || requestId != _studentRecordsRequestId) return;
      _records = data
          .map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _recordsHasMore = data.length == _attendancePageSize;
    } on ApiException catch (e) {
      if (mounted && requestId == _studentRecordsRequestId)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted && requestId == _studentRecordsRequestId) {
        setState(() => _recordsLoading = false);
      }
    }
  }

  Map<String, dynamic> _studentRecordsQuery({required int offset}) {
    final query = <String, dynamic>{
      'limit': _attendancePageSize,
      'offset': offset,
    };
    if (_filterActivityId != null) query['activity_id'] = _filterActivityId;
    if (_filterStatus != null) query['status_filter'] = _filterStatus;
    if (_approvalFilter != null) query['approval_status'] = _approvalFilter;
    if (_attendanceSearch.trim().isNotEmpty) {
      query['search'] = _attendanceSearch.trim();
    }
    if (_filterDateFrom != null) {
      query['date_from'] = _filterDateFrom!.toIso8601String().substring(0, 10);
    }
    if (_filterDateTo != null) {
      query['date_to'] = _filterDateTo!.toIso8601String().substring(0, 10);
    }
    return query;
  }

  Future<void> _loadMoreRecords() async {
    if (_loadingMoreRecords || !_recordsHasMore) return;
    final requestId = _studentRecordsRequestId;
    setState(() => _loadingMoreRecords = true);
    try {
      final data = await ApiClient.instance.get('/attendance/students',
          query: _studentRecordsQuery(offset: _records.length)) as List;
      if (!mounted || requestId != _studentRecordsRequestId) return;
      final knownIds = _records.map((record) => record.id).toSet();
      final next = data
          .map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .where((record) => knownIds.add(record.id));
      setState(() {
        _records.addAll(next);
        _recordsHasMore = data.length == _attendancePageSize;
      });
    } on ApiException catch (e) {
      if (mounted && requestId == _studentRecordsRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && requestId == _studentRecordsRequestId) {
        setState(() => _loadingMoreRecords = false);
      }
    }
  }

  Future<void> _refreshAll() async {
    await _load();
    await _loadRecords();
    await _loadCoachRecords();
    await _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    if (mounted) setState(() => _calendarLoading = true);
    final from = _calendarDateKey(_calendarMonthStart);
    final to = _calendarDateKey(_calendarMonthEnd);
    try {
      final results = await Future.wait([
        ApiClient.instance.getAllPages('/attendance/students', query: {
          'date_from': from,
          'date_to': to,
        }),
        ApiClient.instance.getAllPages('/attendance/coaches', query: {
          'date_from': from,
          'date_to': to,
        }),
      ]);
      _calendarRecords = results[0]
          .map((e) => AdminAttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      _calendarCoachRecords = results[1].cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  void _moveCalendarMonth(int offset) {
    setState(() {
      _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month + offset, 1);
      _calendarSelectedDate = null;
      _calendarStatusFilter = null;
      _calendarApprovalFilter = null;
      _calendarActivityFilter = null;
    });
    _loadCalendarData();
  }

  void _showCalendarToday() {
    final now = DateTime.now();
    setState(() {
      _calendarMonth = DateTime(now.year, now.month, 1);
      _calendarSelectedDate = now;
      _calendarStatusFilter = null;
      _calendarApprovalFilter = null;
      _calendarActivityFilter = null;
    });
    _loadCalendarData();
  }

  Color _calendarStatusColor(String status) {
    switch (status) {
      case 'PRESENT':
        return AppColors.success;
      case 'ABSENT':
        return AppColors.danger;
      case 'NOT_CONFIRM':
        return Colors.indigo;
      default:
        return AppColors.warning;
    }
  }

  Color _calendarApprovalColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _calendarTime(String? value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '-';
    final time = parsed.toLocal();
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $suffix';
  }

  Widget _calendarDot(Color color) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(right: 2, top: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _calendarDayCell(DateTime day) {
    final key = _calendarDateKey(day);
    final students = _calendarStudentsByDate[key] ?? const [];
    final coaches = _calendarCoachesByDate[key] ?? const [];
    final statuses = students.map((record) => record.status).toSet();
    final markerColors = <Color>[
      ...coaches
          .map((record) => record['status'] as String? ?? '')
          .where((status) => status.isNotEmpty)
          .toSet()
          .map(_calendarStatusColor),
      ...statuses.map(_calendarStatusColor),
    ].toSet().take(4);
    final isToday = _calendarDateKey(DateTime.now()) == key;
    final isSelected = _calendarSelectedDate != null &&
        _calendarDateKey(_calendarSelectedDate!) == key;
    return GestureDetector(
      onTap: () => setState(() => _calendarSelectedDate = day),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactCell =
              constraints.maxWidth < 36 || constraints.maxHeight < 36;
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandLight : AppColors.bg,
              border: Border.all(
                color: isToday || isSelected
                    ? AppColors.brandOrange
                    : AppColors.textMuted.withOpacity(0.25),
                width: isToday || isSelected ? 1.4 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: compactCell
                ? SizedBox.expand(
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            '${day.day}',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (markerColors.isNotEmpty)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: markerColors.first,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${day.day}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(children: markerColors.map(_calendarDot).toList()),
                      if (students.isNotEmpty || coaches.isNotEmpty)
                        Text(
                          students.length + coaches.length > 99
                              ? '99+'
                              : '${students.length + coaches.length}',
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.textMuted),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildAttendanceCalendar() {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _moveCalendarMonth(-1)),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(DateFormat('MMMM yyyy').format(_calendarMonth),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _showCalendarToday,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Today'),
                  ),
                ],
              ),
            ),
            IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _moveCalendarMonth(1)),
          ],
        ),
        if (_calendarLoading) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 0.9,
          children: [
            for (final weekday in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Center(
                child: Text(weekday,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted)),
              ),
            for (var i = 0; i < _calendarLeadingBlanks; i++)
              const SizedBox.shrink(),
            for (var day = 1; day <= _calendarDaysInMonth; day++)
              _calendarDayCell(
                  DateTime(_calendarMonth.year, _calendarMonth.month, day)),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarDetail() {
    final selected = _calendarSelectedDate;
    if (selected == null) {
      return const Text(
          'Select a day on the calendar to view coach and student attendance.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted));
    }
    final key = _calendarDateKey(selected);
    final students = _calendarStudentsByDate[key] ?? const [];
    final coaches = _calendarCoachesByDate[key] ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('EEEE, MMM d, yyyy').format(selected),
            style: Theme.of(context).textTheme.titleMedium),
        if (coaches.isNotEmpty) const SizedBox(height: 8),
        if (coaches.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.badge_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Coach Attendance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _attendanceDateBadge(selected)),
            ],
          ),
          const SizedBox(height: 6),
          ...coaches.map((record) {
            final status = record['status'] as String? ?? 'UNKNOWN';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(record['coach_name'] as String? ?? 'Unknown coach',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Chip(
                    label: Text(status,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white)),
                    backgroundColor: _calendarStatusColor(status),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                      'Entry ${_calendarTime(record['entry_time'] as String?)} · Exit ${_calendarTime(record['exit_time'] as String?)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            );
          }),
        ],
        if (students.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: coaches.isEmpty ? 6 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    coaches.isEmpty
                        ? 'No attendance recorded for this date.'
                        : 'No student attendance recorded for this date.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCalendarStudentToolbar() {
    final selected = _calendarSelectedDate;
    if (selected == null) return const SizedBox.shrink();
    final students =
        _calendarStudentsByDate[_calendarDateKey(selected)] ?? const [];
    final theme = Theme.of(context);
    final hasActiveFilters = _calendarStatusFilter != null ||
        _calendarApprovalFilter != null ||
        _calendarActivityFilter != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 2, color: theme.colorScheme.primary),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Icon(Icons.groups_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Student Attendance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: _attendanceDateBadge(selected)),
                  TextButton.icon(
                    key: const ValueKey('toggle-calendar-student-attendance'),
                    onPressed: () => setState(() =>
                        _showCalendarStudentAttendance =
                            !_showCalendarStudentAttendance),
                    icon: Icon(
                      _showCalendarStudentAttendance
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label:
                        Text(_showCalendarStudentAttendance ? 'Hide' : 'Show'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            if (_showCalendarStudentAttendance) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _attendanceFilterDropdown<String?>(
                      label: 'All statuses',
                      value: _calendarStatusFilter,
                      items: const [
                        DropdownMenuItem<String?>(
                            value: null, child: Text('All statuses')),
                        DropdownMenuItem<String?>(
                            value: 'PRESENT', child: Text('Present')),
                        DropdownMenuItem<String?>(
                            value: 'ABSENT', child: Text('Absent')),
                        DropdownMenuItem<String?>(
                            value: 'LEAVE', child: Text('Leave')),
                        DropdownMenuItem<String?>(
                            value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                      ],
                      onChanged: (value) =>
                          setState(() => _calendarStatusFilter = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _attendanceFilterDropdown<String?>(
                      label: 'All reviews',
                      value: _calendarApprovalFilter,
                      items: const [
                        DropdownMenuItem<String?>(
                            value: null, child: Text('All reviews')),
                        DropdownMenuItem<String?>(
                            value: 'PENDING', child: Text('Pending')),
                        DropdownMenuItem<String?>(
                            value: 'APPROVED', child: Text('Approved')),
                        DropdownMenuItem<String?>(
                            value: 'REJECTED', child: Text('Rejected')),
                      ],
                      onChanged: (value) =>
                          setState(() => _calendarApprovalFilter = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _attendanceFilterDropdown<int?>(
                      label: 'All activities',
                      value: _calendarActivityFilter,
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('All activities')),
                        ...{
                          for (final record in students)
                            record.activityId: record.activityName
                        }.entries.map((entry) => DropdownMenuItem<int?>(
                            value: entry.key, child: Text(entry.value))),
                      ],
                      onChanged: (value) =>
                          setState(() => _calendarActivityFilter = value),
                    ),
                  ),
                  if (hasActiveFilters)
                    TextButton(
                      onPressed: () => setState(() {
                        _calendarStatusFilter = null;
                        _calendarApprovalFilter = null;
                        _calendarActivityFilter = null;
                      }),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCalendarStudentRows() {
    final selected = _calendarSelectedDate;
    if (selected == null || !_showCalendarStudentAttendance) return const [];
    final key = _calendarDateKey(selected);
    final students = _calendarStudentsByDate[key] ?? const [];
    final visibleStudents = students.where((record) {
      return (_calendarStatusFilter == null ||
              record.status == _calendarStatusFilter) &&
          (_calendarApprovalFilter == null ||
              record.approvalStatus == _calendarApprovalFilter) &&
          (_calendarActivityFilter == null ||
              record.activityId == _calendarActivityFilter);
    }).toList();

    if (students.isEmpty) return const [];
    if (visibleStudents.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
          child: Text(
            'No student attendance matches these filters.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ];
    }

    return visibleStudents
        .map((record) => Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(record.studentName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          children: [
                            Chip(
                              label: Text(record.status,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white)),
                              backgroundColor:
                                  _calendarStatusColor(record.status),
                              visualDensity: VisualDensity.compact,
                            ),
                            Chip(
                              label: Text(
                                  record.approvalStatus == 'PENDING'
                                      ? 'Awaiting Admin'
                                      : record.approvalStatus,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white)),
                              backgroundColor:
                                  _calendarApprovalColor(record.approvalStatus),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Text(record.activityName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  if (record.hasSelfie) ...[
                    const SizedBox(height: 6),
                    OutlinedButton(
                        onPressed: () => _viewSelfie(record),
                        child: const Text('View Photo')),
                  ],
                ],
              ),
            ))
        .toList();
  }

  Future<void> _openManualEntry() async {
    final marked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ManualEntryForm(),
    );
    if (marked == true) _refreshAll();
  }

  Future<void> _loadCoachRecords() async {
    _coachAttendanceSearchDebounce?.cancel();
    final requestId = ++_coachRecordsRequestId;
    setState(() {
      _coachRecordsLoading = true;
      _loadingMoreCoachRecords = false;
    });
    try {
      final data = await ApiClient.instance.get('/attendance/coaches',
          query: _coachRecordsQuery(offset: 0)) as List;
      if (!mounted || requestId != _coachRecordsRequestId) return;
      _coachRecords = data.cast<Map<String, dynamic>>();
      _coachRecordsHasMore = data.length == _attendancePageSize;
    } on ApiException catch (e) {
      if (mounted && requestId == _coachRecordsRequestId)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted && requestId == _coachRecordsRequestId) {
        setState(() => _coachRecordsLoading = false);
      }
    }
  }

  Map<String, dynamic> _coachRecordsQuery({required int offset}) {
    final query = <String, dynamic>{
      'limit': _attendancePageSize,
      'offset': offset,
    };
    if (_coachFilterId != null) query['coach_id'] = _coachFilterId;
    if (_coachStatusFilter != null) {
      query['status_filter'] = _coachStatusFilter;
    }
    if (_coachSearch.trim().isNotEmpty) query['search'] = _coachSearch.trim();
    if (_coachFilterDateFrom != null) {
      query['date_from'] =
          _coachFilterDateFrom!.toIso8601String().substring(0, 10);
    }
    if (_coachFilterDateTo != null) {
      query['date_to'] = _coachFilterDateTo!.toIso8601String().substring(0, 10);
    }
    return query;
  }

  Future<void> _loadMoreCoachRecords() async {
    if (_loadingMoreCoachRecords || !_coachRecordsHasMore) return;
    final requestId = _coachRecordsRequestId;
    setState(() => _loadingMoreCoachRecords = true);
    try {
      final data = await ApiClient.instance.get('/attendance/coaches',
          query: _coachRecordsQuery(offset: _coachRecords.length)) as List;
      if (!mounted || requestId != _coachRecordsRequestId) return;
      final knownIds = _coachRecords.map((record) => record['id']).toSet();
      final next = data
          .cast<Map<String, dynamic>>()
          .where((record) => knownIds.add(record['id']));
      setState(() {
        _coachRecords.addAll(next);
        _coachRecordsHasMore = data.length == _attendancePageSize;
      });
    } on ApiException catch (e) {
      if (mounted && requestId == _coachRecordsRequestId) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && requestId == _coachRecordsRequestId) {
        setState(() => _loadingMoreCoachRecords = false);
      }
    }
  }

  Future<void> _pickCoachFilterDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _coachFilterDateFrom : _coachFilterDateTo) ??
          DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() =>
        isFrom ? _coachFilterDateFrom = picked : _coachFilterDateTo = picked);
    _loadCoachRecords();
  }

  Future<void> _openCoachManualEntry() async {
    final marked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CoachManualEntryForm(coaches: _coaches),
    );
    if (marked == true) _loadCoachRecords();
  }

  Future<void> _openEditCoachRecord(Map<String, dynamic> r) async {
    String status = r['status'] as String? ?? 'PRESENT';
    final entryCtrl = TextEditingController(
        text: r['entry_time'] != null
            ? (r['entry_time'] as String).substring(11, 16)
            : '');
    final exitCtrl = TextEditingController(
        text: r['exit_time'] != null
            ? (r['exit_time'] as String).substring(11, 16)
            : '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Coach Attendance — ${r['coach_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: entryCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Entry time (HH:MM)')),
              TextField(
                  controller: exitCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Exit time (HH:MM)')),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                  DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                  DropdownMenuItem(
                      value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                  DropdownMenuItem(
                      value: 'INCOMPLETE', child: Text('Incomplete')),
                ],
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await ApiClient.instance
                      .put('/attendance/coaches/${r['id']}', body: {
                    if (entryCtrl.text.trim().isNotEmpty)
                      'entry_time': '${entryCtrl.text.trim()}:00',
                    if (exitCtrl.text.trim().isNotEmpty)
                      'exit_time': '${exitCtrl.text.trim()}:00',
                    'status': status,
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    entryCtrl.dispose();
    exitCtrl.dispose();
    if (saved == true) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coach attendance updated')));
      _loadCoachRecords();
    }
  }

  Future<void> _removeCoachRecord(Map<String, dynamic> r) async {
    final id = r['id'] as int;
    if (_removingCoachId == id) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete coach attendance record?'),
        content: Text(
            'Delete this attendance record for ${r['coach_name']} on ${r['date']}?'),
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
    setState(() => _removingCoachId = id);
    try {
      await ApiClient.instance.delete('/attendance/coaches/$id');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Coach attendance record deleted')));
      _loadCoachRecords();
    } on ApiException catch (e) {
      if (mounted) {
        final message = e.statusCode == 404
            ? 'Already deleted — refreshing list'
            : e.message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _loadCoachRecords();
      }
    } finally {
      if (mounted) setState(() => _removingCoachId = null);
    }
  }

  Future<void> _openEditRecord(AdminAttendanceRecord r) async {
    String status = r.status;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Attendance — ${r.studentName}'),
          content: DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
              DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
              DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
              DropdownMenuItem(
                  value: 'NOT_CONFIRM', child: Text('Not Confirm')),
            ],
            onChanged: (v) => setDialogState(() => status = v ?? status),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                try {
                  await ApiClient.instance.put('/attendance/students/${r.id}',
                      body: {'status': status});
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted)
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Attendance updated')));
      _refreshAll();
    }
  }

  Future<void> _removeRecord(AdminAttendanceRecord r) async {
    if (_removingId == r.id) return; // already in flight — ignore a double tap
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete attendance record?'),
        content: Text('Delete this attendance record for ${r.studentName}?'),
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
    setState(() => _removingId = r.id);
    try {
      await ApiClient.instance.delete('/attendance/students/${r.id}');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attendance record deleted')));
      _refreshAll();
    } on ApiException catch (e) {
      if (mounted) {
        // A 404 here means the record is already gone (deleted from another
        // session/device, or a duplicate tap raced this same request) — the
        // end state the admin wanted is already true, so refresh instead of
        // leaving a stale row on screen with a confusing permanent error.
        final message = e.statusCode == 404
            ? 'Already deleted — refreshing list'
            : e.message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        if (e.statusCode == 404) _refreshAll();
      }
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  Future<String?> _promptReason(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            maxLines: 2),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Confirm')),
        ],
      ),
    ).then((value) {
      ctrl.dispose();
      return value;
    });
  }

  Future<void> _decideApproval(AdminAttendanceRecord r, bool approve) async {
    setState(() => _approvalBusyId = r.id);
    try {
      if (approve) {
        await ApiClient.instance
            .put('/attendance/students/${r.id}/approve', body: {'note': null});
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attendance approved and locked')));
      } else {
        final note = await _promptReason('Reason for rejecting');
        if (note == null) {
          setState(() => _approvalBusyId = null);
          return; // cancelled the dialog
        }
        await ApiClient.instance.put('/attendance/students/${r.id}/reject',
            body: {'note': note.isEmpty ? null : note});
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attendance rejected and locked')));
      }
      _loadRecords();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _approvalBusyId = null);
    }
  }

  Future<void> _approveAllPending() async {
    if (_approvingAll) return;
    final pending =
        _visibleRecords.where((r) => r.approvalStatus == 'PENDING').toList();
    if (pending.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve all pending attendance?'),
        content: Text(
            'Approve ${pending.length} pending record(s) matching the current filters?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve all')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _approvingAll = true);
    var approved = 0;
    var failed = 0;
    for (final record in pending) {
      try {
        await ApiClient.instance.put(
            '/attendance/students/${record.id}/approve',
            body: {'note': null});
        approved++;
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _approvingAll = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Approved $approved attendance record(s)'
          : 'Approved $approved; $failed could not be approved. Refresh and review them.'),
    ));
    await _loadRecords();
  }

  Color _approvalColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _viewSelfie(AdminAttendanceRecord r) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Selfie — ${r.studentName}'),
        content: SizedBox(
          width: 280,
          height: 280,
          child: FutureBuilder<Uint8List>(
            future: ApiClient.instance
                .getBytes('/attendance/selfie/${r.id}')
                .then((b) => Uint8List.fromList(b)),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(child: Text('Selfie not available.'));
              }
              return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain));
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close'))
        ],
      ),
    );
  }

  Future<void> _pickFilterDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _filterDateFrom : _filterDateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _filterDateFrom = picked : _filterDateTo = picked);
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-attendance-fab',
        onPressed: _openManualEntryMenu,
        icon: const Icon(Icons.edit_calendar_outlined),
        label: const Text('Manual Entry'),
      ),
      body: _loading &&
              _records.isEmpty &&
              _coachRecords.isEmpty &&
              _missing.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final selectedDate = _calendarSelectedDate;
              final selectedDateStudents = selectedDate == null
                  ? const <AdminAttendanceRecord>[]
                  : _calendarStudentsByDate[_calendarDateKey(selectedDate)] ??
                      const [];
              final children = <Widget>[
                FutureBuilder<dynamic>(
                    future: ApiClient.instance.get('/reports', query: {
                      'month': DateTime.now().month,
                      'year': DateTime.now().year
                    }),
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return const Text('Revenue could not be loaded');
                      if (!snapshot.hasData)
                        return const Text('Loading overall revenue...');
                      return Text(
                          'Overall revenue this month: Rs ${snapshot.data['total_revenue']} (products included)',
                          style: const TextStyle(fontWeight: FontWeight.bold));
                    }),
                ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Overall Revenue & Attendance Reports"),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => Scaffold(
                                appBar: AppBar(title: const Text("Reports")),
                                body: const AdminReportsTab())))),
                Wrap(spacing: 8, children: [
                  OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _calendarSelectedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (picked != null)
                          _exportReport('classes_detail', date: picked);
                      },
                      child: const Text('Choose Day Classes PDF')),
                  OutlinedButton(
                      onPressed: () => _exportReport('students_summary',
                          date: _calendarMonth, includeDay: false),
                      child: const Text('Monthly Attendance & Classes PDF')),
                  OutlinedButton(
                      onPressed: () => _exportReport('fees_paid'),
                      child: const Text('Fees Paid PDF')),
                  OutlinedButton(
                      onPressed: _exportPendingFeesReport,
                      child: const Text('Fees Pending PDF')),
                ]),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text('Attendance Calendar',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                Card(
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _buildAttendanceCalendar()),
                ),
                Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildCalendarDetail()),
                ),
                KeyedSubtree(
                    key: _calendarStudentSectionStartKey,
                    child: const SizedBox.shrink()),
                if (selectedDateStudents.isNotEmpty) ...[
                  KeyedSubtree(
                    key: _calendarStudentToolbarKey,
                    child: _buildCalendarStudentToolbar(),
                  ),
                  if (_showCalendarStudentAttendance)
                    ..._buildCalendarStudentRows(),
                ],
                KeyedSubtree(
                    key: _calendarStudentSectionEndKey,
                    child: const SizedBox.shrink()),
                KeyedSubtree(
                    key: _missingSectionStartKey,
                    child: const SizedBox.shrink()),
                if (_missing.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Text('Coaches Missing Attendance Today',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  ..._missing.map((m) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber_rounded,
                              color: AppColors.warning),
                          title: Text(m.coachName),
                          subtitle: Text(
                              '${m.activityName} · ${m.date} · ends ${m.endTime}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger),
                            tooltip: 'Dismiss this alert',
                            onPressed: () => _dismissMissing(m),
                          ),
                        ),
                      )),
                ],
                KeyedSubtree(
                    key: _missingSectionEndKey, child: const SizedBox.shrink()),
                KeyedSubtree(
                    key: _studentSectionStartKey,
                    child: const SizedBox.shrink()),
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: _studentSectionHeadingKey,
                  child: _attendanceSectionHeading(
                    title: 'Student Attendance',
                    icon: Icons.groups_outlined,
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'All Attendance Records',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!_showAllAttendanceRecords && !_recordsLoading)
                          Tooltip(
                            message:
                                '${_visibleRecords.length} matching student attendance records',
                            child: Chip(
                              label: Text('${_visibleRecords.length}'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        if (!_showAllAttendanceRecords)
                          Tooltip(
                            message: 'Show all student attendance records',
                            child: TextButton.icon(
                              key: const ValueKey(
                                  'toggle-all-student-attendance'),
                              onPressed: _toggleStudentAttendanceRecords,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Show'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_showAllAttendanceRecords) ...[
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: _studentSearchToolbarKey,
                    child: _buildStudentAttendanceToolbar(),
                  ),
                  const SizedBox(height: 12),
                  if (_recordsLoading && _records.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator())),
                  if (_recordsLoading && _records.isNotEmpty)
                    const LinearProgressIndicator(),
                  if (!_recordsLoading && _records.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: Text('No attendance records found.'))),
                  if (!_recordsLoading &&
                      _records.isNotEmpty &&
                      _visibleRecords.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No results found.'))),
                  if (_visibleRecords.isNotEmpty)
                    ..._visibleRecords.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      r.studentName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Chip(
                                      label: Text(r.status,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white)),
                                      backgroundColor: r.status == 'PRESENT'
                                          ? AppColors.success
                                          : r.status == 'ABSENT'
                                              ? AppColors.danger
                                              : AppColors.warning,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                    ),
                                    Chip(
                                      label: Text(r.approvalStatus,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white)),
                                      backgroundColor:
                                          _approvalColor(r.approvalStatus),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${r.classDate} · ${r.activityName} · ${r.coachName ?? "-"} · ${r.markedManually ? "Manual" : "Coach"}',
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (r.hasSelfie)
                                      IconButton(
                                          icon: const Icon(
                                              Icons.photo_camera_outlined,
                                              size: 20),
                                          tooltip: 'View Selfie',
                                          onPressed: () => _viewSelfie(r)),
                                    if (r.approvalStatus == 'PENDING')
                                      _approvalBusyId == r.id
                                          ? const Padding(
                                              padding: EdgeInsets.all(10),
                                              child: SizedBox(
                                                  height: 16,
                                                  width: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons
                                                          .check_circle_outline,
                                                      size: 20,
                                                      color: AppColors.success),
                                                  tooltip: 'Approve',
                                                  onPressed: () =>
                                                      _decideApproval(r, true),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 20,
                                                      color: AppColors.danger),
                                                  tooltip: 'Reject',
                                                  onPressed: () =>
                                                      _decideApproval(r, false),
                                                ),
                                              ],
                                            ),
                                    IconButton(
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 20),
                                        onPressed: () => _openEditRecord(r)),
                                    _removingId == r.id
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: SizedBox(
                                                height: 16,
                                                width: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)))
                                        : IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 20,
                                                color: AppColors.danger),
                                            onPressed: () => _removeRecord(r)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                  if (_recordsHasMore)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed:
                            _loadingMoreRecords ? null : _loadMoreRecords,
                        icon: _loadingMoreRecords
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(_loadingMoreRecords
                            ? 'Loading older records…'
                            : 'Load older student records'),
                      ),
                    ),
                ],
                KeyedSubtree(
                    key: _studentSectionEndKey, child: const SizedBox.shrink()),
                KeyedSubtree(
                    key: _coachSectionStartKey, child: const SizedBox.shrink()),
                const SizedBox(height: 20),
                KeyedSubtree(
                  key: _coachSectionHeadingKey,
                  child: _attendanceSectionHeading(
                    title: 'Coach Attendance',
                    titleKey: const ValueKey('coach-attendance-section'),
                    icon: Icons.badge_outlined,
                    trailing: !_showCoachAttendanceRecords
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_coachRecordsLoading) ...[
                                Chip(
                                  label: Text('${_visibleCoachRecords.length}'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Tooltip(
                                message: 'Show coach attendance records',
                                child: TextButton.icon(
                                  key:
                                      const ValueKey('toggle-coach-attendance'),
                                  onPressed: _toggleCoachAttendanceRecords,
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: const Text('Show'),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
                if (_showCoachAttendanceRecords) ...[
                  const SizedBox(height: 8),
                  KeyedSubtree(
                    key: _coachSearchToolbarKey,
                    child: _buildCoachAttendanceToolbar(),
                  ),
                  const SizedBox(height: 12),
                  if (_coachRecordsLoading && _coachRecords.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator())),
                  if (_coachRecordsLoading && _coachRecords.isNotEmpty)
                    const LinearProgressIndicator(),
                  if (!_coachRecordsLoading && _coachRecords.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: Text(
                                'No coach attendance records match these filters.'))),
                  if (!_coachRecordsLoading &&
                      _coachRecords.isNotEmpty &&
                      _visibleCoachRecords.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No results found.'))),
                  if (_visibleCoachRecords.isNotEmpty)
                    ..._visibleCoachRecords.map((r) {
                      final id = r['id'] as int;
                      final status = r['status'] as String? ?? 'PRESENT';
                      final entry = r['entry_time'] != null
                          ? (r['entry_time'] as String).substring(11, 16)
                          : '-';
                      final exit = r['exit_time'] != null
                          ? (r['exit_time'] as String).substring(11, 16)
                          : '-';
                      final statusColor = status == 'PRESENT'
                          ? AppColors.success
                          : status == 'ABSENT'
                              ? AppColors.danger
                              : AppColors.warning;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r['coach_name'] as String? ?? '-',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(status,
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.white)),
                                    backgroundColor: statusColor,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${r['date']} · Entry $entry · Exit $exit',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit coach attendance',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onPressed: () => _openEditCoachRecord(r),
                                  ),
                                  _removingCoachId == id
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : IconButton(
                                          tooltip: 'Delete coach attendance',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: AppColors.danger,
                                          ),
                                          onPressed: () =>
                                              _removeCoachRecord(r),
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  if (_coachRecordsHasMore)
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _loadingMoreCoachRecords
                            ? null
                            : _loadMoreCoachRecords,
                        icon: _loadingMoreCoachRecords
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.expand_more),
                        label: Text(_loadingMoreCoachRecords
                            ? 'Loading older records…'
                            : 'Load older coach records'),
                      ),
                    ),
                ],
                KeyedSubtree(
                    key: _coachSectionEndKey, child: const SizedBox.shrink()),
              ];

              int childIndex(Key key) =>
                  children.indexWhere((child) => child.key == key);

              Widget paddedList(List<Widget> items, {double top = 0}) {
                if (items.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(12, top, 12, 0),
                  sliver: SliverList(delegate: SliverChildListDelegate(items)),
                );
              }

              Widget sectionSliver({
                required Key startKey,
                required Key? headingKey,
                required double headingHeight,
                required Key? searchKey,
                required Key endKey,
                required double toolbarHeight,
                bool reserveStickyExitSpace = true,
              }) {
                final start = childIndex(startKey);
                final end = childIndex(endKey);
                if (start < 0 || end <= start) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                final sectionChildren = children.sublist(start + 1, end);
                final stickyHeaders = <MapEntry<int, double>>[
                  if (headingKey != null)
                    MapEntry(
                        sectionChildren
                            .indexWhere((child) => child.key == headingKey),
                        headingHeight),
                  if (searchKey != null)
                    MapEntry(
                        sectionChildren
                            .indexWhere((child) => child.key == searchKey),
                        toolbarHeight),
                ].where((header) => header.key >= 0).toList()
                  ..sort((a, b) => a.key.compareTo(b.key));
                if (stickyHeaders.isEmpty) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList(
                        delegate: SliverChildListDelegate(sectionChildren)),
                  );
                }

                final sectionSlivers = <Widget>[];
                var nextIndex = 0;
                var stickyHeight = 0.0;
                for (final header in stickyHeaders) {
                  if (header.key < nextIndex) continue;
                  final beforeHeader =
                      sectionChildren.sublist(nextIndex, header.key);
                  if (beforeHeader.isNotEmpty) {
                    sectionSlivers.add(paddedList(beforeHeader));
                  }
                  sectionSlivers.add(SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyAttendanceToolbarDelegate(
                      height: header.value,
                      child: sectionChildren[header.key],
                    ),
                  ));
                  stickyHeight += header.value;
                  nextIndex = header.key + 1;
                }
                if (nextIndex < sectionChildren.length) {
                  sectionSlivers
                      .add(paddedList(sectionChildren.sublist(nextIndex)));
                }
                // Give a pinned header enough trailing scroll extent to leave
                // the viewport cleanly at the section boundary.
                if (reserveStickyExitSpace) {
                  sectionSlivers.add(
                    SliverToBoxAdapter(
                      child: SizedBox(height: stickyHeight),
                    ),
                  );
                }
                return SliverMainAxisGroup(slivers: sectionSlivers);
              }

              final calendarStudentStart =
                  childIndex(_calendarStudentSectionStartKey);
              final slivers = <Widget>[
                if (calendarStudentStart > 0)
                  paddedList(children.sublist(0, calendarStudentStart),
                      top: 12),
                sectionSliver(
                  startKey: _calendarStudentSectionStartKey,
                  headingKey: _calendarStudentToolbarKey,
                  headingHeight: _calendarStudentToolbarHeight,
                  searchKey: null,
                  endKey: _calendarStudentSectionEndKey,
                  toolbarHeight: 0,
                  reserveStickyExitSpace: false,
                ),
                sectionSliver(
                  startKey: _missingSectionStartKey,
                  headingKey: null,
                  headingHeight: 0,
                  searchKey: null,
                  endKey: _missingSectionEndKey,
                  toolbarHeight: 0,
                ),
                sectionSliver(
                  startKey: _studentSectionStartKey,
                  headingKey: _studentSectionHeadingKey,
                  headingHeight: 44,
                  searchKey: _studentSearchToolbarKey,
                  endKey: _studentSectionEndKey,
                  toolbarHeight: _studentAttendanceToolbarHeight,
                ),
                sectionSliver(
                  startKey: _coachSectionStartKey,
                  headingKey: _coachSectionHeadingKey,
                  headingHeight: _coachAttendanceHeadingHeight,
                  searchKey: _coachSearchToolbarKey,
                  endKey: _coachSectionEndKey,
                  toolbarHeight: _coachAttendanceToolbarHeight,
                ),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: 90),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ];

              return RefreshIndicator(
                onRefresh: _refreshAll,
                child: CustomScrollView(slivers: slivers),
              );
            }),
    );
  }
}

class _StickyAttendanceToolbarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyAttendanceToolbarDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return SizedBox.expand(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: overlapsContent ? 2 : 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom:
                  BorderSide(color: theme.dividerColor.withValues(alpha: .3)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyAttendanceToolbarDelegate oldDelegate) =>
      height != oldDelegate.height || child != oldDelegate.child;
}

class _ManualEntryForm extends StatefulWidget {
  const _ManualEntryForm();

  @override
  State<_ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends State<_ManualEntryForm> {
  List<Activity> _activities = [];
  List<ClassSession> _classes = [];
  List<RosterStudent> _roster = [];
  int? _activityId;
  int? _classId;
  int? _studentId;
  String _status = 'PRESENT';
  bool _loadingActivities = true;
  bool _loadingDetail = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final data = await ApiClient.instance.get('/activities') as List;
      _activities = data
          .map((e) => Activity.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  Future<void> _onActivityChanged(int? id) async {
    setState(() {
      _activityId = id;
      _classId = null;
      _studentId = null;
      _classes = [];
      _roster = [];
      _loadingDetail = id != null;
    });
    if (id == null) return;
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/activities/$id/classes'),
        ApiClient.instance.get('/activities/$id/roster'),
      ]);
      _classes = (results[0] as List)
          .map((e) => ClassSession.fromJson(e as Map<String, dynamic>))
          .toList();
      _roster = (results[1] as List)
          .map((e) => RosterStudent.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _submit() async {
    if (_classId == null || _studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select an activity, class, and student')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/attendance/mark-student/manual', body: {
        'student_id': _studentId,
        'class_id': _classId,
        'status': _status,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            Text('Manual Attendance Entry',
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Bypasses geofence and selfie requirements.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            _loadingActivities
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
                    initialValue: _activityId,
                    decoration: const InputDecoration(labelText: 'Activity'),
                    items: _activities
                        .map((a) =>
                            DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: _onActivityChanged,
                  ),
            const SizedBox(height: 12),
            if (_loadingDetail)
              const Center(child: CircularProgressIndicator()),
            if (!_loadingDetail && _activityId != null) ...[
              DropdownButtonFormField<int>(
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes
                    .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.date} (${c.startTime}-${c.endTime})')))
                    .toList(),
                onChanged: (v) => setState(() => _classId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _studentId,
                decoration: const InputDecoration(labelText: 'Student'),
                items: _roster
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => setState(() => _studentId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                  DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                  DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                  DropdownMenuItem(
                      value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachManualEntryForm extends StatefulWidget {
  final List<Coach> coaches;
  const _CoachManualEntryForm({required this.coaches});

  @override
  State<_CoachManualEntryForm> createState() => _CoachManualEntryFormState();
}

class _CoachManualEntryFormState extends State<_CoachManualEntryForm> {
  int? _coachId;
  DateTime _date = DateTime.now();
  TimeOfDay? _entryTime;
  TimeOfDay? _exitTime;
  String _status = 'PRESENT';
  bool _submitting = false;

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_coachId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a coach')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/attendance/coaches/manual', body: {
        'coach_id': _coachId,
        'date': _date.toIso8601String().substring(0, 10),
        if (_entryTime != null) 'entry_time': _fmtTime(_entryTime!),
        if (_exitTime != null) 'exit_time': _fmtTime(_exitTime!),
        'status': _status,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            Text('Manual Coach Attendance Entry',
                style: Theme.of(context).textTheme.titleLarge),
            const Text(
                'Bypasses geofencing — for correcting or backfilling records.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
              items: widget.coaches
                  .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _coachId = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(_date.toIso8601String().substring(0, 10)),
              onTap: () async {
                final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (picked != null) setState(() => _date = picked);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entry Time'),
                    subtitle: Text(_entryTime?.format(context) ?? '-'),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context,
                          initialTime: _entryTime ?? TimeOfDay.now());
                      if (picked != null) setState(() => _entryTime = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exit Time'),
                    subtitle: Text(_exitTime?.format(context) ?? '-'),
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context,
                          initialTime: _exitTime ?? TimeOfDay.now());
                      if (picked != null) setState(() => _exitTime = picked);
                    },
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'PRESENT', child: Text('Present')),
                DropdownMenuItem(value: 'ABSENT', child: Text('Absent')),
                DropdownMenuItem(value: 'LEAVE', child: Text('Leave')),
                DropdownMenuItem(
                    value: 'NOT_CONFIRM', child: Text('Not Confirm')),
                DropdownMenuItem(
                    value: 'INCOMPLETE', child: Text('Incomplete')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'PRESENT'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }
}
