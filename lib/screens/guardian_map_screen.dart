import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../ui/widgets.dart';

import 'package:latlong2/latlong.dart';

import '../services/geo_utils.dart';
import '../services/trip_repository.dart';

List<LatLng> _trail(Map<String, dynamic> t) => [
  for (final p in (t['trail'] as List? ?? []))
    LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
];

List<List<LatLng>> _routes(Map<String, dynamic> t) => [
  for (final r in (t['routes'] as List? ?? []))
    decodePolyline(r['polyline'] as String),
];

LatLng? _lastPos(Map<String, dynamic> t) {
  final l = t['lastLocation'] as Map<String, dynamic>?;
  if (l == null) return null;
  return LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble());
}

/// Planned routes (faded) + travelled trail (blue) + destination flag.
List<Widget> tripLayers(Map<String, dynamic> t) {
  final routes = _routes(t);
  final trail = _trail(t);
  final dest = t['destination'] as Map<String, dynamic>?;
  return [
    PolylineLayer(
      polylines: [
        for (final r in routes)
          Polyline(
            points: r,
            color: Colors.blueGrey.withValues(alpha: 0.55),
            strokeWidth: 6,
          ),
        if (trail.length > 1)
          Polyline(
            points: trail,
            color: const Color(0xFF2F6BFF),
            strokeWidth: 6,
          ),
      ],
    ),
    if (dest != null)
      MarkerLayer(
        markers: [
          Marker(
            point: LatLng(
              (dest['lat'] as num).toDouble(),
              (dest['lng'] as num).toDouble(),
            ),
            width: 36,
            height: 36,
            child: const Icon(Icons.flag, color: Colors.red, size: 32),
          ),
        ],
      ),
  ];
}

class GuardianMapScreen extends StatefulWidget {
  const GuardianMapScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });
  final String groupId, groupName;
  @override
  State<GuardianMapScreen> createState() => _GuardianMapScreenState();
}

class _GuardianMapScreenState extends State<GuardianMapScreen> {
  final _map = MapController();
  Timer? _tick;
  String? _selected;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  ({String text, Color color}) _status(Map<String, dynamic> t) {
    final l = t['lastLocation'] as Map<String, dynamic>?;
    final ts = (l?['ts'] as Timestamp?)?.toDate();
    if (l == null || ts == null)
      return (text: 'Waiting for GPS', color: Colors.grey);
    if (l['locationEnabled'] == false)
      return (text: 'GPS OFF', color: Colors.red);
    final age = DateTime.now().difference(ts);
    if (age.inMinutes >= 5) {
      return (text: 'No update ${age.inMinutes} min', color: Colors.red);
    }
    return (text: 'Live', color: Colors.green);
  }

  String _age(Map<String, dynamic> t) {
    final ts = ((t['lastLocation'] as Map?)?['ts'] as Timestamp?)?.toDate();
    if (ts == null) return '-';
    final s = DateTime.now().difference(ts).inSeconds;
    return s < 90 ? '${s}s ago' : '${(s / 60).round()} min ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.groupName} - live')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('trips')
            .where('groupId', isEqualTo: widget.groupId)
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          final trips = {for (final d in docs) d.id: d.data()};

          if (!_fitted && trips.isNotEmpty) {
            final pts = [
              for (final t in trips.values) ...[
                ?_lastPos(t),
                ..._routes(t).expand((r) => r),
              ],
            ];
            if (pts.length > 1) {
              _fitted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _map.fitCamera(
                    CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(pts),
                      padding: const EdgeInsets.all(48),
                    ),
                  );
                } catch (_) {}
              });
            }
          }

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: LatLng(28.6139, 77.2090),
                    initialZoom: 11,
                  ),
                  children: [
                    appTileLayer(context),
                    mapAttribution(),
                    for (final t in trips.values) ...tripLayers(t),
                    MarkerLayer(
                      markers: [
                        for (final e in trips.entries)
                          if (_lastPos(e.value) != null)
                            Marker(
                              point: _lastPos(e.value)!,
                              width: 110,
                              height: 74,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _status(e.value).color,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black38,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      e.value['travelerName'] ?? '',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black38,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundColor: _status(e.value).color,
                                      child: Text(
                                        initials(
                                          '${e.value['travelerName'] ?? ''}',
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 14),
                  ],
                ),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.36,
                ),
                child: trips.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('Nobody is on a trip right now.'),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        children: [
                          for (final e in trips.entries)
                            Builder(
                              builder: (_) {
                                final st = _status(e.value);
                                final l =
                                    e.value['lastLocation']
                                        as Map<String, dynamic>?;
                                final name = '${e.value['travelerName']}';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    shape: _selected == e.key
                                        ? RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                            side: BorderSide(
                                              color: st.color,
                                              width: 2,
                                            ),
                                          )
                                        : null,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() => _selected = e.key);
                                        final p = _lastPos(e.value);
                                        if (p != null) _map.move(p, 15);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor: st.color,
                                              child: Text(
                                                initials(name),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  Text(
                                                    'to ${e.value['destination']['name']}  -  ${_age(e.value)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                StatusChip(st.text, st.color),
                                                if (l?['battery'] != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 4,
                                                        ),
                                                    child: Text(
                                                      '${l!['battery']}%',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows one ended trip's planned routes and travelled trail.
class TripReplayScreen extends StatelessWidget {
  const TripReplayScreen({super.key, required this.trip});
  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final pts = [..._trail(trip), ..._routes(trip).expand((r) => r)];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${trip['travelerName']} -> ${trip['destination']['name']}',
        ),
      ),
      floatingActionButton:
          trip['travelerUid'] == FirebaseAuth.instance.currentUser?.uid &&
              _trail(trip).length > 1
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.bookmark_add),
              label: const Text('Save as my usual route'),
              onPressed: () async {
                final d = trip['destination'] as Map<String, dynamic>;
                await SavedRoutes(trip['groupId']).save(
                  destName: d['name'],
                  dest: LatLng(
                    (d['lat'] as num).toDouble(),
                    (d['lng'] as num).toDouble(),
                  ),
                  points: _trail(trip),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Saved. Future trips here will accept this road.',
                      ),
                    ),
                  );
                }
              },
            )
          : null,
      body: FlutterMap(
        options: MapOptions(
          initialCenter: pts.isEmpty
              ? const LatLng(28.6139, 77.2090)
              : pts.first,
          initialZoom: 12,
          initialCameraFit: pts.length > 1
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(pts),
                  padding: const EdgeInsets.all(48),
                )
              : null,
        ),
        children: [
          appTileLayer(context),
          mapAttribution(),
          ...tripLayers(trip),
        ],
      ),
    );
  }
}
