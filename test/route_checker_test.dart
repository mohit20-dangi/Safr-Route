import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/services/geo_utils.dart';
import 'package:saferoute/services/route_checker.dart';

final start = LatLng(28.6000, 77.2000);
final dest = LatLng(28.6500, 77.2000); // ~5.5 km north
final t0 = DateTime(2026, 1, 1, 16, 0);
DateTime at(int min) => t0.add(Duration(minutes: min));

List<LatLng> line(LatLng a, LatLng b, int n) => List.generate(
    n + 1,
    (i) => LatLng(a.latitude + (b.latitude - a.latitude) * i / n,
        a.longitude + (b.longitude - a.longitude) * i / n));

RouteChecker make() => RouteChecker(
      routes: [line(start, dest, 50)],
      destination: dest,
      baselineEtaSec: 15 * 60,
      startedAt: t0,
    );

LocationSample s(double lat, double lng, int min,
        {double speed = 10, int? battery, bool gps = true}) =>
    LocationSample(LatLng(lat, lng), at(min),
        speed: speed, battery: battery, locationEnabled: gps);

void main() {
  test('polyline round trip', () {
    final pts = line(start, dest, 20);
    final back = decodePolyline(encodePolyline(pts));
    expect(back.length, pts.length);
    for (var i = 0; i < pts.length; i++) {
      expect(back[i].latitude, closeTo(pts[i].latitude, 1e-5));
      expect(back[i].longitude, closeTo(pts[i].longitude, 1e-5));
    }
  });

  test('on route → no alerts', () {
    final c = make();
    for (var i = 0; i <= 10; i++) {
      final r = c.onSample(s(28.600 + i * 0.004, 77.2, i));
      expect(r.alerts, isEmpty);
      expect(r.state, TripState.onRoute);
    }
  });

  test('single GPS jump → no reroute', () {
    final c = make();
    c.onSample(s(28.61, 77.2, 1));
    final jump = c.onSample(s(28.62, 77.21, 2)); // ~1 km east
    expect(jump.needsReroute, isFalse);
    final back = c.onSample(s(28.63, 77.2, 3));
    expect(back.state, TripState.onRoute);
  });

  test('alternate road within tolerance → accepted silently', () {
    final c = make();
    c.onSample(s(28.62, 77.21, 2));
    final r = c.onSample(s(28.621, 77.21, 3));
    expect(r.needsReroute, isTrue);
    final res = c.onRerouteResult(
        points: line(LatLng(28.62, 77.21), dest, 20),
        newEtaSec: 8 * 60,
        now: at(3));
    expect(res.alerts, isEmpty);
    expect(c.routes.length, 2);
    final next = c.onSample(s(28.63, 77.205, 5));
    expect(next.state, TripState.onRoute);
  });

  test('big delay after reroute → offRoute alert', () {
    final c = make();
    c.onSample(s(28.62, 77.21, 2));
    c.onSample(s(28.621, 77.21, 3));
    final res = c.onRerouteResult(
        points: line(LatLng(28.62, 77.21), dest, 20),
        newEtaSec: 30 * 60,
        now: at(3));
    expect(res.state, TripState.offRoute);
    expect(res.alerts.single.type, AlertType.offRoute);
  });

  test('moving away for 5+ min → wrongDirection', () {
    final c = make();
    c.onSample(s(28.60, 77.2, 0));
    c.onSample(s(28.62, 77.2, 2)); // closest point
    expect(c.onSample(s(28.61, 77.2, 5)).alerts, isEmpty); // only 3 min
    final r = c.onSample(s(28.60, 77.2, 8));
    expect(r.alerts.map((a) => a.type), contains(AlertType.wrongDirection));
  });

  test('stopped off route 10+ min → alert', () {
    final c = make();
    final all = <Alert>[];
    for (var m = 1; m <= 12; m++) {
      all.addAll(c.onSample(s(28.62, 77.21, m, speed: 0)).alerts);
    }
    expect(all.map((a) => a.type), contains(AlertType.stoppedOffRoute));
  });

  test('unknown speed (-1) is not treated as stopped', () {
    final c = make();
    final all = <Alert>[];
    for (var m = 1; m <= 12; m++) {
      all.addAll(c.onSample(s(28.62, 77.21, m, speed: -1)).alerts);
    }
    expect(all.map((a) => a.type), isNot(contains(AlertType.stoppedOffRoute)));
  });

  test('stale updates → alert, with cooldown', () {
    final c = make();
    c.onSample(s(28.61, 77.2, 0));
    expect(c.periodic(at(3)), isEmpty);
    expect(c.periodic(at(6)).single.type, AlertType.stale);
    expect(c.periodic(at(10)), isEmpty); // cooldown
    expect(c.periodic(at(17)).single.type, AlertType.stale);
  });

  test('"I\'m fine" silences alerts', () {
    final c = make();
    c.onSample(s(28.61, 77.2, 0));
    expect(c.periodic(at(6), ackUntil: at(20)), isEmpty);
  });

  test('GPS off → locationOff alert', () {
    final c = make();
    final r = c.onSample(s(28.61, 77.2, 1, gps: false));
    expect(r.alerts.single.type, AlertType.locationOff);
  });

  test('low battery alerts once', () {
    final c = make();
    expect(c.onSample(s(28.61, 77.2, 1, battery: 10)).alerts.single.type,
        AlertType.lowBattery);
    expect(c.onSample(s(28.62, 77.2, 2, battery: 9)).alerts, isEmpty);
  });

  test('arrival ends trip', () {
    final c = make();
    final r = c.onSample(s(28.6497, 77.2, 14));
    expect(r.state, TripState.arrived);
    expect(r.alerts.single.type, AlertType.arrived);
    expect(c.periodic(at(30)), isEmpty);
  });

  test('switching route mid-trip makes the new road valid', () {
    final c = make();
    c.onSample(s(28.62, 77.21, 2));
    expect(c.onSample(s(28.621, 77.21, 3)).needsReroute, isTrue);
    c.replaceRoutes([line(LatLng(28.62, 77.21), dest, 20)], 20 * 60);
    final r = c.onSample(s(28.63, 77.205, 5));
    expect(r.state, TripState.onRoute);
    expect(r.alerts, isEmpty);
  });
}
