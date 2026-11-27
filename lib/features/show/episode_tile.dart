import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/storage/records.dart';

/// One row of the episode list: number, title, tags (filler, downloaded…),
/// progress bar, watched tick and a download button.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    required this.history,
    required this.download,
    required this.dubUnavailable,
    required this.selected,
    required this.selecting,
    required this.highlighted,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });

  final EpisodeInfo episode;
  final HistoryEntry? history;
  final DownloadRecord? download;
  final bool dubUnavailable;
  final bool selected;
  final bool selecting;

  /// Briefly true after "Jump to episode" lands on this row.
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onDownload;

  /// Every row has this height, so the list can jump straight to an episode.
  /// It follows the system font size.
  static double extent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = scaler.scale(16) * 1.5 + 2 + scaler.scale(11) * 1.5 + 9;
    return (text < kMinTouch ? kMinTouch : text) + 20;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    final watched = history?.isFinished ?? false;
    final partial = history?.isPartial ?? false;
    final d = download;
    return Opacity(
      opacity: dubUnavailable ? 0.45 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: selected
            ? kAccent.withValues(alpha: 0.18)
            : highlighted
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            child: Padding(
              padding: const EdgeInsets.only(left: Gap.m, right: Gap.s),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(Radii.small)),
                  child: selecting
                      ? Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: kAccent)
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(episode.number, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ),
                ),
                const SizedBox(width: Gap.m),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(episode.title.isEmpty ? tr.episode(episode.number) : episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: watched ? Colors.white54 : Colors.white)),
                    if (episode.isFiller || dubUnavailable || d != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: [
                            if (episode.isFiller) _tag(tr.filler, Colors.orangeAccent),
                            if (dubUnavailable) _tag(tr.noDub, Colors.white38),
                            if (d != null && d.isDone) _tag(tr.downloaded, kAccent),
                            if (d != null && !d.isDone) _tag(_dlLabel(d, tr), d.status == DownloadStatus.failed ? Colors.redAccent : Colors.white54),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (partial)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: history!.fraction, minHeight: 3, backgroundColor: Colors.white12),
                        ),
                      ),
                  ]),
                ),
                if (watched)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Gap.s),
                    child: Icon(Icons.check_circle_rounded, color: kAccent, size: 20),
                  ),
                if (!selecting && onDownload != null && d == null)
                  IconButton(tooltip: tr.download, icon: const Icon(Icons.download_rounded, size: 22), onPressed: onDownload)
                else
                  const SizedBox(width: Gap.s),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _dlLabel(DownloadRecord d, Strings tr) => switch (d.status) {
        DownloadStatus.queued => tr.queued,
        DownloadStatus.downloading => tr.downloadingPct((d.progress * 100).round()),
        DownloadStatus.paused => tr.paused,
        DownloadStatus.failed => tr.failed,
        DownloadStatus.done => tr.downloaded,
      };

  TextSpan _tag(String text, Color color) => TextSpan(text: '$text   ', style: TextStyle(color: color));
}
