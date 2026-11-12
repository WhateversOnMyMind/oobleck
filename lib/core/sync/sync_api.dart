import 'package:dio/dio.dart';

import '../storage/records.dart';

/// Server URL baked in at build time (`--dart-define=OOBLECK_SYNC_URL=...`,
/// set from the `OOBLECK_SYNC_URL` repository variable in CI). Settings can
/// override it.
const defaultSyncUrl = String.fromEnvironment('OOBLECK_SYNC_URL');

/// What went wrong, so the UI can say it in the user's language.
enum SyncError { noServer, unreachable, server, signedOut, taken, wrongPassword, locked, invalid }

class SyncException implements Exception {
  SyncException(this.message, {this.kind = SyncError.server, this.status});
  final String message;
  final SyncError kind;
  final int? status;

  /// The token is no longer valid (signed out elsewhere or account deleted).
  bool get signedOut => kind == SyncError.signedOut;
  @override
  String toString() => message;
}

class SyncAccount {
  SyncAccount(this.username, this.token);
  final String username;
  final String token;
}

/// A show as the sync server stores it (enough for a Continue watching card).
class SyncShow {
  SyncShow({required this.slug, required this.title, this.poster, this.url, this.siteId, this.malId});
  final String slug;
  final String title;
  final String? poster;
  final String? url;
  final String? siteId;
  final String? malId;

  factory SyncShow.fromRecord(ShowRecord r) =>
      SyncShow(slug: r.slug, title: r.title, poster: r.poster, url: r.url, siteId: r.siteId, malId: r.malId);

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'title': title,
        'poster': poster,
        'url': url,
        'siteId': siteId,
        'malId': malId,
      };

  factory SyncShow.fromJson(Map<String, dynamic> m) => SyncShow(
        slug: m['slug'] as String,
        title: m['title'] as String,
        poster: m['poster'] as String?,
        url: m['url'] as String?,
        siteId: m['siteId'] as String?,
        malId: m['malId'] as String?,
      );
}

/// "Clear history" of one show, or of everything when [slug] is `*`, at
/// client time [at].
class SyncDeletion {
  SyncDeletion(this.slug, this.at);
  final String slug;
  final int at;
  Map<String, dynamic> toJson() => {'slug': slug, 'at': at};
  factory SyncDeletion.fromJson(Map<dynamic, dynamic> m) => SyncDeletion(m['slug'] as String, (m['at'] as num).toInt());
}

class SyncPull {
  SyncPull({required this.now, required this.history, required this.shows, required this.deletions});
  final int now;
  final List<HistoryEntry> history;
  final List<SyncShow> shows;
  final List<SyncDeletion> deletions;
}

/// HTTP client for the sync Worker in `server/`.
class SyncApi {
  SyncApi(this.dio, String baseUrl) : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final Dio dio;
  final String baseUrl;

  Future<Map<String, dynamic>> _call(String method, String path, {Object? body, String? token}) async {
    if (baseUrl.isEmpty) throw SyncException('No sync server set.', kind: SyncError.noServer);
    try {
      final r = await dio.request<Map<String, dynamic>>(
        '$baseUrl$path',
        data: body,
        options: Options(
          method: method,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return r.data ?? const {};
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final msg = data is Map && data['error'] is String ? data['error'] as String : null;
      if (status == null) throw SyncException("Can't reach the sync server.", kind: SyncError.unreachable);
      final kind = switch (status) {
        401 when token != null => SyncError.signedOut,
        401 => SyncError.wrongPassword,
        409 => SyncError.taken,
        429 => SyncError.locked,
        400 => SyncError.invalid,
        _ => SyncError.server,
      };
      throw SyncException(msg ?? 'Sync server error ($status).', kind: kind, status: status);
    }
  }

  Future<SyncAccount> register(String username, String key) => _account('/v1/register', username, key);
  Future<SyncAccount> login(String username, String key) => _account('/v1/login', username, key);

  Future<SyncAccount> _account(String path, String username, String key) async {
    final m = await _call('POST', path, body: {'username': username, 'key': key});
    return SyncAccount(m['username'] as String, m['token'] as String);
  }

  Future<void> logout(String token) => _call('POST', '/v1/logout', token: token);

  Future<void> deleteAccount(String token) => _call('DELETE', '/v1/account', token: token);

  Future<SyncPull> sync(
    String token, {
    required int since,
    required List<HistoryEntry> history,
    required List<SyncShow> shows,
    required List<SyncDeletion> deletions,
  }) async {
    final m = await _call('POST', '/v1/sync', token: token, body: {
      'since': since,
      'history': history.map((h) => h.toMap()).toList(),
      'shows': shows.map((s) => s.toJson()).toList(),
      'deletions': deletions.map((d) => d.toJson()).toList(),
    });
    return SyncPull(
      now: (m['now'] as num).toInt(),
      history: [for (final h in (m['history'] as List? ?? const [])) HistoryEntry.fromMap(h as Map)],
      shows: [for (final s in (m['shows'] as List? ?? const [])) SyncShow.fromJson((s as Map).cast<String, dynamic>())],
      deletions: [for (final d in (m['deletions'] as List? ?? const [])) SyncDeletion.fromJson(d as Map)],
    );
  }
}
