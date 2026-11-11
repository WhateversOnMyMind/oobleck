import 'dart:convert';
import 'dart:typed_data';

import 'cp949_table.dart';

/// Decodes subtitle bytes: BOM-aware UTF-8/UTF-16, strict UTF-8, otherwise
/// CP949 (EUC-KR superset used by Korean fansubs).
String decodeSubtitleBytes(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return _utf16(bytes.sublist(2), Endian.little);
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return _utf16(bytes.sublist(2), Endian.big);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeCp949(bytes);
  }
}

String _utf16(List<int> b, Endian e) {
  final bd = ByteData.sublistView(Uint8List.fromList(b));
  final units = [for (var i = 0; i + 1 < b.length; i += 2) bd.getUint16(i, e)];
  return String.fromCharCodes(units);
}

String decodeCp949(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b < 0x80) {
      out.writeCharCode(b);
      i++;
    } else if (b >= 0x81 && b <= 0xFE && i + 1 < bytes.length) {
      final t = bytes[i + 1];
      if (t >= 0x41 && t <= 0xFE) {
        final c = cp949Table.codeUnitAt((b - 0x81) * cp949TrailCount + (t - 0x41));
        out.writeCharCode(c);
        i += 2;
      } else {
        out.write('�');
        i++;
      }
    } else {
      out.write('�');
      i++;
    }
  }
  return out.toString();
}

/// Test helper: encodes Hangul text as CP949 using the same table.
List<int> encodeCp949(String text) {
  final rev = <int, int>{};
  for (var i = 0; i < cp949Table.length; i++) {
    final c = cp949Table.codeUnitAt(i);
    if (c != 0xFFFD) rev.putIfAbsent(c, () => i);
  }
  final out = <int>[];
  for (final c in text.runes) {
    if (c < 0x80) {
      out.add(c);
    } else {
      final idx = rev[c];
      if (idx == null) {
        out.add(0x3F);
      } else {
        out
          ..add(0x81 + idx ~/ cp949TrailCount)
          ..add(0x41 + idx % cp949TrailCount);
      }
    }
  }
  return out;
}
