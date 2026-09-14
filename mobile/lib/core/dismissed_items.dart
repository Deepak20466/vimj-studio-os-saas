import 'package:shared_preferences/shared_preferences.dart';

/// Some admin panels (e.g. "Coaches Missing Attendance Today") are generated
/// reports, not editable database rows -- there's nothing to actually delete
/// on the backend. This gives those panels a delete/dismiss action that hides
/// a row on this device (SharedPreferences), matching the read-or-ignore
/// affordance notifications already have, without inventing backend state for
/// data that's recomputed fresh on every load. Mirrors
/// `frontend/src/utils/dismissedItems.js`.
class DismissedItems {
  static const _prefix = 'vimj_dismissed_';

  static Future<Set<int>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefix + key) ?? const [];
    return raw.map(int.parse).toSet();
  }

  static Future<void> _write(String key, Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefix + key, ids.map((e) => e.toString()).toList());
  }

  static Future<void> dismiss(String key, int id) async {
    final set = await _read(key);
    set.add(id);
    await _write(key, set);
  }

  /// Filters out already-dismissed items, and prunes dismissed ids that no
  /// longer appear in the current list (resolved/expired) so storage doesn't
  /// grow forever.
  static Future<List<T>> filter<T>(String key, List<T> items, int Function(T) idOf) async {
    final set = await _read(key);
    if (set.isEmpty) return items;
    final currentIds = items.map(idOf).toSet();
    final stale = set.difference(currentIds);
    if (stale.isNotEmpty) {
      await _write(key, set.intersection(currentIds));
    }
    return items.where((item) => !set.contains(idOf(item))).toList();
  }
}
