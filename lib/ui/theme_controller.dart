import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance settings, saved on the device.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final instance = ThemeController._();

  ThemeMode mode = ThemeMode.system;
  bool amoled = true; // pure black in dark mode (saves battery on OLED screens)

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == p.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );
      amoled = p.getBool('amoled') ?? true;
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('themeMode', m.name);
  }

  Future<void> setAmoled(bool v) async {
    amoled = v;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool('amoled', v);
  }
}
