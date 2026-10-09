import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

import '../services/alert_service.dart';
import '../services/geo_utils.dart';
import '../services/reroute_coordinator.dart';
import '../services/route_checker.dart';

class _Trip {
  _Trip(this.ref, this.groupId, this.checker, this.travelerName, this.dest);
  final DocumentReference<Map<String, dynamic>> ref;
  final String groupId, travelerName;
  final RouteChecker checker;
  final LatLng dest;
  DateTime? ackUntil;
  DateTime? lastTs, rerouteRaisedAt, seenResultAt;
  int rev = 0;
  LatLng? lastPos;
}

/// Guardian side. Runs inside the Android foreground service isolate:
/// one live listener per group, one RouteChecker per active trip.
class MonitorPart {
  StreamSubscription<User?>? _auth;
  StreamSubscription? _user;
  final _members = <String, StreamSubscription>{};
  final _trips = <String, StreamSubscription>{};
  final _groups = <String, Map<String, dynamic>>{};
  final _active = <String, _Trip>{};
  String? _uid;

  Future<void> start() async {
    _auth = FirebaseAuth.instance.authStateChanges().listen((u) {
      _stopListeners();
      if (u != null) _begin(u.uid);
    });
  }

  void _begin(String uid) {
    _uid = uid;
    final db = FirebaseFirestore.instance;
    _user = db.collection('users').doc(uid).snapshots().listen((s) {
      final ids = List<String>.from(s.data()?['groupIds'] ?? []);
      for (final g in ids) {
        _members[g] ??= db
            .collection('groups')
            .doc(g)
            .collection('members')
            .doc(uid)
            .snapshots()
            .listen((m) {
              if (m.data()?['status'] == 'active') {
                _watchGroup(g);
              } else {
                _unwatchGroup(g);
              }
            }, onError: (_) {});
      }
      for (final g in _members.keys.toList()) {
        if (!ids.contains(g)) {
          _members.remove(g)?.cancel();
          _unwatchGroup(g);
        }
      }
    }, onError: (_) {});
  }

