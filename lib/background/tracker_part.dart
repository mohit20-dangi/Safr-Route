import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import 'foreground_keepalive.dart';
import '../services/trip_repository.dart';

LocationSettings trackerSettings() => Platform.isIOS
    ? AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 25,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      )
    : AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);

/// Traveler side: GPS stream -> throttled Firestore uploads.
class TrackerPart {
  TrackerPart._();
  static final instance = TrackerPart._();

  final _repo = TripRepository();
  final _battery = Battery();
  StreamSubscription<Position>? _pos;
  StreamSubscription<ServiceStatus>? _gps;
  Timer? _heartbeat;
  String? _tripId;
  Position? _last, _lastUploaded;
  DateTime? _lastUploadAt;
  bool _gpsOn = true;

  /// Called by the UI right after a trip is created. On Android the service
  /// notices the new trip by itself (we only make sure it carries the location
  /// type); on iPhone tracking runs here in the app.
  Future<void> startFromUi(String tripId, LatLng dest) async {
    if (Platform.isAndroid) {
      await ForegroundKeepAlive.start(
        'Sharing your trip with family',
        needLocation: true,
      );
    } else {
      await start(tripId, dest: dest);
    }
  }

  bool get isRunning => _tripId != null;
  String? get tripId => _tripId;

  LatLng? _dest;
  double _arriveM = Config.arriveRadiusM;

  StreamSubscription<User?>? _authSub;
  StreamSubscription? _tripSub;

  /// Android service isolate: follow my active trip by myself, so tracking
  /// survives the UI being closed and resumes after a reboot.
  void watchMyActiveTrip() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((u) {
      _tripSub?.cancel();
      _tripSub = null;
      if (u == null) {
        stop();
        return;
      }
      _tripSub = FirebaseFirestore.instance
          .collection('trips')
          .where('travelerUid', isEqualTo: u.uid)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen((snap) async {
            if (snap.docs.isEmpty) {
              if (isRunning) {
                await stop();
                _notify('SafeRoute is watching over your family');
              }
              return;
            }
            final d = snap.docs.first;
            final dd = d['destination'] as Map<String, dynamic>;
            _notify('Sharing your trip with family');
            await start(
              d.id,
              dest: LatLng(
                (dd['lat'] as num).toDouble(),
                (dd['lng'] as num).toDouble(),
              ),
            );
          }, onError: (_) {});
    });
  }

  Future<void> stopWatching() async {
    await _tripSub?.cancel();
    await _authSub?.cancel();
    _tripSub = _authSub = null;
    await stop();
  }

  void _notify(String text) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'SafeRoute',
      notificationText: text,
    );
  }

  Future<void> start(
    String tripId, {
    LatLng? dest,
    double arriveRadiusM = Config.arriveRadiusM,
  }) async {
    if (_tripId == tripId) return;
    await stop();
    _tripId = tripId;
    _dest = dest;
    _arriveM = arriveRadiusM;
    _gpsOn = await Geolocator.isLocationServiceEnabled();

    _pos = Geolocator.getPositionStream(locationSettings: trackerSettings())
        .listen(_onPosition, onError: (_) {});
    _gps = Geolocator.getServiceStatusStream().listen((s) async {
      _gpsOn = s == ServiceStatus.enabled;
      if (!_gpsOn) await _uploadLast(trail: false);
    });
    // Keeps a stationary traveler from looking "stale" to guardians.
    _heartbeat = Timer.periodic(Config.uploadEvery, (_) {
      final due =
          _lastUploadAt == null ||
          DateTime.now().difference(_lastUploadAt!) >= Config.uploadEvery;
      if (due) _uploadLast(trail: false);
    });
    try {
      _onPosition(await Geolocator.getCurrentPosition());
    } catch (_) {}
  }

  void _onPosition(Position p) {
    _last = p;
    final byTime =
        _lastUploadAt == null ||
        DateTime.now().difference(_lastUploadAt!) >= Config.uploadEvery;
    final byDist =
        _lastUploaded == null ||
        Geolocator.distanceBetween(
              _lastUploaded!.latitude,
              _lastUploaded!.longitude,
              p.latitude,
              p.longitude,
            ) >=
            Config.uploadEveryMeters;
    if (byTime || byDist) _uploadLast();
    final d = _dest;
    if (d != null &&
        Geolocator.distanceBetween(
              p.latitude,
              p.longitude,
              d.latitude,
              d.longitude,
            ) <=
            _arriveM) {
      _arrive();
    }
  }

  Future<void> _arrive() async {
    final id = _tripId;
    if (id == null) return;
    await _uploadLast(); // final position so guardians see the arrival
    await stop();
    try {
      await _repo.endTrip(id);
    } catch (_) {}
  }

  Future<void> _uploadLast({bool trail = true}) async {
    final p = _last, id = _tripId;
    if (p == null || id == null) return;
    int? level;
    try {
      level = await _battery.batteryLevel;
    } catch (_) {}
    _lastUploadAt = DateTime.now();
    if (trail) _lastUploaded = p;
    try {
      await _repo.uploadLocation(
        id,
        lat: p.latitude,
        lng: p.longitude,
        speed: p.speed,
        accuracy: p.accuracy,
        battery: level,
        locationEnabled: _gpsOn,
        appendTrail: trail,
      );
    } catch (_) {
      // Offline or quota hit: the next tick retries.
    }
  }

  Future<void> stop() async {
    _heartbeat?.cancel();
    await _pos?.cancel();
    await _gps?.cancel();
    _heartbeat = _pos = _gps = null;
    _tripId = null;
    _last = _lastUploaded = null;
    _lastUploadAt = null;
  }
}
