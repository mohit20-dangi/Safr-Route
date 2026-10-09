import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../firebase_options.dart';
import '../services/alert_service.dart';
import 'monitor_part.dart';
import 'tracker_part.dart';

@pragma('vm:entry-point')
void taskEntry() => FlutterForegroundTask.setTaskHandler(AppTaskHandler());

/// Runs in the foreground-service isolate, so the guardian monitor keeps
/// working when the app UI is closed.
class AppTaskHandler extends TaskHandler {
  final monitor = MonitorPart();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {}
    await AlertService.init();
    await monitor.start();
    TrackerPart.instance.watchMyActiveTrip();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => monitor.periodic();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await TrackerPart.instance.stopWatching();
    await monitor.stop();
  }
}
