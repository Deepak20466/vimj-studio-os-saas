import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SalaryFilterHeader extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final DateTime? fromMonth;
  final DateTime? toMonth;
  final VoidCallback onPickFromMonth;
  final VoidCallback onPickToMonth;
  final VoidCallback onClear;
  final bool hasFilters;
  final int visibleCount;
  final int totalCount;

  const SalaryFilterHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.fromMonth,
    required this.toMonth,
    required this.onPickFromMonth,
    required this.onPickToMonth,
    required this.onClear,
    required this.hasFilters,
    required this.visibleCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
        pinned: true,
        delegate: _SalaryFilterHeaderDelegate(
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search coach, month, amount, status',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickFromMonth,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: Text(
                            fromMonth == null
                                ? 'From month'
                                : 'From: ${DateFormat('MMM yyyy').format(fromMonth!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickToMonth,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: Text(
                            toMonth == null
                                ? 'To month'
                                : 'To: ${DateFormat('MMM yyyy').format(toMonth!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$visibleCount of $totalCount records',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (hasFilters)
                        TextButton(
                          onPressed: onClear,
                          child: const Text('Clear filters'),
                        )
                      else
                        const SizedBox(height: 36),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SalaryFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _SalaryFilterHeaderDelegate({required this.child});

  @override
  double get minExtent => 168;

  @override
  double get maxExtent => 168;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      child;

  @override
  bool shouldRebuild(covariant _SalaryFilterHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

Future<DateTime?> pickSalaryMonth(
  BuildContext context, {
  required DateTime? selectedMonth,
  required String helpText,
}) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: selectedMonth ?? now,
    firstDate: DateTime(2000),
    lastDate: DateTime(2200, 12, 31),
    helpText: helpText,
  );
  return picked == null ? null : DateTime(picked.year, picked.month);
}

bool salaryMatchesFilters({
  required int year,
  required int month,
  required String search,
  required DateTime? fromMonth,
  required DateTime? toMonth,
  required Iterable<Object?> searchFields,
}) {
  final period = DateTime(year, month);
  if (fromMonth != null &&
      period.isBefore(DateTime(fromMonth.year, fromMonth.month))) {
    return false;
  }
  if (toMonth != null &&
      period.isAfter(DateTime(toMonth.year, toMonth.month))) {
    return false;
  }
  final query = search.trim().toLowerCase();
  if (query.isEmpty) return true;
  return searchFields
      .where((value) => value != null)
      .map((value) => value.toString().toLowerCase())
      .join(' ')
      .contains(query);
}
