import 'package:flutter/foundation.dart';

/// Tiny in-memory logger (the only global singleton). Shown in
/// Settings > Advanced > Source diagnostics.
class Log {
  Log._();
  static final List<String> lines = <String>[];
  static const int _max = 500;

  static void d(String tag, String message) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)} [$tag] $message';
    lines.add(line);
    if (lines.length > _max) lines.removeRange(0, lines.length - _max);
    if (kDebugMode) debugPrint(line);
  }
}
