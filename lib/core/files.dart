import 'dart:io';

/// Writes [data] next to [file] and renames it into place, so a killed app
/// never leaves half a file behind.
Future<void> writeFileAtomic(File file, List<int> data) async {
  final part = File('${file.path}.part');
  await part.writeAsBytes(data, flush: true);
  await part.rename(file.path);
}

/// Size of [file] in bytes; 0 when it does not exist.
Future<int> fileSize(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return 0;
  }
}
