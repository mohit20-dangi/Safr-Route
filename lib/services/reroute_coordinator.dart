import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import 'geo_utils.dart';
import 'routing_service.dart';

/// Exactly one guardian runs the routing call per reroute. The result is
/// written to trip.reroute.result; every guardian applies it from the trip
/// snapshot so they all agree.
Future<void> requestReroute(
  DocumentReference<Map<String, dynamic>> trip,
  String myUid,
  LatLng from,
  LatLng to,
) async {
  final claimed = await FirebaseFirestore.instance.runTransaction((tx) async {
    final r = (await tx.get(trip)).data()?['reroute'] as Map<String, dynamic>?;
    final at = (r?['claimedAt'] as Timestamp?)?.toDate();
    if (at != null && DateTime.now().difference(at).inSeconds < 60)
      return false;
    tx.update(trip, {
      'reroute': {
        'claimedBy': myUid,
        'claimedAt': FieldValue.serverTimestamp(),
        'result': r?['result'],
      },
    });
    return true;
  });
  if (!claimed) return; // result arrives via the trip listener

  try {
    final routes = await fetchRoutes(from, to);
    if (routes.isEmpty) throw Exception('no route');
    await trip.update({
      'reroute.result': {
        'polyline': encodePolyline(routes.first.points),
        'durationSec': routes.first.durationSec,
        'at': FieldValue.serverTimestamp(),
      },
    });
  } catch (_) {
    // Release the claim so another guardian can retry.
    await trip.update({'reroute.claimedAt': null});
  }
}

/// Only one guardian posts each alert to ntfy. True if this device won.
Future<bool> claimAlertPost(
  DocumentReference<Map<String, dynamic>> trip,
  String myUid,
  String type,
  String message, {
  Duration cooldown = const Duration(minutes: 10),
}) {
  return FirebaseFirestore.instance.runTransaction((tx) async {
    final last =
        (await tx.get(trip)).data()?['lastAlert'] as Map<String, dynamic>?;
    final ts = (last?['ts'] as Timestamp?)?.toDate();
    if (last?['type'] == type &&
        ts != null &&
        DateTime.now().difference(ts) < cooldown) {
      return false;
    }
    tx.update(trip, {
      'lastAlert': {
        'type': type,
        'message': message,
        'ts': FieldValue.serverTimestamp(),
        'by': myUid,
      },
    });
    return true;
  });
}
