import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/image_header.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList([...b, ...List.filled(64, 0)]);

void main() {
  test('sizes come from the header of each common format', () {
    // JPEG: an APP0 segment, then SOF0 with height 1200 and width 800.
    final jpeg = bytes([
      0xff, 0xd8, //
      0xff, 0xe0, 0x00, 0x04, 0x00, 0x00,
      0xff, 0xc0, 0x00, 0x11, 0x08, 0x04, 0xb0, 0x03, 0x20, 0x03,
    ]);
    expect(headerSize(jpeg), (width: 800, height: 1200));

    final png = bytes([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
      0, 0, 0x02, 0xbc, 0, 0, 0x27, 0x10,
    ]);
    expect(headerSize(png), (width: 700, height: 10000));

    final gif = bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x40, 0x01, 0xf0, 0x00]);
    expect(headerSize(gif), (width: 320, height: 240));

    List<int> riff(String chunk) => [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, ...chunk.codeUnits];
    // VP8X stores width-1 and height-1 in 24 bits.
    expect(headerSize(bytes([...riff('VP8X'), 10, 0, 0, 0, 0, 0, 0, 0, 0x1f, 0x03, 0x00, 0xaf, 0x04, 0x00])),
        (width: 800, height: 1200));
    // VP8L packs 14-bit width-1 and height-1 after the 0x2f signature.
    const w = 800 - 1, h = 1200 - 1;
    const bits = w | (h << 14);
    expect(
        headerSize(bytes([...riff('VP8L'), 0, 0, 0, 0, 0x2f, bits & 0xff, bits >> 8 & 0xff, bits >> 16 & 0xff, bits >> 24 & 0xff])),
        (width: 800, height: 1200));
    // Lossy VP8: frame tag, start code, then 14-bit width and height.
    expect(headerSize(bytes([...riff('VP8 '), 0, 0, 0, 0, 0, 0, 0, 0x9d, 0x01, 0x2a, 0x20, 0x03, 0xb0, 0x04])),
        (width: 800, height: 1200));
  });

  test('error pages and cut-off files are not images', () {
    final html = Uint8List.fromList('<!DOCTYPE html><html><body>Blocked</body></html>'.codeUnits);
    expect(sniffImage(html), isNull);
    expect(headerSize(html), isNull);
    expect(describeNonImage(html), contains('<!DOCTYPE html>'));
    expect(sniffImage(Uint8List(0)), isNull);
    expect(headerSize(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0])), isNull, reason: 'cut off before the size');
  });
}
