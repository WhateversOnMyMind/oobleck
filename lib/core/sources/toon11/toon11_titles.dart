// Chapter title clean-up for 11toon.com. The chapter list repeats the series
// name in front of every chapter ("원피스(ONE PIECE) 1199화") and, when the
// text is long, replaces its middle with "…" ("원피스(ONE PI…CE) 1199화").
// Older chapters often use a shorter spelling of the series name
// ("원피스 1화"). Observed 2026-11-27.

import 'toon11_parsers.dart';

final _letter = RegExp(r'^[A-Za-z぀-ヿ一-鿿가-힣]');

final _chapterNo = RegExp(r'(\d+(?:\.\d+)?)(?:-(\d+))?\s*[화회]');
final _volumeNo = RegExp(r'(\d+(?:\.\d+)?)(?:-(\d+))?\s*권');
final _bareNo = RegExp(r'(?:^|\s)#?(\d+(?:\.\d+)?)$');
final _leadingDash = RegExp(r'^[-–:·]\s+');

/// "232화", "10.5권", "38-2화", "3회".
final _numbered = RegExp(r'\d+(?:[.\-]\d+)*\s*[화권회]');

/// Chapter label without the series name: "1199화", "외전 3화", "1부 에필로그".
/// Falls back to the full text when the name cannot be told apart.
String toon11ChapterLabel(String raw, String seriesTitle) {
  final text = toon11Clean(raw);
  final series = toon11Clean(seriesTitle);
  if (text.isEmpty || series.isEmpty) return text;
  final rest = (_stripFull(text, series) ??
          _stripTruncated(text, series) ??
          _stripSharedPrefix(text, series) ??
          _numberedTail(text) ??
          text)
      .replaceFirst(_leadingDash, '')
      .trim();
  return rest.isEmpty ? text : rest;
}

/// "귀멸의 칼날 205.5화", "귀멸의 칼날205화", and the doubled
/// "귀멸의 칼날 귀멸의 칼날 134화".
String? _stripFull(String text, String series) {
  var rest = text;
  while (rest.startsWith(series)) {
    final next = rest.substring(series.length);
    if (_letter.hasMatch(next)) break; // "원피스x토리코 콜라보" is one word
    rest = next.trimLeft();
  }
  return rest == text ? null : rest;
}

/// "원피스(ONE PI…CE) 1199화": the cut falls inside the series name, so the
/// part after "…" starts with the end of the name.
String? _stripTruncated(String text, String series) {
  final cut = text.indexOf('…');
  if (cut <= 0) return null;
  final head = text.substring(0, cut), tail = text.substring(cut + 1);
  if (!series.startsWith(head)) return null;
  final hidden = series.length - head.length;
  for (var k = hidden < tail.length ? hidden : tail.length; k > 0; k--) {
    if (tail.startsWith(series.substring(series.length - k))) return tail.substring(k).trim();
  }
  return null;
}

/// "원피스 1화" for the series "원피스(ONE PIECE)": drop the words both start with.
String? _stripSharedPrefix(String text, String series) {
  var n = 0;
  while (n < text.length && n < series.length && text[n] == series[n]) {
    n++;
  }
  if (n >= text.length || text[n] != ' ' || text.substring(0, n).trim().length < 2) return null;
  return text.substring(n).trim();
}

/// Truncated and spelled differently ("전 세계 1위의 서…육성 일기 79화"):
/// nothing of the name is recoverable, keep the numbered end.
String? _numberedTail(String text) {
  final cut = text.indexOf('…');
  if (cut < 0) return null;
  final tail = text.substring(cut + 1);
  final matches = _numbered.allMatches(tail);
  return matches.isEmpty ? null : tail.substring(matches.last.start).trim();
}

/// Chapter number from a label: "1199화" -> 1199, "12.5화" -> 12.5,
/// "제 3화" -> 3, "38-2화" -> 38.2, "299-300화" -> 299, "3권" -> 3, "36" -> 36.
/// Null when the label has no number ("특별편", "1부 에필로그").
double? toon11ChapterNumber(String label) {
  final m = _chapterNo.firstMatch(label) ??
      _volumeNo.firstMatch(label) ??
      _bareNo.firstMatch(label);
  if (m == null) return null;
  final whole = m.group(1)!;
  final part = m.groupCount >= 2 ? m.group(2) : null;
  final n = double.parse(whole);
  if (part == null || whole.contains('.')) return n;
  final p = int.parse(part);
  // "299-300화" is two chapters in one post, "38-2화" is part 2 of chapter 38.
  if (p >= 10 || (p > n && n >= 10)) return n;
  return double.parse('$whole.$part');
}
