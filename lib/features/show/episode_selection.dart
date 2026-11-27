import '../../core/models.dart';

/// The episode numbers from [anchor] to [target] inclusive, in the order of
/// [ordered] (whichever of the two comes first). Used for "long-press another
/// episode to select everything in between". Empty if either is unknown.
List<String> episodeSpan(List<String> ordered, String anchor, String target) {
  final a = ordered.indexOf(anchor);
  final b = ordered.indexOf(target);
  if (a < 0 || b < 0) return const [];
  return ordered.sublist(a < b ? a : b, (a < b ? b : a) + 1);
}

/// Episodes numbered [from]..[to] inclusive. The bounds may be given in
/// either order, so typing "12 to 1" still works.
List<EpisodeInfo> episodesBetween(List<EpisodeInfo> episodes, num from, num to) {
  final lo = from < to ? from : to;
  final hi = from < to ? to : from;
  return episodes.where((e) => e.numeric >= lo && e.numeric <= hi).toList();
}

/// Index of the episode a typed number should jump to: the exact episode, or
/// the first one after it (for shows that skip numbers). -1 when [input] is
/// not a number or is past the last episode.
int episodeIndexFor(List<EpisodeInfo> ordered, String input) {
  final exact = ordered.indexWhere((e) => e.number == input.trim());
  if (exact >= 0) return exact;
  final n = double.tryParse(input.trim());
  if (n == null) return -1;
  var best = -1;
  for (var i = 0; i < ordered.length; i++) {
    final v = ordered[i].numeric;
    if (v >= n && (best < 0 || v < ordered[best].numeric)) best = i;
  }
  return best;
}
