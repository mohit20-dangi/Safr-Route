import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';

class RouteOption {
  final List<LatLng> points;
  final double distanceM, durationSec;
  const RouteOption({
    required this.points,
    required this.distanceM,
    required this.durationSec,
  });
}

/// Driving routes with alternatives. Uses OpenRouteService when a key is set,
/// and falls back to the public OSRM server if ORS is down or has no key.
Future<List<RouteOption>> fetchRoutes(
  LatLng from,
  LatLng to, {
  List<LatLng> via = const [],
}) async {
  if (Config.orsKey != 'PASTE_ORS_KEY') {
    try {
      return await _fetchOrs(from, to, via);
    } catch (_) {
      // fall through to OSRM
    }
  }
  return _fetchOsrm(from, to, via);
}

Future<List<RouteOption>> _fetchOsrm(
  LatLng from,
  LatLng to,
  List<LatLng> via,
) async {
  final coords = [
    from,
    ...via,
    to,
  ].map((p) => '${p.longitude},${p.latitude}').join(';');
  // Alternatives only make sense between two points.
  final url =
      'https://router.project-osrm.org/route/v1/driving/$coords'
      '?alternatives=${via.isEmpty ? 3 : 0}&overview=full&geometries=geojson';
  final res = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 25));
  if (res.statusCode != 200) {
    throw Exception('OSRM ${res.statusCode}: ${res.body}');
  }
  final routes = jsonDecode(res.body)['routes'] as List? ?? [];
  return routes
      .map(
        (r) => RouteOption(
          points: (r['geometry']['coordinates'] as List)
              .map<LatLng>((c) => LatLng(c[1], c[0]))
              .toList(),
          distanceM: (r['distance'] as num).toDouble(),
          durationSec: (r['duration'] as num).toDouble(),
        ),
      )
      .toList();
}

Future<List<RouteOption>> _fetchOrs(
  LatLng from,
  LatLng to,
  List<LatLng> via,
) async {
  Future<http.Response> call(bool alternatives) => http.post(
    Uri.parse(
      'https://api.openrouteservice.org/v2/directions/driving-car/geojson',
    ),
    headers: {
      'Authorization': Config.orsKey,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'coordinates': [
        for (final p in [from, ...via, to])
          [p.longitude, p.latitude], // ORS uses [lng, lat]
      ],
      if (alternatives && via.isEmpty)
        'alternative_routes': {
          'target_count': 3,
          'weight_factor': 1.6,
          'share_factor': 0.6,
        },
    }),
  );

  var res = await call(true);
  // Alternatives are rejected for long trips; fall back to the single route.
  if (res.statusCode == 400) res = await call(false);
  if (res.statusCode != 200) {
    throw Exception('ORS ${res.statusCode}: ${res.body}');
  }
  return (jsonDecode(res.body)['features'] as List)
      .map(
        (f) => RouteOption(
          points: (f['geometry']['coordinates'] as List)
              .map<LatLng>((c) => LatLng(c[1], c[0]))
              .toList(),
          distanceM: (f['properties']['summary']['distance'] as num).toDouble(),
          durationSec: (f['properties']['summary']['duration'] as num)
              .toDouble(),
        ),
      )
      .toList();
}
