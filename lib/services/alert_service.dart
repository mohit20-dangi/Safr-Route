import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Local alarm notifications (Android guardians) + ntfy posts (iPhone guardians).
class AlertService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nextId = 100;

  // Channel sound settings are fixed once created; change the id to change them.
  static const _channelId = 'route_alerts_v2';
  static const _sound = RawResourceAndroidNotificationSound('alert_siren');

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) {
        final url = r.payload;
        if (url != null && url.startsWith('http')) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.deleteNotificationChannel(channelId: 'route_alerts_v1');
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Route alerts',
        importance: Importance.max,
        playSound: true,
        sound: _sound,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    _ready = true;
  }

  /// Last alerts, kept on the device so you can see why a siren went off.
  static Future<void> _remember(String title, String body) async {
    debugPrint('SAFEROUTE ALERT: $title - $body');
    try {
      final p = await SharedPreferences.getInstance();
      await p
          .reload(); // the service isolate and the UI isolate share this file
      final log = p.getStringList('alertLog') ?? [];
      log.insert(0, '${DateTime.now().toIso8601String()}|$title|$body');
      await p.setStringList('alertLog', log.take(30).toList());
    } catch (_) {}
  }

  static Future<List<({DateTime at, String title, String body})>>
  history() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return [
      for (final e in p.getStringList('alertLog') ?? [])
        (
          at: DateTime.tryParse(e.split('|').first) ?? DateTime.now(),
          title: e.split('|').length > 1 ? e.split('|')[1] : '',
          body: e.split('|').length > 2
              ? e.split('|').sublist(2).join('|')
              : '',
        ),
    ];
  }

  static Future<void> alarm(
    String title,
    String body,
    double lat,
    double lng, {
    bool urgent = true,
  }) async {
    await _remember(title, body);
    await init();
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Route alerts',
          importance: urgent ? Importance.max : Importance.defaultImportance,
          priority: urgent ? Priority.high : Priority.defaultPriority,
          category: urgent ? AndroidNotificationCategory.alarm : null,
          fullScreenIntent: urgent,
          playSound: true,
          sound: _sound,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 800]),
          // 4 = FLAG_INSISTENT: repeat the siren until the alert is dismissed.
          additionalFlags: urgent ? Int32List.fromList([4]) : null,
          ongoing: false,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      ),
      payload: 'https://maps.google.com/?q=$lat,$lng',
    );
  }

  /// Topics are public to anyone who guesses the name, so keep messages short.
  static Future<void> postNtfy(
    String topic,
    String title,
    String msg,
    double lat,
    double lng,
  ) async {
    try {
      await http.post(
        Uri.parse('https://ntfy.sh/$topic'),
        headers: {
          'Title': title,
          'Priority': 'urgent',
          'Tags': 'warning',
          'Click': 'https://maps.google.com/?q=$lat,$lng',
        },
        body: msg,
      );
    } catch (_) {}
  }
}