  Future<void> _watchGroup(String g) async {
    if (_trips.containsKey(g)) return;
    final db = FirebaseFirestore.instance;
    try {
      final gd = await db.collection('groups').doc(g).get();
      _groups[g] = gd.data() ?? {};
    } catch (_) {
      return;
    }
    if (_trips.containsKey(g)) return;
    _trips[g] = db
        .collection('trips')
        .where('groupId', isEqualTo: g)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snap) {
          for (final c in snap.docChanges) {
            if (c.type == DocumentChangeType.removed) {
              _active.remove(c.doc.id);
            } else {
              _onTrip(g, c.doc);
            }
          }
        }, onError: (_) {});
  }

  void _unwatchGroup(String g) {
    _trips.remove(g)?.cancel();
    _groups.remove(g);
    _active.removeWhere((_, t) => t.groupId == g);
  }

  void _onTrip(String g, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null || d['travelerUid'] == _uid)
      return; // don't alert on my own trip

    var t = _active[doc.id];
    if (t == null) {
      final dest = d['destination'] as Map<String, dynamic>;
      t = _Trip(
        doc.reference,
        g,
        RouteChecker(
          routes: [
            for (final r in (d['routes'] as List? ?? []))
              decodePolyline(r['polyline'] as String),
          ],
          destination: LatLng(
            (dest['lat'] as num).toDouble(),
            (dest['lng'] as num).toDouble(),
          ),
          baselineEtaSec: (d['baselineEtaSec'] as num).toDouble(),
          startedAt: (d['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          settings: CheckerSettings.fromMap(
            Map<String, dynamic>.from(_groups[g]?['settings'] ?? {}),
          ),
        ),
        d['travelerName'] ?? 'Someone',
        LatLng(
          (dest['lat'] as num).toDouble(),
          (dest['lng'] as num).toDouble(),
        ),
      );
      t.seenResultAt = _resultAt(d);
      t.rev = (d['routesRev'] as num?)?.toInt() ?? 0;
      _active[doc.id] = t;
    }

    // Traveler switched route mid-trip.
    final rev = (d['routesRev'] as num?)?.toInt() ?? 0;
    if (rev != t.rev) {
      t.rev = rev;
      t.rerouteRaisedAt = null;
      t.seenResultAt = _resultAt(d);
      t.checker.replaceRoutes([
        for (final r in (d['routes'] as List? ?? []))
          decodePolyline(r['polyline'] as String),
      ], (d['baselineEtaSec'] as num).toDouble());
    }
    t.ackUntil = (d['ackUntil'] as Timestamp?)?.toDate();

    // Shared reroute result (same data on every guardian).
    final resAt = _resultAt(d);
    if (resAt != null && resAt != t.seenResultAt) {
      t.seenResultAt = resAt;
      if (t.rerouteRaisedAt != null) {
        final res = d['reroute']['result'] as Map<String, dynamic>;
        t.rerouteRaisedAt = null;
        final r = t.checker.onRerouteResult(
          points: decodePolyline(res['polyline']),
          newEtaSec: (res['durationSec'] as num).toDouble(),
          now: DateTime.now(),
          ackUntil: t.ackUntil,
        );
        _raise(t, r.alerts);
      }
    }

    final l = d['lastLocation'] as Map<String, dynamic>?;
    final ts = (l?['ts'] as Timestamp?)?.toDate();
    if (l == null || ts == null || ts == t.lastTs) return;
    t.lastTs = ts;
    final pos = LatLng(
      (l['lat'] as num).toDouble(),
      (l['lng'] as num).toDouble(),
    );
    t.lastPos = pos;
    final r = t.checker.onSample(
      LocationSample(
        pos,
        ts,
        speed: (l['speed'] as num?)?.toDouble() ?? 0,
        battery: l['battery'] as int?,
        locationEnabled: l['locationEnabled'] != false,
      ),
      ackUntil: t.ackUntil,
    );
    _raise(t, r.alerts);
    if (r.needsReroute) {
      t.rerouteRaisedAt = DateTime.now();
      requestReroute(t.ref, _uid!, pos, t.dest).catchError((_) {});
    }
  }

  DateTime? _resultAt(Map<String, dynamic> d) =>
      ((d['reroute'] as Map?)?['result'] as Map?)?['at'] is Timestamp
      ? (((d['reroute'] as Map)['result'] as Map)['at'] as Timestamp).toDate()
      : null;

  /// Called every minute by the service: stale updates + reroute timeouts.
  void periodic() {
    final now = DateTime.now();
    for (final t in _active.values) {
      final raised = t.rerouteRaisedAt;
      if (raised != null && now.difference(raised).inSeconds > 90) {
        t.rerouteRaisedAt = null;
        t.checker.onRerouteFailed();
      }
      _raise(t, t.checker.periodic(now, ackUntil: t.ackUntil));
    }
  }

  static const _titles = {
    AlertType.offRoute: 'OFF ROUTE',
    AlertType.wrongDirection: 'Going the wrong way',
    AlertType.stoppedOffRoute: 'Stopped off route',
    AlertType.stale: 'No location updates',
    AlertType.lowBattery: 'Low battery',
    AlertType.locationOff: 'Location turned off',
    AlertType.arrived: 'Arrived safely',
  };

  void _raise(_Trip t, List<Alert> alerts) {
    for (final a in alerts) {
      final title = '${t.travelerName}: ${_titles[a.type]}';
      final pos = t.lastPos ?? t.dest;
      final urgent = a.type != AlertType.arrived;
      AlertService.alarm(
        title,
        a.message,
        pos.latitude,
        pos.longitude,
        urgent: urgent,
      );
      final topic = _groups[t.groupId]?['ntfyTopic'] as String?;
      if (topic != null && _uid != null) {
        claimAlertPost(t.ref, _uid!, a.type.name, a.message)
            .then((won) {
              if (won) {
                AlertService.postNtfy(
                  topic,
                  title,
                  a.message,
                  pos.latitude,
                  pos.longitude,
                );
              }
            })
            .catchError((_) {});
      }
    }
  }

  void _stopListeners() {
    _user?.cancel();
    for (final s in [..._members.values, ..._trips.values]) {
      s.cancel();
    }
    _members.clear();
    _trips.clear();
    _groups.clear();
    _active.clear();
    _uid = null;
  }

  Future<void> stop() async {
    await _auth?.cancel();
    _stopListeners();
  }
}
