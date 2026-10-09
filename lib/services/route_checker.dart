import 'package:latlong2/latlong.dart';

import 'geo_utils.dart';

enum TripState { onRoute, checking, offRoute, stopped, arrived }

enum AlertType {
  offRoute,
  wrongDirection,
  stoppedOffRoute,
  stale,
  lowBattery,
  locationOff,
  arrived,
}

class CheckerSettings {
  final double corridorM, arriveRadiusM, wrongDirMarginM;
  final int missesBeforeReroute, lowBatteryPct;
  final Duration rerouteTolerance,
      stopAlert,
      staleAlert,
      wrongDirAlert,
      cooldown;

  const CheckerSettings({
    this.corridorM = 300,
    this.arriveRadiusM = 50,
    this.wrongDirMarginM = 300,
    this.missesBeforeReroute = 2,
    this.lowBatteryPct = 15,
    this.rerouteTolerance = const Duration(minutes: 15),
    this.stopAlert = const Duration(minutes: 10),
    this.staleAlert = const Duration(minutes: 5),
    this.wrongDirAlert = const Duration(minutes: 5),
    this.cooldown = const Duration(minutes: 10),
  });

  factory CheckerSettings.fromMap(Map<String, dynamic> m) => CheckerSettings(
    corridorM: (m['corridorM'] ?? 300).toDouble(),
    lowBatteryPct: m['lowBatteryPct'] ?? 15,
    rerouteTolerance: Duration(minutes: m['rerouteToleranceMin'] ?? 15),
    stopAlert: Duration(minutes: m['stopAlertMin'] ?? 10),
    staleAlert: Duration(minutes: m['staleAlertMin'] ?? 5),
  );
}

class LocationSample {
  final LatLng pos;
  final DateTime ts;
  final double speed; // m/s; negative = unknown (iOS reports -1)
  final int? battery; // %
  final bool locationEnabled;
  const LocationSample(
    this.pos,
    this.ts, {
    this.speed = 0,
    this.battery,
    this.locationEnabled = true,
  });
}

class Alert {
  final AlertType type;
  final String message;
  const Alert(this.type, this.message);
  @override
  String toString() => '$type: $message';
}

class CheckResult {
  final TripState state;
  final List<Alert> alerts;
  final bool needsReroute; // caller should run the reroute coordinator
  final double distToDestM;
  const CheckResult(
    this.state,
    this.alerts, {
    this.needsReroute = false,
    this.distToDestM = 0,
  });
}

class RouteChecker {
  RouteChecker({
    required List<List<LatLng>> routes,
    required this.destination,
    required this.baselineEtaSec,
    required this.startedAt,
    this.settings = const CheckerSettings(),
  }) : _routes = [...routes],
       _lastSampleAt = startedAt;

  final LatLng destination;
  double baselineEtaSec;
  final DateTime startedAt;
  final CheckerSettings settings;

  final List<List<LatLng>> _routes;
  final _dist = const Distance();

  TripState _state = TripState.onRoute;
  int _misses = 0;
  bool _rerouteInFlight = false;
  DateTime? _stoppedSince;
  double? _minDistToDest;
  DateTime? _minDistAt;
  DateTime _lastSampleAt;
  bool _lowBatteryAlerted = false;
  final Map<AlertType, DateTime> _lastAlertAt = {};

  TripState get state => _state;
  List<List<LatLng>> get routes => List.unmodifiable(_routes);

