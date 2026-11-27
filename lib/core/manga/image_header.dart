import 'dart:typed_data';

/// Image formats recognised from their first bytes.
enum ImageKind { jpeg, png, gif, webp, avif, bmp }

/// The format of [b] from its signature, or null when it is not an image this
/// app can show (an HTML error page, an empty or cut-off file).
ImageKind? sniffImage(Uint8List b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0xff, 0xd8, 0xff])) return ImageKind.jpeg;
  if (at(0, const [0x89, 0x50, 0x4e, 0x47])) return ImageKind.png;
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return ImageKind.gif;
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return ImageKind.webp;
  if (at(4, const [0x66, 0x74, 0x79, 0x70])) return ImageKind.avif; // ISO media (avif/heic)
  if (at(0, const [0x42, 0x4d])) return ImageKind.bmp;
  return null;
}

/// Width and height read straight from the file header, without decoding.
/// Null when the format or header is not understood.
({int width, int height})? headerSize(Uint8List b) {
  int u16be(int i) => (b[i] << 8) | b[i + 1];
  int u16le(int i) => b[i] | (b[i + 1] << 8);
  int u32be(int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  try {
    switch (sniffImage(b)) {
      case ImageKind.png:
        return (width: u32be(16), height: u32be(20));
      case ImageKind.gif:
        return (width: u16le(6), height: u16le(8));
      case ImageKind.webp:
        final chunk = String.fromCharCodes(b.sublist(12, 16));
        if (chunk == 'VP8X') {
          return (width: 1 + (b[24] | b[25] << 8 | b[26] << 16), height: 1 + (b[27] | b[28] << 8 | b[29] << 16));
        }
        if (chunk == 'VP8L') {
          final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
          return (width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff));
        }
        if (chunk == 'VP8 ') return (width: u16le(26) & 0x3fff, height: u16le(28) & 0x3fff);
        return null;
      case ImageKind.jpeg:
        var i = 2;
        while (i + 9 < b.length) {
          if (b[i] != 0xff) return null;
          final marker = b[i + 1];
          if (marker == 0xff) {
            i++;
            continue;
          }
          // Start-of-frame markers carry the size (not DHT, JPG or DAC).
          if (marker >= 0xc0 && marker <= 0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc) {
            return (width: u16be(i + 7), height: u16be(i + 5));
          }
          i += 2 + u16be(i + 2);
        }
        return null;
      case ImageKind.avif || ImageKind.bmp || null:
        return null;
    }
  } on RangeError {
    return null;
  }
}

/// A short, readable description of bytes that are not an image, for error
/// details (the start of an HTML page, or the first bytes in hex).
String describeNonImage(Uint8List b) {
  if (b.isEmpty) return 'empty file';
  final head = b.sublist(0, b.length < 120 ? b.length : 120);
  final text = String.fromCharCodes(head.where((c) => c >= 0x20 && c < 0x7f || c == 0x0a));
  if (text.length > head.length * 0.8) return '${b.length} bytes: ${text.replaceAll('\n', ' ').trim()}';
  return '${b.length} bytes starting ${head.take(12).map((c) => c.toRadixString(16).padLeft(2, '0')).join(' ')}';
}
