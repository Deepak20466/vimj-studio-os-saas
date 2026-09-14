// Some admin panels (e.g. "Coaches Missing Attendance Today") are generated
// reports, not editable database rows — there's nothing to actually delete on
// the backend. This gives those panels a "Delete"/dismiss action that hides a
// row for the current browser (localStorage), matching the read-or-ignore
// affordance notifications already have, without inventing backend state for
// data that's recomputed fresh on every load.

const STORAGE_PREFIX = "vimj_dismissed_";

function readSet(key) {
  try {
    const raw = localStorage.getItem(STORAGE_PREFIX + key);
    return raw ? new Set(JSON.parse(raw)) : new Set();
  } catch {
    return new Set();
  }
}

function writeSet(key, set) {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, JSON.stringify([...set]));
  } catch {
    // localStorage unavailable (private mode, quota) — dismissal just won't persist across reloads
  }
}

export function dismissItem(key, id) {
  const set = readSet(key);
  set.add(id);
  writeSet(key, set);
}

// Filters out already-dismissed items, and prunes dismissed ids that no
// longer appear in the current list (resolved/expired) so storage doesn't
// grow forever.
export function filterDismissed(key, items, idFn) {
  const set = readSet(key);
  if (set.size === 0) return items;
  const currentIds = new Set(items.map(idFn));
  let changed = false;
  for (const id of set) {
    if (!currentIds.has(id)) {
      set.delete(id);
      changed = true;
    }
  }
  if (changed) writeSet(key, set);
  return items.filter((item) => !set.has(idFn(item)));
}
