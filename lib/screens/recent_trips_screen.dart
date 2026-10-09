import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import 'guardian_map_screen.dart';

class RecentTripsScreen extends StatelessWidget {
  const RecentTripsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(
      const Duration(days: Config.keepTripsDays),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Recent trips (7 days)')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('trips')
            .where('groupId', isEqualTo: groupId)
            .where('status', isEqualTo: 'ended')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final trips =
              (snap.data?.docs ?? [])
                  .map((d) => d.data())
                  .where(
                    (t) =>
                        ((t['endedAt'] as Timestamp?)?.toDate() ??
                                DateTime.now())
                            .isAfter(cutoff),
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      ((b['endedAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                              0)
                          .compareTo(
                            (a['endedAt'] as Timestamp?)
                                    ?.millisecondsSinceEpoch ??
                                0,
                          ),
                );
          if (trips.isEmpty)
            return const Center(child: Text('No recent trips.'));
          return ListView(
            children: [
              for (final t in trips)
                ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(
                    '${t['travelerName']} -> ${t['destination']['name']}',
                  ),
                  subtitle: Text(
                    _fmt(
                      (t['startedAt'] as Timestamp?)?.toDate(),
                      (t['endedAt'] as Timestamp?)?.toDate(),
                    ),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripReplayScreen(trip: t),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _fmt(DateTime? s, DateTime? e) {
    if (s == null) return '';
    final mins = e?.difference(s).inMinutes;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${s.day}/${s.month} ${two(s.hour)}:${two(s.minute)}'
        '${mins != null ? ' - $mins min' : ''}';
  }
}
