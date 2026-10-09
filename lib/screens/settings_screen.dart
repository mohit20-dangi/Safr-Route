import 'package:flutter/material.dart';

import '../ui/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ThemeController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
              ],
              selected: {c.mode},
              onSelectionChanged: (s) => c.setMode(s.first),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile(
                value: c.amoled,
                onChanged: c.setAmoled,
                title: const Text('Pure black in dark mode'),
                subtitle: const Text(
                  'True black background. Saves battery on AMOLED screens.',
                ),
                secondary: const Icon(Icons.battery_saver_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
