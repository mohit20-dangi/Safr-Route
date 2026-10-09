import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/alert_service.dart';
import 'alert_history_screen.dart';

class PermissionsSetupScreen extends StatefulWidget {
  const PermissionsSetupScreen({super.key});
  @override
  State<PermissionsSetupScreen> createState() => _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends State<PermissionsSetupScreen>
    with WidgetsBindingObserver {
  final _items = <_Item>[
    _Item(
      'Location (while using)',
      Permission.locationWhenInUse,
      'Needed to show your position during a trip.',
    ),
    _Item(
      'Location (all the time)',
      Permission.locationAlways,
      'Needed so tracking continues when the screen is off. Choose "Allow all the time".',
    ),
    _Item(
      'Notifications',
      Permission.notification,
      'Needed for the tracking notification and alerts.',
    ),
    _Item(
      'Battery optimization off',
      Permission.ignoreBatteryOptimizations,
      'Stops the phone from killing the app in the background.',
    ),
  ];
  Map<Permission, bool> _ok = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final r = <Permission, bool>{};
    for (final i in _items) {
      r[i.perm] = await i.perm.isGranted;
    }
    if (mounted) setState(() => _ok = r);
  }

  Future<void> _grant(_Item i) async {
    // "Always" only works after "while using" has been granted.
    if (i.perm == Permission.locationAlways &&
        !(await Permission.locationWhenInUse.isGranted)) {
      await Permission.locationWhenInUse.request();
    }
    final s = await i.perm.request();
    if (s.isPermanentlyDenied ||
        (i.perm == Permission.locationAlways && !s.isGranted)) {
      await openAppSettings();
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        children: [
          for (final i in _items)
            ListTile(
              leading: Text(
                _ok[i.perm] == true ? '✅' : '❌',
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(i.title),
              subtitle: Text(i.why),
              trailing: _ok[i.perm] == true
                  ? null
                  : TextButton(
                      onPressed: () => _grant(i),
                      child: const Text('Allow'),
                    ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.campaign),
            title: const Text('Send test alert'),
            subtitle: const Text(
              'Plays the alert siren, like a real off-route alert',
            ),
            onTap: () => AlertService.alarm(
              'Test alert',
              'This is how a SafeRoute alert sounds.',
              0,
              0,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Recent alerts'),
            subtitle: const Text('Why did a siren go off?'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertHistoryScreen()),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Xiaomi / Vivo / Oppo / Realme / Samsung'),
            subtitle: Text(
              'These phones kill background apps. Turn on Autostart and set battery to "No restrictions" for SafeRoute, and lock the app in recents.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Step-by-step for your phone brand'),
            subtitle: const Text('dontkillmyapp.com'),
            onTap: () => launchUrl(
              Uri.parse('https://dontkillmyapp.com'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String title, why;
  final Permission perm;
  _Item(this.title, this.perm, this.why);
}
