import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/sync/sync_api.dart';
import 'sync_controller.dart';

/// Settings tiles for watch-history sync.
class SyncSettingsSection extends ConsumerWidget {
  const SyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncProvider);
    final c = ref.read(syncProvider.notifier);
    final tr = Strings.of(context);
    if (!s.signedIn) {
      return ListTile(
        leading: const Icon(Icons.cloud_sync_outlined),
        title: Text(tr.syncWatchHistory),
        subtitle: Text(s.error == null ? tr.syncPitch : tr.syncError(s.error!)),
        trailing: FilledButton.tonal(onPressed: () => showSyncSignIn(context), child: Text(tr.signIn)),
        onTap: () => showSyncSignIn(context),
      );
    }
    return Column(children: [
      ListTile(
        leading: Icon(Icons.cloud_done_outlined, color: s.error == null ? kAccent : Colors.orangeAccent),
        title: Text(tr.signedInAs(s.username!)),
        subtitle: Text(s.syncing ? tr.syncing : s.error != null ? tr.syncError(s.error!) : syncedAgo(s.lastSync, DateTime.now(), tr)),
        trailing: s.syncing
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(onPressed: () => unawaited(c.syncNow()), child: Text(tr.syncNow)),
      ),
      ListTile(
        leading: const Icon(Icons.logout_rounded),
        title: Text(tr.signOut),
        subtitle: Text(tr.signOutHint),
        onTap: () => unawaited(c.signOut()),
      ),
    ]);
  }
}

/// Top-right of Home: a "Sign in" button while signed out, then the user ID
/// with the sync state (tap to sync now).
class HomeSyncButton extends ConsumerWidget {
  const HomeSyncButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncProvider);
    final tr = Strings.of(context);
    if (!s.signedIn) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: FilledButton.icon(
          onPressed: () => showSyncSignIn(context),
          icon: const Icon(Icons.person_outline_rounded, size: 20),
          label: Text(tr.signIn),
        ),
      );
    }
    final icon = s.syncing
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(s.error == null ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            size: 20, color: s.error == null ? kAccent : Colors.orangeAccent);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Tooltip(
        message: s.syncing ? tr.syncing : s.error != null ? tr.syncError(s.error!) : tr.tapToSync(syncedAgo(s.lastSync, DateTime.now(), tr)),
        child: ActionChip(
          avatar: icon,
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(s.username!, overflow: TextOverflow.ellipsis),
          ),
          onPressed: () => unawaited(ref.read(syncProvider.notifier).syncNow()),
        ),
      ),
    );
  }
}

String syncedAgo(DateTime? t, DateTime now, [Strings tr = Strings.en]) {
  if (t == null) return tr.notSyncedYet;
  final d = now.difference(t);
  if (d.inMinutes < 1) return tr.syncedJustNow;
  if (d.inMinutes < 60) return tr.syncedMinAgo(d.inMinutes);
  if (d.inHours < 24) return tr.syncedHoursAgo(d.inHours);
  return tr.syncedOn('${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}');
}

final _userPattern = RegExp(r'^[a-z0-9_.-]{3,32}$');

/// Checks the form before anything is sent; null when it is fine.
String? validateSyncForm({required String user, required String password, String? confirm, required bool create, required String server, Strings tr = Strings.en}) {
  if (server.trim().isEmpty) return tr.errServerAddress;
  final u = Uri.tryParse(server.trim());
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return tr.errServerScheme;
  if (!_userPattern.hasMatch(user.trim().toLowerCase())) return tr.errUserId;
  if (password.length < 8) return tr.errPassword;
  if (create && confirm != password) return tr.errPasswordsDiffer;
  return null;
}

Future<void> showSyncSignIn(BuildContext context) => showDialog<void>(context: context, builder: (_) => const SyncSignInDialog());

class SyncSignInDialog extends ConsumerStatefulWidget {
  const SyncSignInDialog({super.key});
  @override
  ConsumerState<SyncSignInDialog> createState() => _SyncSignInDialogState();
}

class _SyncSignInDialogState extends ConsumerState<SyncSignInDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  late final _server = TextEditingController(text: ref.read(syncProvider).serverUrl);
  bool _create = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_user, _pass, _confirm, _server]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final err = validateSyncForm(user: _user.text, password: _pass.text, confirm: _confirm.text, create: _create, server: _server.text, tr: Strings.of(context));
    if (err != null) return setState(() => _error = err);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncProvider.notifier).signIn(_user.text, _pass.text, create: _create, serverUrl: _server.text);
      if (mounted) Navigator.of(context).pop();
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = Strings.of(context).syncError(e));
    } catch (_) {
      if (mounted) setState(() => _error = Strings.of(context).errSignIn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showServer = defaultSyncUrl.isEmpty || _server.text != defaultSyncUrl;
    final tr = Strings.of(context);
    return AlertDialog(
      title: Text(tr.syncWatchHistory),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr.signIn)),
                ButtonSegment(value: true, label: Text(tr.createAccount)),
              ],
              selected: {_create},
              onSelectionChanged: _busy ? null : (v) => setState(() => _create = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(labelText: tr.userId),
            ),
            TextField(
              controller: _pass,
              enabled: !_busy,
              obscureText: true,
              autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: tr.password),
              onSubmitted: _create ? null : (_) => unawaited(_submit()),
            ),
            if (_create)
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(labelText: tr.passwordAgain),
                onSubmitted: (_) => unawaited(_submit()),
              ),
            if (showServer)
              TextField(
                controller: _server,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr.syncServer, hintText: 'https://oobleck-sync.<name>.workers.dev'),
              ),
            if (_create) ...[
              const SizedBox(height: 12),
              Text(
                tr.noReset,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr.cancel)),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_submit()),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_create ? tr.createAccount : tr.signIn),
        ),
      ],
    );
  }
}
