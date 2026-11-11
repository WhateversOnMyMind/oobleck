import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/storage/app_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final dbDir = Directory(p.join(support.path, 'db'))..createSync(recursive: true);
  final db = await AppDb.open(dbDir.path);
  runApp(ProviderScope(
    overrides: [
      dbProvider.overrideWithValue(db),
      supportDirProvider.overrideWithValue(support.path),
    ],
    child: const OobleckApp(),
  ));
}
