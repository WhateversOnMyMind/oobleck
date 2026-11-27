import 'package:dio/dio.dart';

import '../../log.dart';

/// Public pages that link 11toon's current address. The site moves often and
/// some networks block its domains, so when the saved address stops working
/// the app reads the address from here.
///
/// Observed 2026-11-27: the Namuwiki article "일일툰" has the working link in
/// its info box ("링크" row), then `http://103.204.13.68:8904/bbs/board.php?...`.
/// The page is plain HTML (no bot check); if it ever shows one, discovery
/// just fails and the user can type the address in Settings.
const toon11AddressPages = ['https://namu.wiki/w/%EC%9D%BC%EC%9D%BC%ED%88%B0'];

final _link = RegExp(r'''https?://([A-Za-z0-9.-]+)(:\d{1,5})?(?=[/'"\s<?#]|$)''');
final _ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
final _toonHost = RegExp(r'(^|\.)11toon\d*\.[a-z.]+$');

/// Candidate site addresses (`scheme://host[:port]`) linked on [html], in page
/// order: bare IPv4 hosts and hosts named like `11toon<N>.<tld>`. Image hosts
/// such as `11toon8.com` may show up too; checking each one weeds them out.
List<String> parseToon11Addresses(String html) {
  final out = <String>[];
  for (final m in _link.allMatches(html)) {
    final host = m.group(1)!.toLowerCase();
    if (!_ipv4.hasMatch(host) && !_toonHost.hasMatch(host)) continue;
    final scheme = m.group(0)!.startsWith('https') ? 'https' : 'http';
    final base = '$scheme://$host${m.group(2) ?? ''}';
    if (!out.contains(base)) out.add(base);
  }
  return out;
}

/// True when [html] is an 11toon listing page (observed 2026-11-27: the title
/// says 일일툰 and series links use `bo_table=toons`).
bool looksLikeToon11(String html) => html.contains('일일툰') && html.contains('bo_table=toons');

/// Finds an 11toon address that answers.
class Toon11AddressFinder {
  Toon11AddressFinder(this.dio, {this.pages = toon11AddressPages, this.timeout = const Duration(seconds: 8)});

  final Dio dio;
  final List<String> pages;
  final Duration timeout;

  Future<String> _text(String url, {Map<String, String>? headers}) async {
    final r = await dio.get<String>(url,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ));
    return r.data ?? '';
  }

  /// Whether [base] serves the 11toon latest-updates list.
  Future<bool> works(String base) async {
    try {
      return looksLikeToon11(await _text('$base/bbs/board.php?bo_table=toon_c&type=upd', headers: {'Referer': '$base/'}));
    } catch (e) {
      Log.d('toon11', 'address $base: $e');
      return false;
    }
  }

  /// The first address that works: [tryFirst] in order, then the ones linked
  /// on [pages]. Null when none answers.
  Future<String?> find({List<String> tryFirst = const []}) async {
    final tried = <String>{};
    for (final base in tryFirst) {
      if (tried.add(base) && await works(base)) return base;
    }
    for (final page in pages) {
      String html;
      try {
        html = await _text(page);
      } catch (e) {
        Log.d('toon11', 'address page $page: $e');
        continue;
      }
      for (final base in parseToon11Addresses(html)) {
        if (tried.add(base) && await works(base)) return base;
      }
    }
    return null;
  }
}
