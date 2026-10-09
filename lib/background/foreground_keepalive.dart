import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_task_handler.dart';

/// Android: one foreground service per install. It hosts the guardian monitor
/// (see app_task_handler.dart) and keeps the process alive during trips.
class ForegroundKeepAlive {
  static bool _withLocation = false;

  static void init() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'service_status',
        channelName: 'SafeRoute status',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// [needLocation]: a trip is about to be tracked, so the service must carry
  /// the location type (only possible once location permission is granted).
  static Future<void> start(String text, {bool needLocation = false}) async {
    if (!Platform.isAndroid) return;
    final locOk = await Permission.locationWhenInUse.isGranted;
    if (await FlutterForegroundTask.isRunningService) {
      if (needLocation && locOk && !_withLocation) {
        await FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 600));
      } else {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'SafeRoute',
          notificationText: text,
        );
        return;
      }
    }
    _withLocation = locOk;
    await FlutterForegroundTask.startService(
      serviceTypes: [
        if (locOk) ForegroundServiceTypes.location,
        ForegroundServiceTypes.specialUse,
      ],
      notificationTitle: 'SafeRoute',
      notificationText: text,
      callback: taskEntry,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }
}
