import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../core/storage/manga_records.dart';
import 'manga_strings.dart';

/// One row of the chapter list.
class ChapterTile extends StatelessWidget {
  const ChapterTile({
    super.key,
    required this.chapter,
    this.state,
    this.download,
    this.selected = false,
    this.selecting = false,
    this.onTap,
    this.onLongPress,
    this.onDownload,
  });

  final ChapterRecord chapter;
  final ChapterState? state;
  final MangaDownloadRecord? download;
  final bool selected;
  final bool selecting;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final read = state?.read ?? false;
    final started = state?.started ?? false;
    final bookmarked = state?.bookmarked ?? false;
    final faded = read && !selected;
    final date = chapter.uploaded == null ? null : DateTime.fromMillisecondsSinceEpoch(chapter.uploaded!);
    final meta = <String>[
      if (date != null) '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      if (started && state!.pageCount > 0) tr.pageOf(state!.page + 1, state!.pageCount),
    ];
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? scheme.primary : Colors.white38),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (bookmarked)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.bookmark_rounded, size: 16, color: scheme.primary),
                    ),
                  Flexible(
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: faded ? Colors.white38 : (bookmarked ? scheme.primary : Colors.white),
                      ),
                    ),
                  ),
                ]),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(meta.join(' · '),
                        style: t.bodySmall?.copyWith(color: faded ? Colors.white24 : Colors.white54)),
                  ),
                if (started && !read)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: state!.fraction, minHeight: 3, backgroundColor: Colors.white12),
                    ),
                  ),
              ]),
            ),
            if (!selecting) _DownloadButton(download: download, onPressed: onDownload, tr: tr),
          ]),
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.download, required this.onPressed, required this.tr});
  final MangaDownloadRecord? download;
  final VoidCallback? onPressed;
  final Strings tr;

  @override
  Widget build(BuildContext context) {
    final d = download;
    final scheme = Theme.of(context).colorScheme;
    Widget icon;
    String tip;
    if (d == null) {
      icon = const Icon(Icons.download_for_offline_outlined, color: Colors.white54);
      tip = tr.download;
    } else {
      switch (d.status) {
        case MangaDownloadStatus.done:
          icon = Icon(Icons.download_done_rounded, color: scheme.primary);
          tip = tr.deleteDownload;
        case MangaDownloadStatus.running:
          icon = SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(value: d.pagesTotal == 0 ? null : d.progress, strokeWidth: 2.5),
          );
          tip = tr.pause;
        case MangaDownloadStatus.queued:
          icon = const Icon(Icons.schedule_rounded, color: Colors.white54);
          tip = tr.waiting;
        case MangaDownloadStatus.paused:
          icon = const Icon(Icons.pause_circle_outline_rounded, color: Colors.white54);
          tip = tr.resumeDownload;
        case MangaDownloadStatus.failed:
          icon = Icon(Icons.error_outline_rounded, color: scheme.error);
          tip = tr.failed;
      }
    }
    return IconButton(tooltip: tip, onPressed: onPressed, icon: icon);
  }
}
