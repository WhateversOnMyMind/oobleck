import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../log.dart';

/// Keeps the app process alive on Android while downloads run (foreground
/// service + progress notification). No-op on other platforms.
class DownloadForeground {
  bool _inited = false;

  bool get _supported => Platform.isAndroid;

  void init() {
    if (!_supported || _inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'oobleck_downloads',
        channelName: 'Downloads',
        channelDescription: 'Shows progress while episodes download.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  Future<void> show(String title, String text) async {
    if (!_supported) return;
    try {
      init();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else {
        if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
        await FlutterForegroundTask.startService(notificationTitle: title, notificationText: text);
      }
    } catch (e) {
      Log.d('fg', 'foreground service error: $e');
    }
  }

  Future<void> stop() async {
    if (!_supported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (e) {
      Log.d('fg', 'stop error: $e');
    }
  }
}
