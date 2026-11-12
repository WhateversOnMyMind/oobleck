import 'dart:io';

import 'package:flutter/material.dart';

import '../app/strings.dart';
import '../app/theme.dart';

/// Animated placeholder block used instead of spinners.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = 12});
  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + 3 * t, 0),
              end: Alignment(-0.5 + 3 * t, 0),
              colors: const [Color(0xFF1A1A23), Color(0xFF262633), Color(0xFF1A1A23)],
            ),
          ),
        );
      },
    );
  }
}

/// Cover art: local file first (offline), then network, then a placeholder.
class PosterImage extends StatelessWidget {
  const PosterImage({super.key, this.url, this.localPath, this.fit = BoxFit.cover});
  final String? url;
  final String? localPath;
  final BoxFit fit;

  static const Map<String, String> headers = {'Referer': 'https://anikototv.to/'};

  Widget get _placeholder => Container(
        color: kSurface,
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
      );

  @override
  Widget build(BuildContext context) {
    Widget fade(BuildContext c, Widget child, int? frame, bool sync) =>
        sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child);

    final lp = localPath;
    if (lp != null && File(lp).existsSync()) {
      return Image.file(File(lp), fit: fit, frameBuilder: fade, errorBuilder: (_, _, _) => _placeholder);
    }
    if (url == null) return _placeholder;
    return Image.network(url!,
        fit: fit,
        headers: headers,
        frameBuilder: fade,
        errorBuilder: (_, _, _) => _placeholder,
        loadingBuilder: (c, child, p) => p == null ? child : const Skeleton(radius: 0));
  }
}

/// 2:3 poster with title below, optional badge and progress bar.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.url,
    this.localPath,
    this.subtitle,
    this.badge,
    this.progress,
    this.onTap,
    this.onLongPress,
    this.width,
  });
  final String title;
  final String? url;
  final String? localPath;
  final String? subtitle;
  final String? badge;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final card = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                PosterImage(url: url, localPath: localPath),
                if (badge != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
                      child: Text(badge!, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.black54),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white60)),
            ),
        ],
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, Gap.s),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: kAccent),
            ),
            const SizedBox(height: Gap.m),
            Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: Gap.s),
              Text(message!, style: t.bodyMedium?.copyWith(color: Colors.white60), textAlign: TextAlign.center),
            ],
            if (onAction != null) ...[
              const SizedBox(height: Gap.m),
              FilledButton(onPressed: onAction, child: Text(actionLabel ?? Strings.of(context).retry)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Friendly error with a retry button. Never shows raw URLs or stack traces.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  static String friendly(Object e, [Strings s = Strings.en]) {
    final m = e.toString().toLowerCase();
    if (m.contains('socket') || m.contains('connection') || m.contains('timeout') || m.contains('host lookup')) {
      return s.errNetwork;
    }
    if (m.contains('403') || m.contains('challenge') || m.contains('cloudflare')) {
      return s.errRefused;
    }
    return s.errGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: s.couldntLoad,
      message: friendly(error, s),
      actionLabel: s.retry,
      onAction: onRetry,
    );
  }
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}
