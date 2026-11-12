import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/features/player/video_fit.dart';

void main() {
  test('Fit -> Zoom to fill -> Stretch -> Fit, unknown names fall back to Fit', () {
    expect(VideoFit.fit.next, VideoFit.fill);
    expect(VideoFit.fill.next, VideoFit.stretch);
    expect(VideoFit.stretch.next, VideoFit.fit);
    expect(VideoFit.fill.boxFit, BoxFit.cover);
    expect(VideoFit.parse('fill'), VideoFit.fill);
    expect(VideoFit.parse(null), VideoFit.fit);
    expect(VideoFit.parse('garbage'), VideoFit.fit);
  });

  test('phone subtitles follow screen height, not the old sqrt(area / 1080p) rule', () {
    // Landscape phone (~915x412 dp) with the default size 46.
    const phone = Size(915, 412);
    final dp = 46 * subtitleTextScale(phone);
    expect(dp, inInclusiveRange(18, 23));
    // The old media_kit rule gave about 10 dp here.
    // Same height, so the same size for a 4:3 and a 16:9 show.
    expect(subtitleTextScale(const Size(549, 412)), subtitleTextScale(phone));
    // A tablet gets proportionally larger text, capped.
    expect(subtitleTextScale(const Size(1280, 800)), greaterThan(subtitleTextScale(phone)));
    expect(subtitleTextScale(const Size(8000, 4000)), 2.0);
    expect(subtitleTextScale(Size.zero), 1);
  });
}
