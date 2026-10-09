import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import 'geo_utils.dart';
import 'routing_service.dart';

class TripRepository {
  final _db = FirebaseFirestore.instance;
  User get _user => FirebaseAuth.instance.currentUser!;
  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');

  Future<String> startTrip({
    required String groupId,
    required String destName,
    required LatLng dest,
    required List<RouteOption> routes,
    required double baselineEtaSec,
  }) async {
    final ref = _trips.doc();
    await ref.set({
      'groupId': groupId,
      'travelerUid': _user.uid,
      'travelerName': _user.displayName ?? _user.email ?? 'Traveler',
      'status': 'active',
      'destination': {
        'lat': dest.latitude,
        'lng': dest.longitude,
        'name': destName,
      },
      'startedAt': FieldValue.serverTimestamp(),
      'baselineEtaSec': baselineEtaSec,
      'routes': [
        for (final r in routes)
          {
            'polyline': encodePolyline(r.points),
            'distanceM': r.distanceM,
            'durationSec': r.durationSec,
          },
      ],
      'routesRev': 0,
      'trail': [],
    });
    return ref.id;
  }

  /// One write: lastLocation + trail append.
  Future<void> uploadLocation(
    String tripId, {
    required double lat,
    required double lng,
    required double speed,
    required double accuracy,
    required int? battery,
    required bool locationEnabled,
    bool appendTrail = true,
  }) {
    final now = Timestamp.now();
    return _trips.doc(tripId).update({
      'lastLocation': {
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'accuracy': accuracy,
        'ts': now,
        'battery': battery,
        'locationEnabled': locationEnabled,
      },
      if (appendTrail)
        'trail': FieldValue.arrayUnion([
          {'lat': lat, 'lng': lng, 'ts': now},
        ]),
    });
  }

  /// Traveler switched road mid-trip. Watchers rebuild their checker when
  /// routesRev changes.
  Future<void> changeRoutes(
    String tripId, {
    required List<RouteOption> routes,
    required double baselineEtaSec,
  }) {
    return _trips.doc(tripId).update({
      'routes': [
        for (final r in routes)
          {
            'polyline': encodePolyline(r.points),
            'distanceM': r.distanceM,
            'durationSec': r.durationSec,
          },
      ],
      'baselineEtaSec': baselineEtaSec,
      'routesRev': FieldValue.increment(1),
      'reroute': FieldValue.delete(),
    });
  }

  Future<void> endTrip(String tripId) => _trips.doc(tripId).update({
    'status': 'ended',
    'endedAt': FieldValue.serverTimestamp(),
  });

  Future<void> ackFine(String tripId, {int minutes = 5}) =>
      _trips.doc(tripId).update({
        'ackUntil': Timestamp.fromDate(
          DateTime.now().add(Duration(minutes: minutes)),
        ),
      });

  /// My currently active trip, if any.
  Stream<QueryDocumentSnapshot<Map<String, dynamic>>?> myActiveTrip() => _trips
      .where('travelerUid', isEqualTo: _user.uid)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : s.docs.first);

  /// 7-day cleanup (no Cloud Functions). Needs the composite index.
  Future<void> cleanupOldTrips({int keepDays = Config.keepTripsDays}) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(Duration(days: keepDays)),
    );
    final old = await _trips
        .where('travelerUid', isEqualTo: _user.uid)
        .where('status', isEqualTo: 'ended')
        .where('endedAt', isLessThan: cutoff)
        .get();
    if (old.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in old.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}

/// A route the traveler normally takes. Accepted as valid on future trips to
/// the same destination.
class SavedRoutes {
  SavedRoutes(this.groupId);
  final String groupId;
  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('groups')
      .doc(groupId)
      .collection('savedRoutes');
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> save({
    required String destName,
    required LatLng dest,
    required List<LatLng> points,
  }) {
    // Thin out the trail (keep a point every ~60 m) to keep the doc small.
    final kept = <LatLng>[];
    for (final p in points) {
      if (kept.isEmpty || const Distance()(kept.last, p) >= 60) kept.add(p);
    }
    if (points.isNotEmpty && kept.last != points.last) kept.add(points.last);
    return _col.add({
      'ownerUid': _uid,
      'destName': destName,
      'destLat': dest.latitude,
      'destLng': dest.longitude,
      'polyline': encodePolyline(kept),
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  /// My saved routes ending within 500 m of [dest].
  Future<List<({String id, List<LatLng> points, String label})>> forDestination(
    LatLng dest,
  ) async {
    final snap = await _col.where('ownerUid', isEqualTo: _uid).get();
    final out = <({String id, List<LatLng> points, String label})>[];
    for (final d in snap.docs) {
      final m = d.data();
      final p = LatLng(
        (m['destLat'] as num).toDouble(),
        (m['destLng'] as num).toDouble(),
      );
      if (const Distance()(p, dest) <= 500) {
        final at = (m['savedAt'] as Timestamp?)?.toDate();
        out.add((
          id: d.id,
          points: decodePolyline(m['polyline'] as String),
          label:
              'My usual route${at != null ? ' (saved ${at.day}/${at.month})' : ''}',
        ));
      }
    }
    return out;
  }
}
