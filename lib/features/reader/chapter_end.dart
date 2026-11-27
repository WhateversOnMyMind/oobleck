import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../core/storage/manga_records.dart';
import '../manga/manga_strings.dart';
import 'reader_settings.dart';

/// "Finished …" and "Up next: …" (or "no next chapter") shown after a
/// chapter, with [action] under it when there is a next chapter.
class ChapterEndText extends StatelessWidget {
  const ChapterEndText({super.key, required this.finished, required this.next, required this.background, this.action});

  final ChapterRecord finished;
  final ChapterRecord? next;
  final ReaderBackground background;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final t = Theme.of(context).textTheme;
    final fg = background.foreground;
    final big = t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(tr.finishedChapter(finished.title), style: t.titleMedium?.copyWith(color: fg.withValues(alpha: 0.7))),
      const SizedBox(height: 10),
      if (next == null)
        Text(tr.noNextChapter, style: big)
      else ...[
        Text(tr.upNext(next!.title), style: big, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ]);
  }
}
