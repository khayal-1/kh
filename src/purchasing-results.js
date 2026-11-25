/** Apply independent Supabase query results without discarding successful siblings. */
export function applyQueryResults(state, entries, onError = () => {}) {
  const loaded = new Set();
  for (const { result, key, label } of entries) {
    if (result?.error) {
      onError(label, result.error);
      continue;
    }
    state[key] = result?.data ?? [];
    loaded.add(key);
  }
  return loaded;
}
