import 'dart:math';

import 'package:latlong2/latlong.dart';

double _distToSegment(LatLng p, LatLng a, LatLng b) {
  const r = 6371000.0;
  final cosLat = cos(p.latitude * pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * pi / 180 * r * cosLat;
  double y(LatLng q) => (q.latitude - p.latitude) * pi / 180 * r;
  final ax = x(a), ay = y(a), bx = x(b), by = y(b);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  var t = len2 == 0 ? 0.0 : (-ax * dx - ay * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return sqrt(cx * cx + cy * cy);
}

double distanceToRoute(LatLng p, List<LatLng> route) {
  if (route.length == 1) return const Distance()(p, route.first);
  var best = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    best = min(best, _distToSegment(p, route[i], route[i + 1]));
  }
  return best;
}

bool isOnAnyRoute(
  LatLng p,
  List<List<LatLng>> routes, {
  double thresholdM = 300,
}) => routes.any((r) => distanceToRoute(p, r) <= thresholdM);

List<LatLng> decodePolyline(String s) {
  final pts = <LatLng>[];
  var i = 0, lat = 0, lng = 0;
  while (i < s.length) {
    for (var k = 0; k < 2; k++) {
      var shift = 0, result = 0, b = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final d = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (k == 0) {
        lat += d;
      } else {
        lng += d;
      }
    }
    pts.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return pts;
}

String encodePolyline(List<LatLng> pts) {
  final sb = StringBuffer();
  var pLat = 0, pLng = 0;
  void enc(int v) {
    v = v < 0 ? ~(v << 1) : (v << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  for (final p in pts) {
    final lat = (p.latitude * 1e5).round(), lng = (p.longitude * 1e5).round();
    enc(lat - pLat);
    enc(lng - pLng);
    pLat = lat;
    pLng = lng;
  }
  return sb.toString();
}