  /// Call on every new location from Firestore.
  CheckResult onSample(LocationSample s, {DateTime? ackUntil}) {
    final alerts = <Alert>[];
    _lastSampleAt = s.ts;
    if (_state == TripState.arrived) return CheckResult(_state, alerts);

    if (!s.locationEnabled) {
      _maybe(
        alerts,
        AlertType.locationOff,
        'Location was turned off',
        s.ts,
        ackUntil,
      );
      return CheckResult(_state, alerts);
    }

    final d = _dist(s.pos, destination);

    // Arrival
    if (d <= settings.arriveRadiusM) {
      _state = TripState.arrived;
      alerts.add(const Alert(AlertType.arrived, 'Arrived safely'));
      return CheckResult(_state, alerts, distToDestM: d);
    }

    // Low battery (once per trip, not silenced by ack)
    if (s.battery != null &&
        s.battery! < settings.lowBatteryPct &&
        !_lowBatteryAlerted) {
      _lowBatteryAlerted = true;
      alerts.add(Alert(AlertType.lowBattery, 'Phone battery at ${s.battery}%'));
    }

    // Wrong direction: no progress + moving away for a while
    if (_minDistToDest == null || d < _minDistToDest!) {
      _minDistToDest = d;
      _minDistAt = s.ts;
    } else if (d > _minDistToDest! + settings.wrongDirMarginM &&
        s.ts.difference(_minDistAt!) >= settings.wrongDirAlert) {
      _maybe(
        alerts,
        AlertType.wrongDirection,
        'Moving away from destination '
        '(${(d / 1000).toStringAsFixed(1)} km away)',
        s.ts,
        ackUntil,
      );
    }

    // Corridor check
    final onRoute = _routes.any(
      (r) => distanceToRoute(s.pos, r) <= settings.corridorM,
    );
    var needsReroute = false;

    if (onRoute) {
      _misses = 0;
      _stoppedSince = null;
      _state = TripState.onRoute;
    } else {
      _misses++;

      // Stopped off-route (negative speed = unknown, not stopped)
      if (s.speed >= 0 && s.speed < 1) {
        _stoppedSince ??= s.ts;
        final stoppedFor = s.ts.difference(_stoppedSince!);
        if (stoppedFor >= settings.stopAlert) {
          _state = TripState.stopped;
          _maybe(
            alerts,
            AlertType.stoppedOffRoute,
            'Stopped off route for ${stoppedFor.inMinutes} min',
            s.ts,
            ackUntil,
          );
        }
      } else {
        _stoppedSince = null;
      }

      if (_misses >= settings.missesBeforeReroute && !_rerouteInFlight) {
        _rerouteInFlight = true;
        needsReroute = true;
        if (_state == TripState.onRoute) _state = TripState.checking;
      }
    }

    return CheckResult(
      _state,
      alerts,
      needsReroute: needsReroute,
      distToDestM: d,
    );
  }

  /// Feed the shared reroute result (same data on every guardian).
  CheckResult onRerouteResult({
    required List<LatLng> points,
    required double newEtaSec,
    required DateTime now,
    DateTime? ackUntil,
  }) {
    _rerouteInFlight = false;
    final alerts = <Alert>[];
    final elapsed = now.difference(startedAt).inSeconds;
    final limit = baselineEtaSec + settings.rerouteTolerance.inSeconds;
    if (elapsed + newEtaSec <= limit) {
      _routes.add(points);
      _misses = 0;
      _state = TripState.onRoute;
    } else {
      _state = TripState.offRoute;
      final lateMin = ((elapsed + newEtaSec - baselineEtaSec) / 60).round();
      _maybe(
        alerts,
        AlertType.offRoute,
        'Off route - about $lateMin min later than planned',
        now,
        ackUntil,
      );
    }
    return CheckResult(_state, alerts);
  }

  /// The traveler switched route mid-trip: new valid routes and a new
  /// baseline (elapsed time + new route duration).
  void replaceRoutes(List<List<LatLng>> routes, double newBaselineEtaSec) {
    _routes
      ..clear()
      ..addAll(routes);
    baselineEtaSec = newBaselineEtaSec;
    _misses = 0;
    _rerouteInFlight = false;
    _stoppedSince = null;
    if (_state != TripState.arrived) _state = TripState.onRoute;
  }

  /// ORS failed; allow another attempt on the next off-route sample.
  void onRerouteFailed() => _rerouteInFlight = false;

  /// Call every minute for time-based checks (stale updates).
  List<Alert> periodic(DateTime now, {DateTime? ackUntil}) {
    final alerts = <Alert>[];
    if (_state == TripState.arrived) return alerts;
    final age = now.difference(_lastSampleAt);
    if (age >= settings.staleAlert) {
      _maybe(
        alerts,
        AlertType.stale,
        'No location update for ${age.inMinutes} min',
        now,
        ackUntil,
      );
    }
    return alerts;
  }

  void _maybe(
    List<Alert> out,
    AlertType type,
    String msg,
    DateTime now,
    DateTime? ackUntil,
  ) {
    if (ackUntil != null && now.isBefore(ackUntil)) return;
    final last = _lastAlertAt[type];
    if (last != null && now.difference(last) < settings.cooldown) return;
    _lastAlertAt[type] = now;
    out.add(Alert(type, msg));
  }
}
