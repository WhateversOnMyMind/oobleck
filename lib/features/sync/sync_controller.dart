import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/log.dart';
import '../../core/storage/app_db.dart';
import '../../core/sync/sync_api.dart';
import '../../core/sync/sync_crypto.dart';
import '../../core/sync/sync_engine.dart';

class SyncState {
  const SyncState({this.username, this.serverUrl = '', this.syncing = false, this.lastSync, this.error});
  final String? username;
  final String serverUrl;
  final bool syncing;
  final DateTime? lastSync;
  /// A [SyncException] (or other error); the UI words it via `Strings.syncError`.
  final Object? error;

  bool get signedIn => username != null;

  SyncState copyWith({String? username, bool clearUser = false, String? serverUrl, bool? syncing, DateTime? lastSync, Object? error, bool clearError = false}) =>
      SyncState(
        username: clearUser ? null : username ?? this.username,
        serverUrl: serverUrl ?? this.serverUrl,
        syncing: syncing ?? this.syncing,
        lastSync: lastSync ?? this.lastSync,
        error: clearError ? null : error ?? this.error,
      );
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Signs in/out and runs sync: on launch, when the app comes back, after the
/// player closes, every 10 minutes, and on "Sync now".
class SyncController extends Notifier<SyncState> {
  static const _userKey = 'sync:user';
  static const _urlKey = 'sync:url';

  Timer? _timer;
  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;

  AppDb get _db => ref.read(dbProvider);
  SyncApi _api([String? url]) => SyncApi(ref.read(dioProvider), url ?? state.serverUrl);
  SyncEngine get _engine => SyncEngine(_db, _api());
  String? get _token => _db.misc<String>(AppDb.syncTokenKey);

  @override
  SyncState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _debounce?.cancel();
    });
    final db = ref.read(dbProvider);
    final last = db.misc<int>(SyncEngine.lastSyncKey);
    final s = SyncState(
      username: db.misc<String>(AppDb.syncTokenKey) == null ? null : db.misc<String>(_userKey),
      serverUrl: db.misc<String>(_urlKey) ?? defaultSyncUrl,
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
    if (s.signedIn) _startTimer();
    return s;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(syncNow()));
  }

  Future<void> setServerUrl(String url) async {
    final u = url.trim();
    await _db.setMisc(_urlKey, u.isEmpty || u == defaultSyncUrl ? null : u);
    state = state.copyWith(serverUrl: u.isEmpty ? defaultSyncUrl : u);
  }

  /// Signs in (or creates the account) and syncs straight away. Throws
  /// [SyncException] with a message for the dialog.
  Future<void> signIn(String username, String password, {bool create = false, String? serverUrl}) async {
    if (serverUrl != null) await setServerUrl(serverUrl);
    final key = await deriveLoginKey(username, password);
    final api = _api();
    final acc = create ? await api.register(username.trim(), key) : await api.login(username.trim(), key);
    await _engine.reset();
    await _db.setMisc(AppDb.syncTokenKey, acc.token);
    await _db.setMisc(_userKey, acc.username);
    state = SyncState(username: acc.username, serverUrl: state.serverUrl);
    _startTimer();
    await syncNow();
  }

  Future<void> signOut({bool deleteAccount = false}) async {
    final token = _token;
    if (token != null) {
      try {
        deleteAccount ? await _api().deleteAccount(token) : await _api().logout(token);
      } on SyncException catch (e) {
        if (deleteAccount) rethrow; // keep the account signed in so it can be retried
        Log.d('sync', 'logout: $e');
      }
    }
    _timer?.cancel();
    await _db.setMisc(AppDb.syncTokenKey, null);
    await _db.setMisc(_userKey, null);
    await _engine.reset();
    state = SyncState(serverUrl: state.serverUrl);
  }

  /// Sync a moment from now (lets the player's last progress write land).
  void syncSoon() {
    if (!state.signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (_running != null) {
      _again = true;
      return _running;
    }
    final run = _run();
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  Future<void> _run() async {
    final token = _token;
    if (token == null || state.serverUrl.isEmpty) return;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      await _engine.run(token);
      state = state.copyWith(syncing: false, lastSync: DateTime.now());
    } on SyncException catch (e) {
      Log.d('sync', '$e');
      if (e.signedOut) {
        await _db.setMisc(AppDb.syncTokenKey, null);
        _timer?.cancel();
        state = SyncState(serverUrl: state.serverUrl, error: e);
      } else {
        state = state.copyWith(syncing: false, error: e);
      }
    } catch (e) {
      Log.d('sync', 'failed: $e');
      state = state.copyWith(syncing: false, error: e);
    }
  }
}
