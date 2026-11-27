/// Runs [task] for each of [items] in order, with at most [limit] running at
/// the same time.
Future<void> forEachLimited<T>(List<T> items, int limit, Future<void> Function(T item) task) {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      await task(items[next++]);
    }
  }

  return Future.wait([for (var i = 0; i < limit && i < items.length; i++) worker()]);
}
