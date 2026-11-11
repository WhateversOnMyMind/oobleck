import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

import 'smi.dart';
import 'text_decode.dart';

const Set<String> kSubtitleExts = {'.smi', '.srt', '.ass', '.ssa', '.vtt', '.sub'};
const Set<String> kImportableExts = {...kSubtitleExts, '.zip'};

class SubAttachment {
  SubAttachment(this.url, this.name);
  final String url;
  final String name;
}

/// A subtitle ready to hand to the player (always UTF-8).
class PreparedSubtitle {
  PreparedSubtitle(this.ext, this.text, this.name);
  final String ext; // '.srt' | '.vtt' | '.ass' | '.ssa'
  final String text;
  final String name;
}

String _extOf(String s) => p.extension(s.split('?').first).toLowerCase();

/// Decodes (UTF-8/CP949), converts SMI to SRT, returns UTF-8 text.
PreparedSubtitle prepareSubtitle(List<int> bytes, String fileName) {
  final text = decodeSubtitleBytes(bytes);
  var ext = _extOf(fileName);
  final name = p.basenameWithoutExtension(fileName);
  if (ext == '.smi' || (ext != '.srt' && ext != '.vtt' && ext != '.ass' && ext != '.ssa' && text.toUpperCase().contains('<SAMI'))) {
    return PreparedSubtitle('.srt', cuesToSrt(parseSmi(text)), name);
  }
  if (ext == '.sub') ext = '.srt';
  return PreparedSubtitle(ext, text, name);
}

/// Picks the entry for [episode] out of a list of file names; null if
/// ambiguous (caller shows a picker).
String? pickForEpisode(List<String> names, int episode) {
  if (names.length == 1) return names.first;
  final re = RegExp('(?<![0-9])0*$episode(?![0-9])');
  final noise = RegExp(r'(1080|720|480|2160|264|265|10bit|8bit|\d{4}p)', caseSensitive: false);
  final hits = names.where((n) => re.hasMatch(p.basename(n).replaceAll(noise, ''))).toList();
  return hits.length == 1 ? hits.first : null;
}

/// Extracts subtitle files from a zip; returns name -> bytes.
Map<String, List<int>> unzipSubtitles(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  return {
    for (final f in archive.files)
      if (f.isFile && kSubtitleExts.contains(_extOf(f.name))) f.name: f.content,
  };
}

/// Finds downloadable attachment links on a release post (Tistory, blogs,
/// Google Drive). Naver Blog and unparseable pages return an empty list and
/// the caller should offer the system browser.
Future<List<SubAttachment>> findAttachments(Dio dio, String url) async {
  final u = Uri.parse(url);
  if (kImportableExts.contains(_extOf(u.path))) return [SubAttachment(url, p.basename(u.path))];
  final drive = _driveDirect(u);
  if (drive != null) return [SubAttachment(drive, 'drive-file')];
  if (u.host.contains('blog.naver.com') || u.host.contains('cafe.naver.com')) return const [];
  final r = await dio.get<String>(url, options: Options(responseType: ResponseType.plain));
  final doc = html.parse(r.data ?? '');
  final found = <SubAttachment>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    final abs = u.resolve(href).toString();
    final knm = Uri.tryParse(abs)?.queryParameters['knm'] ?? '';
    final label = a.text.trim();
    final ext = [_extOf(abs), _extOf(knm), _extOf(label)].firstWhere(kImportableExts.contains, orElse: () => '');
    final d = _driveDirect(Uri.parse(abs));
    if (d != null && seen.add(d)) {
      found.add(SubAttachment(d, label.isEmpty ? 'drive-file' : label));
    } else if (ext.isNotEmpty && seen.add(abs)) {
      found.add(SubAttachment(abs, knm.isNotEmpty ? knm : (label.isNotEmpty ? label : p.basename(Uri.parse(abs).path))));
    }
  }
  return found;
}

String? _driveDirect(Uri u) {
  if (!u.host.contains('drive.google.com')) return null;
  final m = RegExp(r'/file/d/([A-Za-z0-9_\-]+)').firstMatch(u.path);
  final id = m?.group(1) ?? u.queryParameters['id'];
  return id == null ? null : 'https://drive.google.com/uc?export=download&id=$id';
}

/// Downloads an attachment and returns candidate (name, bytes) subtitle files
/// (unzipping when needed).
Future<Map<String, List<int>>> fetchSubtitleFiles(Dio dio, SubAttachment a) async {
  final r = await dio.get<List<int>>(a.url, options: Options(responseType: ResponseType.bytes));
  final bytes = r.data ?? const <int>[];
  final looksZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (looksZip || _extOf(a.name) == '.zip') return unzipSubtitles(bytes);
  final name = kSubtitleExts.contains(_extOf(a.name)) ? a.name : '${a.name}.smi';
  return {name: bytes};
}

/// Writes a prepared subtitle to `<supportDir>/subs/<slug>/` and returns the path.
Future<String> saveSubtitle(PreparedSubtitle s, String supportDir, String slug, String episode) async {
  final dir = Directory(p.join(supportDir, 'subs', slug))..createSync(recursive: true);
  final safe = s.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  final path = p.join(dir.path, 'E${episode}_$safe${s.ext}');
  await File(path).writeAsString(s.text);
  return path;
}
