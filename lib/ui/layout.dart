import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// True on platforms that are driven with a mouse and keyboard.
bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// True on phones and tablets.
bool get isMobile => Platform.isAndroid || Platform.isIOS;

/// How many poster columns fit in [width] (the grid's full width, before its
/// side padding). Phones get three smaller covers per row; wide windows get as
/// many ~170 px covers as fit.
int posterColumns(double width, {double padding = Gap.m, double gap = Gap.m}) {
  final maxTile = width < 600 ? 130.0 : 170.0;
  const minTile = 96.0;
  final avail = width - padding * 2;
  var cols = ((avail + gap) / (maxTile + gap)).ceil();
  while (cols > 2 && (avail - gap * (cols - 1)) / cols < minTile) {
    cols--;
  }
  return cols < 2 ? 2 : cols;
}

/// Width of one poster tile in a grid of [posterColumns] columns.
double posterTileWidth(double width, {double padding = Gap.m, double gap = Gap.m}) {
  final cols = posterColumns(width, padding: padding, gap: gap);
  return (width - padding * 2 - gap * (cols - 1)) / cols;
}

/// Height a `PosterCard` of [width] needs: 2:3 cover, two title lines and an
/// optional subtitle line. Follows the system font size, so large text never
/// overflows a row or grid cell.
double posterCardHeight(BuildContext context, double width, {bool subtitle = false}) {
  final scaler = MediaQuery.textScalerOf(context);
  final title = scaler.scale(14) * 1.2 * 2;
  final sub = subtitle ? 2 + scaler.scale(12) * 1.34 : 0.0;
  return width * 1.5 + Gap.s + title + sub + 6;
}

/// Grid delegate for poster cards that adapts the column count to [width] and
/// the cell height to the system font size.
SliverGridDelegate posterGridDelegate(BuildContext context, double width, {bool subtitle = false}) {
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: posterColumns(width),
    crossAxisSpacing: Gap.m,
    mainAxisSpacing: Gap.m,
    mainAxisExtent: posterCardHeight(context, posterTileWidth(width), subtitle: subtitle),
  );
}

/// Caps a sliver's width so lists stay readable on wide windows. It stays
/// at the left, in line with the page title.
class SliverMaxWidth extends StatelessWidget {
  const SliverMaxWidth({super.key, required this.sliver, this.maxWidth = 760});
  final Widget sliver;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        final extra = c.crossAxisExtent > maxWidth ? c.crossAxisExtent - maxWidth : 0.0;
        return SliverPadding(
          padding: EdgeInsets.only(right: extra),
          sliver: sliver,
        );
      },
    );
  }
}
