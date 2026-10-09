import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../ui/widgets.dart';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key, required this.groupId});
  final String groupId;

  CollectionReference<Map<String, dynamic>> get _places => FirebaseFirestore
      .instance
      .collection('groups')
      .doc(groupId)
      .collection('places');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      body: StreamBuilder(
        stream: _places.snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No places yet. Add Home and College.'),
            );
          }
          return ListView(
            children: [
              for (final d in docs)
                ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(d['name']),
                  subtitle: Text(
                    '${(d['lat'] as num).toStringAsFixed(4)}, ${(d['lng'] as num).toStringAsFixed(4)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => d.reference.delete(),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add place'),
        onPressed: () async {
          final r = await Navigator.push<_Picked>(
            context,
            MaterialPageRoute(builder: (_) => const _PickPlaceScreen()),
          );
          if (r == null) return;
          await _places.add({
            'name': r.name,
            'lat': r.point.latitude,
            'lng': r.point.longitude,
            'ownerUid': FirebaseAuth.instance.currentUser!.uid,
          });
        },
      ),
    );
  }
}

class _Picked {
  final String name;
  final LatLng point;
  _Picked(this.name, this.point);
}

class _PickPlaceScreen extends StatefulWidget {
  const _PickPlaceScreen();
  @override
  State<_PickPlaceScreen> createState() => _PickPlaceScreenState();
}

class _PickPlaceScreenState extends State<_PickPlaceScreen> {
  final _map = MapController();
  final _name = TextEditingController();
  LatLng _center = const LatLng(28.6139, 77.2090); // Delhi fallback
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    try {
      final p = await Geolocator.getCurrentPosition();
      final c = LatLng(p.latitude, p.longitude);
      if (mounted) {
        setState(() => _center = c);
        _map.move(c, 15);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tap the map to choose a place')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 13,
                onTap: (_, p) => setState(() => _picked = p),
              ),
              children: [
                appTileLayer(context),
                mapAttribution(),
                if (_picked != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Name (Home, College...)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _picked == null || _name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _Picked(_name.text.trim(), _picked!),
                        ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
