import 'package:dio/dio.dart';

import '../../core/sources/manga_source.dart';
import '../../core/sources/toon11/toon11_source.dart';

/// Builds the manga site source. [baseUrl] overrides the default address.
MangaSource buildMangaSource(Dio dio, {String? baseUrl}) =>
    Toon11Source(dio: dio, baseUrl: (baseUrl == null || baseUrl.isEmpty) ? Toon11Source.defaultBaseUrl : baseUrl);
