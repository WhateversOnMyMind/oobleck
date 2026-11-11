/// SAMI (.smi) parser and converters to SRT / WebVTT.
library;

class SubCue {
  SubCue(this.startMs, this.endMs, this.text);
  final int startMs;
  final int endMs;
  final String text;
}

final RegExp _sync = RegExp(r'<SYNC\s+Start\s*=\s*["\x27]?(\d+)["\x27]?[^>]*>', caseSensitive: false);
final RegExp _pClass = RegExp(r'<P\s+[^>]*Class\s*=\s*["\x27]?([A-Za-z0-9_\-]+)', caseSensitive: false);
final RegExp _hangul = RegExp(r'[가-힣]');

String _entities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String _clean(String body) {
  var t = body.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = _entities(t);
  return t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');
}

/// Parses SAMI text. When several language classes exist, the class with the
/// most Hangul is chosen (or [className] if given).
List<SubCue> parseSmi(String text, {String? className}) {
  final matches = _sync.allMatches(text).toList();
  final byClass = <String, List<(int, String)>>{};
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final start = int.parse(m.group(1)!);
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    var body = text.substring(m.end, end);
    final c = _pClass.firstMatch(body)?.group(1) ?? '_';
    body = body.replaceFirst(RegExp(r'<P[^>]*>', caseSensitive: false), '');
    byClass.putIfAbsent(c, () => []).add((start, _clean(body.replaceAll(RegExp(r'</?(SAMI|BODY)[^>]*>', caseSensitive: false), ''))));
  }
  if (byClass.isEmpty) return const [];
  String chosen;
  if (className != null && byClass.containsKey(className)) {
    chosen = className;
  } else {
    chosen = byClass.keys.first;
    var best = -1;
    byClass.forEach((k, v) {
      final score = v.where((e) => _hangul.hasMatch(e.$2)).length;
      if (score > best) {
        best = score;
        chosen = k;
      }
    });
  }
  final rows = byClass[chosen]!;
  final cues = <SubCue>[];
  for (var i = 0; i < rows.length; i++) {
    final (start, t) = rows[i];
    if (t.isEmpty) continue;
    var end = i + 1 < rows.length ? rows[i + 1].$1 : start + 3000;
    if (end <= start) end = start + 2000;
    cues.add(SubCue(start, end, t));
  }
  return cues;
}

/// Class names present in a SAMI document (for a language picker).
List<String> smiClasses(String text) => {for (final m in _pClass.allMatches(text)) m.group(1)!}.toList();

String _ts(int ms, String sep) {
  final h = (ms ~/ 3600000).toString().padLeft(2, '0');
  final m = ((ms ~/ 60000) % 60).toString().padLeft(2, '0');
  final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
  final f = (ms % 1000).toString().padLeft(3, '0');
  return '$h:$m:$s$sep$f';
}

String cuesToSrt(List<SubCue> cues) {
  final b = StringBuffer();
  for (var i = 0; i < cues.length; i++) {
    b
      ..writeln(i + 1)
      ..writeln('${_ts(cues[i].startMs, ',')} --> ${_ts(cues[i].endMs, ',')}')
      ..writeln(cues[i].text)
      ..writeln();
  }
  return b.toString();
}

String cuesToVtt(List<SubCue> cues) {
  final b = StringBuffer('WEBVTT\n\n');
  for (final c in cues) {
    b
      ..writeln('${_ts(c.startMs, '.')} --> ${_ts(c.endMs, '.')}')
      ..writeln(c.text)
      ..writeln();
  }
  return b.toString();
}
