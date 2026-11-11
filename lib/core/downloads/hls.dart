/// Minimal HLS playlist parsing (master + media playlists) for the downloader
/// and the player's quality menu.
library;

class HlsVariant {
  HlsVariant({required this.url, required this.bandwidth, this.width, this.height});
  final Uri url;
  final int bandwidth;
  final int? width;
  final int? height;

  String get label => height != null ? '${height}p' : '${(bandwidth / 1000).round()} kbps';
}

class HlsKey {
  HlsKey({required this.uri, this.iv});
  final Uri uri;

  /// 16 bytes, or null to derive from the segment's media sequence number.
  final List<int>? iv;
}

class HlsSegment {
  HlsSegment({required this.url, required this.duration, required this.sequence, this.key, this.byteRange});
  final Uri url;
  final double duration;
  final int sequence;
  final HlsKey? key;
  final String? byteRange;
}

class HlsMediaPlaylist {
  HlsMediaPlaylist({required this.segments, this.initSegment, this.isLive = false});
  final List<HlsSegment> segments;
  final Uri? initSegment;
  final bool isLive;
  double get totalDuration => segments.fold(0.0, (a, s) => a + s.duration);
}

bool isMasterPlaylist(String text) => text.contains('#EXT-X-STREAM-INF');

Map<String, String> _attrs(String s) {
  final out = <String, String>{};
  final re = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|[^,]*)');
  for (final m in re.allMatches(s)) {
    out[m.group(1)!] = m.group(3) ?? m.group(2)!;
  }
  return out;
}

List<int> _hexToBytes(String hex) {
  var h = hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;
  h = h.padLeft(32, '0');
  return [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
}

List<HlsVariant> parseMasterPlaylist(String text, Uri base) {
  final lines = text.split(RegExp(r'\r?\n'));
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (!l.startsWith('#EXT-X-STREAM-INF:')) continue;
    final a = _attrs(l.substring('#EXT-X-STREAM-INF:'.length));
    var j = i + 1;
    while (j < lines.length && (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
      j++;
    }
    if (j >= lines.length) break;
    int? w, h;
    final res = a['RESOLUTION'];
    if (res != null && res.contains('x')) {
      final p = res.split('x');
      w = int.tryParse(p[0]);
      h = int.tryParse(p[1]);
    }
    out.add(HlsVariant(
      url: base.resolve(lines[j].trim()),
      bandwidth: int.tryParse(a['BANDWIDTH'] ?? a['AVERAGE-BANDWIDTH'] ?? '') ?? 0,
      width: w,
      height: h,
    ));
  }
  return out;
}

/// 'best' -> highest bandwidth. A number -> the best variant not taller than
/// that, else the smallest one available.
HlsVariant pickVariant(List<HlsVariant> variants, String quality) {
  final sorted = [...variants]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  final target = int.tryParse(quality);
  if (target == null) return sorted.first;
  final fits = sorted.where((v) => (v.height ?? 0) > 0 && v.height! <= target).toList();
  if (fits.isNotEmpty) return fits.first;
  return sorted.last;
}

HlsMediaPlaylist parseMediaPlaylist(String text, Uri base) {
  final lines = text.split(RegExp(r'\r?\n'));
  var seq = 0;
  HlsKey? key;
  Uri? init;
  var dur = 0.0;
  String? range;
  var live = true;
  final segs = <HlsSegment>[];
  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      seq = int.tryParse(l.substring(22)) ?? 0;
    } else if (l.startsWith('#EXT-X-KEY:')) {
      final a = _attrs(l.substring(11));
      if ((a['METHOD'] ?? 'NONE') == 'AES-128' && a['URI'] != null) {
        key = HlsKey(uri: base.resolve(a['URI']!), iv: a['IV'] != null ? _hexToBytes(a['IV']!) : null);
      } else {
        key = null;
      }
    } else if (l.startsWith('#EXT-X-MAP:')) {
      final a = _attrs(l.substring(11));
      if (a['URI'] != null) init = base.resolve(a['URI']!);
    } else if (l.startsWith('#EXTINF:')) {
      dur = double.tryParse(l.substring(8).split(',').first) ?? 0;
    } else if (l.startsWith('#EXT-X-BYTERANGE:')) {
      range = l.substring(17);
    } else if (l.startsWith('#EXT-X-ENDLIST')) {
      live = false;
    } else if (!l.startsWith('#')) {
      segs.add(HlsSegment(url: base.resolve(l), duration: dur, sequence: seq, key: key, byteRange: range));
      seq++;
      range = null;
    }
  }
  return HlsMediaPlaylist(segments: segs, initSegment: init, isLive: live);
}
