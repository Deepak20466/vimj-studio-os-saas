/// Returns whether every meaningful part of [query] appears somewhere in the
/// supplied searchable fields. Normalizing separators lets a person search for
/// displayed labels such as "Not Confirm" when the API stores `NOT_CONFIRM`.
bool matchesSearchQuery(Iterable<Object?> fields, String query) {
  final normalizedQuery = _normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;

  final normalizedFields = _normalizeSearchText(
    fields.where((value) => value != null).join(' '),
  );
  return normalizedQuery
      .split(' ')
      .where((term) => term.isNotEmpty)
      .every(normalizedFields.contains);
}

String _normalizeSearchText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[_/\\-]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
