import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Cover art: cached file first (offline), then network, then a placeholder.
class MangaCover extends StatelessWidget {
  const MangaCover({super.key, this.url, this.localPath, this.headers = const {}, this.fit = BoxFit.cover});
  final String? url;
  final String? localPath;
  final Map<String, String> headers;
  final BoxFit fit;

  Widget get _placeholder => Container(
        color: kSurface,
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_rounded, color: Colors.white24, size: 34),
      );

  @override
  Widget build(BuildContext context) {
    Widget fade(BuildContext c, Widget child, int? frame, bool sync) =>
        sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: child);
    final lp = localPath;
    if (lp != null && File(lp).existsSync()) {
      return Image.file(File(lp), fit: fit, frameBuilder: fade, errorBuilder: (_, _, _) => _placeholder);
    }
    final u = url;
    if (u == null || u.isEmpty) return _placeholder;
    return Image.network(u, fit: fit, headers: headers, frameBuilder: fade, errorBuilder: (_, _, _) => _placeholder);
  }
}

/// A cover card for grids: cover with optional badges, title below (or on
/// the cover in compact mode).
class MangaCard extends StatelessWidget {
  const MangaCard({
    super.key,
    required this.title,
    this.cover,
    this.coverPath,
    this.headers = const {},
    this.subtitle,
    this.badges = const [],
    this.compact = false,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.onLongPress,
    this.onContinue,
  });

  final String title;
  final String? cover;
  final String? coverPath;
  final Map<String, String> headers;
  final String? subtitle;
  final List<(String, Color)> badges;
  final bool compact;
  final bool selected;

  /// Already in the library (shown on Browse cards).
  final bool dimmed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Small play button on the cover that opens the next chapter directly.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final coverBox = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(fit: StackFit.expand, children: [
        MangaCover(url: cover, localPath: coverPath, headers: headers),
        if (dimmed) Container(color: Colors.black45),
        if (compact)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.transparent, Color(0xDD000000)],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
        if (badges.isNotEmpty)
          Positioned(
            top: 6,
            left: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (text, color) in badges)
                  Container(
                    color: color,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(text, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        if (onContinue != null)
          Positioned(
            right: 6,
            bottom: compact ? 40 : 6,
            child: Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onContinue,
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        if (compact)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2, color: Colors.white)),
          ),
        if (selected)
          Container(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.35),
              border: Border.all(color: scheme.primary, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded, size: 36, color: Colors.white),
          ),
      ]),
    );
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 0.7, child: coverBox),
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white60)),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Grid column count for cover grids by available width.
SliverGridDelegate coverGridDelegate(double width, {bool compact = false}) {
  final target = compact ? 116.0 : 150.0;
  final cols = (width / target).floor().clamp(2, 12);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: cols,
    mainAxisSpacing: compact ? Gap.s : Gap.m,
    crossAxisSpacing: Gap.s + 4,
    childAspectRatio: compact ? 0.7 : 0.52,
  );
}

/// "3 h ago", "Yesterday", "2026-11-03".
String relativeTime(DateTime t, DateTime now, {required String Function(int) minutes, required String Function(int) hours,
    required String yesterday, required String Function(int) days}) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return minutes(1);
  if (d.inMinutes < 60) return minutes(d.inMinutes);
  if (d.inHours < 24 && now.day == t.day) return hours(d.inHours);
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 1) return yesterday;
  if (diff < 7) return days(diff);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
