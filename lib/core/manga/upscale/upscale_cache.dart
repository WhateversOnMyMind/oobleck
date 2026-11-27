import 'dart:collection';

/// Least-recently-used cache with a byte budget.
///
/// Entries read or stored during the current [tick] (one tick per frame) are
/// pinned: making room never evicts them, so two bands that are on screen at
/// the same time cannot push each other out and be re-rendered every frame.
class LruByteCache<K, V> {
  LruByteCache({required this._maxBytes, required this.onEvict});

  /// Called for every value that leaves the cache (to release its memory).
  final void Function(V value) onEvict;

  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap<K, _Entry<V>>();
  int _maxBytes;
  int _bytes = 0;

  /// The current frame. Advance it once per frame.
  int tick = 0;

  int get bytes => _bytes;
  int get length => _entries.length;
  int get maxBytes => _maxBytes;

  set maxBytes(int value) {
    _maxBytes = value;
    reserve(0);
  }

  bool containsKey(K key) => _entries.containsKey(key);

  /// Returns the value for [key] and marks it as most recently used.
  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    entry.tick = tick;
    _entries[key] = entry;
    return entry.value;
  }

  /// Evicts least recently used entries until [bytes] more fit in the budget.
  /// Returns false, evicting nothing, when that is impossible without touching
  /// entries used this tick.
  bool reserve(int bytes) {
    if (bytes > _maxBytes) return false;
    int free = _maxBytes - _bytes;
    if (free >= bytes) return true;
    final victims = <K>[];
    for (final e in _entries.entries) {
      if (e.value.tick >= tick) continue;
      victims.add(e.key);
      free += e.value.bytes;
      if (free >= bytes) break;
    }
    if (free < bytes) return false;
    victims.forEach(_remove);
    return true;
  }

  /// Stores [value]. Returns false (and does not take ownership of the value)
  /// when it does not fit.
  bool put(K key, V value, int bytes) {
    _remove(key);
    if (!reserve(bytes)) return false;
    _entries[key] = _Entry<V>(value, bytes, tick);
    _bytes += bytes;
    return true;
  }

  void removeWhere(bool Function(K key) test) {
    _entries.keys.where(test).toList().forEach(_remove);
  }

  void clear() {
    _entries.keys.toList().forEach(_remove);
  }

  void _remove(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    _bytes -= entry.bytes;
    onEvict(entry.value);
  }
}

class _Entry<V> {
  _Entry(this.value, this.bytes, this.tick);

  final V value;
  final int bytes;
  int tick;
}
