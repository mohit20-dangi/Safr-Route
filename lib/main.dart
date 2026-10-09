import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/theme.dart';
import 'ui/theme_controller.dart';

import 'package:permission_handler/permission_handler.dart';

import 'background/foreground_keepalive.dart';
import 'firebase_options.dart';
import 'screens/groups_home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ForegroundKeepAlive.init();
  await ThemeController.instance.load();
  String? initError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    initError = e.toString();
  }
  runApp(SafeRouteApp(initError: initError));
}

class SafeRouteApp extends StatelessWidget {
  const SafeRouteApp({super.key, this.initError});
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'SafeRoute',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(amoled: ThemeController.instance.amoled),
        themeMode: ThemeController.instance.mode,
        // Android 15 draws edge-to-edge: keep content above the navigation bar.
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: Theme.of(context)
                  .scaffoldBackgroundColor,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(top: false, child: child!),
            ),
          );
        },
        home: initError != null
            ? _SetupNeeded(initError!)
            : StreamBuilder<User?>(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return snap.data == null
                      ? const LoginScreen()
                      : const _Authed();
                },
              ),
      ),
    );
  }
}

class _SetupNeeded extends StatelessWidget {
  const _SetupNeeded(this.error);
  final String error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Firebase is not configured yet.\nRun `flutterfire configure` in the project folder.\n\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

/// Logged-in shell: starts the Android guardian monitor service.
class _Authed extends StatefulWidget {
  const _Authed();
  @override
  State<_Authed> createState() => _AuthedState();
}

class _AuthedState extends State<_Authed> {
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _startService();
  }

  Future<void> _startService() async {
    await Permission.notification.request();
    await ForegroundKeepAlive.start('SafeRoute is watching over your family');
  }

  @override
  Widget build(BuildContext context) => GroupsHomeScreen();
}
