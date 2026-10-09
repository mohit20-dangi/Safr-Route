import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../background/tracker_part.dart';
import '../services/geo_utils.dart';
import '../services/trip_repository.dart';
import '../ui/widgets.dart';
import 'guardian_map_screen.dart';
import 'permissions_setup_screen.dart';
import 'trip_plan_screen.dart';

class TravelerHomeScreen extends StatefulWidget {
  const TravelerHomeScreen({super.key, required this.groupId});
  final String groupId;
  @override
  State<TravelerHomeScreen> createState() => _TravelerHomeScreenState();
}

class _TravelerHomeScreenState extends State<TravelerHomeScreen> {
  final _repo = TripRepository();

  @override
  void initState() {
    super.initState();
    _repo.cleanupOldTrips().catchError((_) {});
  }

  Future<void> _end(String tripId) async {
    await TrackerPart.instance.stop();
    await _repo.endTrip(tripId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My trip')),
      body: StreamBuilder<QueryDocumentSnapshot<Map<String, dynamic>>?>(
        stream: _repo.myActiveTrip(),
        builder: (context, snap) {
          final trip = snap.data;
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (trip != null) return _activeView(trip);
          return _startView();
        },
      ),
    );
  }

  Widget _activeView(QueryDocumentSnapshot<Map<String, dynamic>> trip) {
    // Resume tracking after an app restart.
    if (Platform.isIOS && !TrackerPart.instance.isRunning) {
      final dd = trip.data()['destination'] as Map<String, dynamic>;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => TrackerPart.instance.start(
          trip.id,
          dest: LatLng(
            (dd['lat'] as num).toDouble(),
            (dd['lng'] as num).toDouble(),
          ),
        ),
      );
    }
    final data = trip.data();
    final loc = data['lastLocation'] as Map<String, dynamic>?;
    final ts = (loc?['ts'] as Timestamp?)?.toDate();
    final cs = Theme.of(context).colorScheme;
    final battery = loc?['battery'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.4)!],
            ),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  PulseDot(),
                  SizedBox(width: 10),
                  Text(
                    'LIVE  -  sharing with your group',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Heading to',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Text(
                '${data['destination']['name']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    Icons.access_time_rounded,
                    ts == null
                        ? 'Getting GPS…'
                        : '${DateTime.now().difference(ts).inSeconds}s ago',
                  ),
                  if (battery != null)
                    _chip(Icons.battery_5_bar_rounded, '$battery%'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text("I'm fine  -  silence alerts 5 min"),
          onPressed: () async {
            await _repo.ackFine(trip.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Alerts silenced for 5 min')),
              );
            }
          },
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.map),
          label: const Text('See live map'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuardianMapScreen(
                groupId: widget.groupId,
                groupName: 'My trip',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.alt_route),
          label: const Text('Change route'),
          onPressed: () {
            final dd = data['destination'] as Map<String, dynamic>;
            final started = (data['startedAt'] as Timestamp?)?.toDate();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TripPlanScreen(
                  groupId: widget.groupId,
                  activeTripId: trip.id,
                  presetName: dd['name'],
                  presetDest: LatLng(
                    (dd['lat'] as num).toDouble(),
                    (dd['lng'] as num).toDouble(),
                  ),
                  currentRoutes: [
                    for (final r in (data['routes'] as List? ?? []))
                      decodePolyline(r['polyline'] as String),
                  ],
                  elapsedSec: started == null
                      ? 0
                      : DateTime.now().difference(started).inSeconds.toDouble(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('End trip'),
          onPressed: () => _end(trip.id),
        ),
        const SizedBox(height: 16),
        Text(
          'Your location is shared only while a trip is active, and the trip ends '
          'by itself when you arrive. On iPhone, do not swipe-close the app during a trip.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  Widget _chip(IconData i, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(i, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _startView() {
    final places = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('places')
        .snapshots();
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Where are you going?',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a saved place or search anywhere.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        StreamBuilder(
          stream: places,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            Widget tile(
              IconData icon,
              String title,
              String sub,
              VoidCallback onTap, {
              bool primary = false,
            }) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                color: primary ? cs.primaryContainer : null,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.primary.withValues(alpha: 0.15),
                          child: Icon(icon, color: cs.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                sub,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return Column(
              children: [
                tile(
                  Icons.travel_explore_rounded,
                  'Somewhere else',
                  'Search an address or tap the map',
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripPlanScreen(groupId: widget.groupId),
                    ),
                  ),
                  primary: true,
                ),
                for (final d in docs)
                  tile(
                    Icons.flag_rounded,
                    d['name'],
                    'Plan trip here',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TripPlanScreen(
                          groupId: widget.groupId,
                          presetName: d['name'],
                          presetDest: LatLng(
                            (d['lat'] as num).toDouble(),
                            (d['lng'] as num).toDouble(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.verified_user_rounded),
          label: const Text('Permissions check'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PermissionsSetupScreen()),
          ),
        ),
      ],
    );
  }
}
