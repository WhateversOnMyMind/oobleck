import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import '../../ui/widgets.dart';
import '../reader/open_reader.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';

/// Offline chapters and the download queue, grouped by series.
class MangaDownloadsScreen extends ConsumerWidget {
  const MangaDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final all = ref.watch(mangaDownloadsProvider).value ?? const <MangaDownloadRecord>[];
    ref.watch(chapterStateTickProvider);
    final db = ref.read(dbProvider);
    final dl = ref.read(mangaDownloaderProvider);
    final bySeries = <String, List<MangaDownloadRecord>>{};
    for (final d in all) {
      bySeries.putIfAbsent(d.mangaKey, () => []).add(d);
    }
    final total = all.fold<int>(0, (a, d) => a + d.bytes);
    final readDone = all.where((d) => d.isDone && (db.chapterState(d.mangaKey, d.chapterId)?.read ?? false)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.mangaDownloads),
        actions: [
          if (readDone.isNotEmpty)
            IconButton(
              tooltip: tr.deleteRead,
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(tr.deleteRead),
                    content: Text(tr.chapterCount(readDone.length)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.delete)),
                    ],
                  ),
                );
                if (ok != true) return;
                for (final d in readDone) {
                  await dl.delete(d.key);
                }
              },
            ),
        ],
      ),
      body: all.isEmpty
          ? Center(child: EmptyState(icon: Icons.download_for_offline_outlined, title: tr.downloadsEmpty, message: tr.downloadsEmptyHint))
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('${tr.chapterCount(all.length)} · ${formatBytes(total)}', style: const TextStyle(color: Colors.white60)),
              ),
              for (final e in bySeries.entries) ...[
                SectionHeader(db.manga(e.key)?.title ?? e.key),
                for (final d in (e.value..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0))))
                  ListTile(
                    title: Text(d.chapterTitle),
                    subtitle: _status(context, tr, d),
                    onTap: d.isDone ? () => openReader(context, mangaKey: d.mangaKey, chapterId: d.chapterId) : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (d.status == MangaDownloadStatus.running || d.status == MangaDownloadStatus.queued)
                        IconButton(tooltip: tr.pause, icon: const Icon(Icons.pause_rounded), onPressed: () => dl.pause(d.key)),
                      if (d.status == MangaDownloadStatus.paused || d.status == MangaDownloadStatus.failed)
                        IconButton(tooltip: tr.resumeDownload, icon: const Icon(Icons.play_arrow_rounded), onPressed: () => dl.resume(d.key)),
                      IconButton(
                        tooltip: tr.deleteDownload,
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => unawaited(dl.delete(d.key)),
                      ),
                    ]),
                  ),
              ],
            ]),
    );
  }

  Widget _status(BuildContext context, Strings tr, MangaDownloadRecord d) => switch (d.status) {
        MangaDownloadStatus.done => Text(formatBytes(d.bytes), style: const TextStyle(color: Colors.white54)),
        MangaDownloadStatus.running => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: d.pagesTotal == 0 ? null : d.progress, minHeight: 3),
          ),
        MangaDownloadStatus.queued => Text(tr.waiting, style: const TextStyle(color: Colors.white54)),
        MangaDownloadStatus.paused => Text(tr.pause, style: const TextStyle(color: Colors.white54)),
        MangaDownloadStatus.failed => Text(tr.failed, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      };
}
