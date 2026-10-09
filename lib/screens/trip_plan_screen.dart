import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../ui/widgets.dart';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../background/tracker_part.dart';
import '../services/routing_service.dart';
import '../services/trip_repository.dart';

const _palette = [
  Colors.blue,
  Colors.deepOrange,
  Colors.purple,
  Colors.pink,
  Colors.indigo,
];

class _Cand {
  _Cand(
    this.label,
    this.points, {
    this.durationSec,
    this.distanceM,
    this.saved = false,
  });
  final String label;
  final List<LatLng> points;
  final double? durationSec, distanceM;
  final bool saved;
  bool selected = true;
}

/// Pick any destination (search or tap), optionally force the road with via
/// points, choose which routes count as "valid", then start the trip.
class TripPlanScreen extends StatefulWidget {
  const TripPlanScreen({
    super.key,
    required this.groupId,
    this.presetName,
    this.presetDest,
    this.activeTripId,
    this.currentRoutes = const [],
    this.elapsedSec = 0,
  });
  final String groupId;

  /// Set when switching route during a trip (destination is locked).
  final String? activeTripId;
  final List<List<LatLng>> currentRoutes;
  final double elapsedSec;
  final String? presetName;
  final LatLng? presetDest;
  @override
  State<TripPlanScreen> createState() => _TripPlanScreenState();
}

class _TripPlanScreenState extends State<TripPlanScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  LatLng? _origin, _dest;
  String _destName = 'Destination';
  final _vias = <LatLng>[];
  bool _viaMode = false, _busy = false;
  List<_Cand> _cands = [];
  double _baseline = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.activeTripId != null) _viaMode = true;
    if (widget.presetDest != null) {
      _dest = widget.presetDest;
      _destName = widget.presetName ?? 'Destination';
    }
    _locate();
  }

  Future<void> _locate() async {
    try {
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _origin = LatLng(p.latitude, p.longitude));
      _fit();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not get your location: $e');
    }
  }

  void _fit() {
    final pts = [?_origin, ?_dest, ..._vias];
    if (pts.length > 1) {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(60),
        ),
      );
    } else if (pts.length == 1) {
      _map.move(pts.first, 14);
    }
  }

  void _invalidate() => _cands = [];

  String? _countryCode;

  /// Country of the user's current position (so search stays in-country).
  Future<String?> _country(LatLng at) async {
    if (_countryCode != null) return _countryCode;
    try {
      final r = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${at.latitude}&lon=${at.longitude}&zoom=3&format=json',
        ),
        headers: {'User-Agent': 'SaferouteFamilyApp/1.0'},
      );
      _countryCode =
          (jsonDecode(r.body)['address']?['country_code'] as String?);
    } catch (_) {}
    return _countryCode;
  }

  static final _coordRe = RegExp(
    r'^\s*(-?\d{1,2}\.\d+)\s*[, ]\s*(-?\d{1,3}\.\d+)\s*$',
  );
  static final _urlCoordRes = [
    RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
    RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
    RegExp(r'[?&](?:q|ll|query|destination)=(-?\d+\.\d+)(?:,|%2C)(-?\d+\.\d+)'),
  ];

  LatLng? _parseCoords(String text) {
    final m = _coordRe.firstMatch(text);
    if (m != null) {
      return LatLng(double.parse(m.group(1)!), double.parse(m.group(2)!));
    }
    for (final re in _urlCoordRes) {
      final u = re.firstMatch(text);
      if (u != null) {
        return LatLng(double.parse(u.group(1)!), double.parse(u.group(2)!));
      }
    }
    return null;
  }

  /// Place name inside a Google Maps URL (…/maps/place/NAME/… or ?q=NAME).
  String? _placeNameFromUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return null;
    final seg = u.pathSegments;
    final i = seg.indexOf('place');
    if (i >= 0 && i + 1 < seg.length) {
      final n = Uri.decodeComponent(seg[i + 1]).replaceAll('+', ' ').trim();
      if (n.isNotEmpty && !_coordRe.hasMatch(n)) return n;
    }
    for (final k in ['q', 'query', 'destination']) {
      final v = u.queryParameters[k];
      if (v != null && v.trim().isNotEmpty && !_coordRe.hasMatch(v)) {
        return v.trim();
      }
    }
    return null;
  }

  /// DNS-over-HTTPS lookup, for networks whose own DNS blocks or mangles
  /// Google's short-link domain.
  Future<String> _doh(String host) async {
    for (final u in [
      'https://1.1.1.1/dns-query?name=$host&type=A',
      'https://dns.google/resolve?name=$host&type=A',
      'https://cloudflare-dns.com/dns-query?name=$host&type=A',
    ]) {
      try {
        final r = await http
            .get(Uri.parse(u), headers: {'accept': 'application/dns-json'})
            .timeout(const Duration(seconds: 5));
        final ans = (jsonDecode(r.body)['Answer'] as List? ?? [])
            .where((a) => a['type'] == 1)
            .toList();
        if (ans.isNotEmpty) return ans.first['data'] as String;
      } catch (_) {}
    }
    throw Exception('DNS lookup failed for $host');
  }

  /// One GET over a socket to a DNS-over-HTTPS-resolved address. The TLS
  /// certificate is still checked against the real host name. Returns the
  /// Location header, if any.
  Future<String?> _rawLocation(Uri uri) async {
    final ip = await _doh(uri.host);
    final raw = await Socket.connect(
      InternetAddress(ip),
      uri.hasPort ? uri.port : 443,
      timeout: const Duration(seconds: 8),
    );
    final sock = uri.scheme == 'https'
        ? await SecureSocket.secure(raw, host: uri.host)
        : raw;
    try {
      final path = uri.path.isEmpty ? '/' : uri.path;
      sock.write(
        'GET ${uri.hasQuery ? '$path?${uri.query}' : path} HTTP/1.1\r\n'
        'Host: ${uri.host}\r\n'
        'User-Agent: Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36\r\n'
        'Accept: */*\r\n'
        'Connection: close\r\n\r\n',
      );
      await sock.flush();
      final buf = StringBuffer();
      await for (final chunk in sock.timeout(const Duration(seconds: 10))) {
        buf.write(latin1.decode(chunk, allowInvalid: true));
        if (buf.toString().contains('\r\n\r\n')) break;
      }
      final head = buf.toString().split('\r\n\r\n').first;
      for (final line in head.split('\r\n')) {
        if (line.toLowerCase().startsWith('location:')) {
          return line.substring(9).trim();
        }
      }
      return null;
    } finally {
      sock.destroy();
    }
  }

  /// Follows redirects by hand (we only need the Location header, which holds
  /// the coordinates) and stops as soon as coordinates appear.
  Future<String> _followRedirects(String url, {required bool useDoh}) async {
    var current = url;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent =
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';
    try {
      for (var i = 0; i < 6; i++) {
        String? loc;
        if (useDoh) {
          loc = await _rawLocation(Uri.parse(current));
        } else {
          final req = await client.getUrl(Uri.parse(current))
            ..followRedirects = false;
          final res = await req.close().timeout(const Duration(seconds: 12));
          await res.drain();
          loc = res.headers.value(HttpHeaders.locationHeader);
        }
        if (loc == null) break;
        current = Uri.parse(current).resolve(loc).toString();
        // Cookie-consent interstitial: the real URL is in ?continue=
        final u = Uri.parse(current);
        if (u.host.contains('consent.') &&
            u.queryParameters['continue'] != null) {
          current = u.queryParameters['continue']!;
        }
        if (_parseCoords(current) != null) break;
      }
    } finally {
      client.close();
    }
    return current;
  }

  /// Expands a Google Maps short link (maps.app.goo.gl/...) to its full URL.
  Future<String> _expandLink(String url) async {
    try {
      return await _followRedirects(
        url,
        useDoh: false,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      return _followRedirects(url, useDoh: true);
    }
  }

  /// Some Maps links carry only a place name and Google's internal id, not
  /// coordinates. Google's own page loads the place details from an internal
  /// endpoint whose response lists the place's exact coordinates next to its
  /// id; read them from there. (Unofficial: if Google changes it, we fall back
  /// to searching by name.)
  Future<LatLng?> _googlePlaceCoords(String placeUrl) async {
    const headers = {
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
      'Accept-Language': 'en',
      'Cookie': 'CONSENT=YES+1; SOCS=CAI',
    };
    final page = await http
        .get(Uri.parse(placeUrl), headers: headers)
        .timeout(const Duration(seconds: 15));
    final m = RegExp(r'''/maps/preview/place\?[^"'\s<]+''')
        .firstMatch(page.body);
    if (m == null) return null;
    final detailUrl =
        'https://www.google.com${m.group(0)!.replaceAll('&amp;', '&').replaceAll(r'\u0026', '&').replaceAll(r'\u003d', '=')}';
    final r = await http
        .get(Uri.parse(detailUrl), headers: headers)
        .timeout(const Duration(seconds: 15));
    final ftid = RegExp(r'!1s(0x[0-9a-f]+:0x[0-9a-f]+)')
        .firstMatch(placeUrl)
        ?.group(1);
    final re = RegExp(
      r'\[null,null,(-?\d+\.\d+),(-?\d+\.\d+)\],"(0x[0-9a-f]+:0x[0-9a-f]+)"',
    );
    for (final mm in re.allMatches(r.body)) {
      if (ftid == null || mm.group(3) == ftid) {
        return LatLng(double.parse(mm.group(1)!), double.parse(mm.group(2)!));
      }
    }
    return null;
  }

  void _setDest(LatLng p, String name) {
    setState(() {
      _dest = p;
      _destName = name;
      _vias.clear();
      _invalidate();
    });
    _fit();
  }

  Future<List<Map<String, dynamic>>> _nominatim(
    String q,
    LatLng here,
    String? cc,
  ) async {
    const d = 0.6;
    final url =
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeQueryComponent(q)}'
        '&format=jsonv2&limit=10'
        '&viewbox=${here.longitude - d},${here.latitude + d},${here.longitude + d},${here.latitude - d}'
        '&bounded=0${cc != null ? '&countrycodes=$cc' : ''}';
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'SaferouteFamilyApp/1.0'},
    );
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Photon (OpenStreetMap too): typo tolerant and biased to a location.
  Future<List<Map<String, dynamic>>> _photon(
    String q,
    LatLng here,
    String? cc,
  ) async {
    final res = await http.get(
      Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeQueryComponent(q)}&limit=10'
        '&lat=${here.latitude}&lon=${here.longitude}',
      ),
      headers: {'User-Agent': 'SaferouteFamilyApp/1.0'},
    );
    final feats = (jsonDecode(res.body)['features'] as List? ?? []);
    final out = <Map<String, dynamic>>[];
    for (final f in feats) {
      final pr = f['properties'] as Map<String, dynamic>;
      if (cc != null &&
          (pr['countrycode'] as String?)?.toLowerCase() != cc.toLowerCase()) {
        continue;
      }
      final c = f['geometry']['coordinates'] as List;
      final parts = [
        pr['name'],
        pr['street'],
        pr['district'] ?? pr['locality'],
        pr['city'],
        pr['state'],
        pr['country'],
      ].whereType<String>().where((e) => e.isNotEmpty).toList();
      out.add({
        'name': pr['name'] ?? '',
        'display_name': parts.join(', '),
        'lat': '${c[1]}',
        'lon': '${c[0]}',
      });
    }
    return out;
  }

  Future<void> _doSearch() async {
    var q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 1. Coordinates or a pasted Google Maps link.
      var direct = _parseCoords(q);
      // Google's Share button copies "Place name\nhttps://maps.app.goo.gl/..."
      final link = RegExp(r'https?://\S+').firstMatch(q)?.group(0);
      if (direct == null && link != null) {
        final textBefore = q.substring(0, q.indexOf(link)).trim();
        String expanded = link;
        String? netError;
        try {
          expanded = await _expandLink(link);
        } catch (e) {
          netError = e.toString();
        }
        direct = _parseCoords(expanded);
        String? linkName = _placeNameFromUrl(expanded)?.split(',').first;
        if (direct == null &&
            Uri.tryParse(expanded)?.host.contains('google.') == true) {
          try {
            direct = await _googlePlaceCoords(expanded);
          } catch (_) {}
        }
        if (direct != null) {
          if (mounted) setState(() => _busy = false);
          _setDest(direct, linkName ?? 'Shared location');
          return;
        }
        if (direct == null) {
          // No coordinates in the link: search by the place name instead.
          final name = textBefore.isNotEmpty
              ? textBefore.split('\n').first.trim()
              : _placeNameFromUrl(expanded);
          if (name == null || name.isEmpty) {
            if (mounted) {
              final shown = expanded.length > 90
                  ? '${expanded.substring(0, 90)}...'
                  : expanded;
              setState(() {
                _busy = false;
                _error = netError != null
                    ? 'Could not open that link (network problem: $netError). '
                          'Try the place name instead.'
                    : 'Could not read a location from that link '
                          '(it opened: $shown). Try the place name instead.';
              });
            }
            return;
          }
          q = name;
          _search.text = name.split(',').first;
        }
      }
      if (direct != null) {
        if (mounted) setState(() => _busy = false);
        _setDest(direct, 'Shared location');
        return;
      }

      // 2. Search two OpenStreetMap-based services and merge.
      final here = _origin ?? _map.camera.center;
      final cc = await _country(here);
      // Long addresses (e.g. from a Maps link) rarely match as-is, so retry
      // with progressively shorter versions until something is found.
      final parts = q
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final variants = <String>{
        q,
        if (parts.length > 2)
          '${parts.first}, ${parts.sublist(parts.length > 4 ? parts.length - 3 : 1).join(', ')}',
        if (parts.length > 1) parts.first,
      };
      var results = <List<Map<String, dynamic>>>[];
      for (final v in variants) {
        results = await Future.wait([
          _nominatim(v, here, cc).catchError((_) => <Map<String, dynamic>>[]),
          _photon(v, here, cc).catchError((_) => <Map<String, dynamic>>[]),
        ]);
        if (results.any((r) => r.isNotEmpty)) break;
      }
      double km(Map<String, dynamic> r) =>
          const Distance()(
            here,
            LatLng(double.parse(r['lat']), double.parse(r['lon'])),
          ) /
          1000;
      final list = <Map<String, dynamic>>[];
      for (final r in results.expand((e) => e)) {
        final p = LatLng(double.parse(r['lat']), double.parse(r['lon']));
        final dup = list.any(
          (o) =>
              const Distance()(
                p,
                LatLng(double.parse(o['lat']), double.parse(o['lon'])),
              ) <
              60,
        );
        if (!dup) list.add(r);
      }
      list.sort((a, b) => km(a).compareTo(km(b)));
      if (!mounted) return;
      setState(() => _busy = false);
      if (list.isEmpty) {
        setState(
          () => _error =
              'Nothing found for "$q". Try a nearby landmark, paste a Google Maps '
              'link or "lat,lng", or tap the map.',
        );
        return;
      }
      final pick = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (c) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in list.take(14))
                ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(
                    (r['name'] as String?)?.isNotEmpty == true
                        ? r['name']
                        : (r['display_name'] as String).split(',').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    r['display_name'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${km(r).toStringAsFixed(km(r) < 10 ? 1 : 0)} km',
                  ),
                  onTap: () => Navigator.pop(c, r),
                ),
            ],
          ),
        ),
      );
      if (pick == null) return;
      _setDest(
        LatLng(double.parse(pick['lat']), double.parse(pick['lon'])),
        ((pick['name'] as String?)?.isNotEmpty == true
                ? pick['name']
                : (pick['display_name'] as String).split(',').first)
            as String,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Search failed: $e';
        });
      }
    }
  }

  Future<void> _findRoutes() async {
    final o = _origin, d = _dest;
    if (o == null || d == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = await fetchRoutes(o, d, via: List.of(_vias));
      if (api.isEmpty) throw Exception('No route found');
      final saved = await SavedRoutes(widget.groupId).forDestination(d);
      final cands = <_Cand>[
        for (var i = 0; i < api.length; i++)
          _Cand(
            i == 0
                ? (_vias.isEmpty ? 'Fastest route' : 'Route via your points')
                : 'Alternative $i',
            api[i].points,
            durationSec: api[i].durationSec,
            distanceM: api[i].distanceM,
          ),
        for (final s in saved) _Cand(s.label, s.points, saved: true),
        for (var i = 0; i < widget.currentRoutes.length; i++)
          _Cand('Current route ${i + 1}', widget.currentRoutes[i], saved: true),
      ];
      // With via points the single route is exactly what the user drew, and
      // alternatives are noise: keep only the first selected by default.
      for (var i = 1; i < api.length; i++) {
        cands[i].selected = false;
      }
      setState(() {
        _cands = cands;
        _baseline = api.first.durationSec;
      });
      _fit();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final chosen = _cands.where((c) => c.selected).toList();
    if (chosen.isEmpty || _dest == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await Permission.locationWhenInUse.isGranted) {
        throw Exception(
          'Location permission missing - open "Permissions check".',
        );
      }
      final apiChosen = chosen.where((c) => c.durationSec != null);
      if (widget.activeTripId != null) {
        // Switching mid-trip: new baseline = time already spent + new ETA.
        final fresh = apiChosen.isEmpty
            ? _baseline
            : apiChosen
                  .map((c) => c.durationSec!)
                  .reduce((a, b) => a < b ? a : b);
        await TripRepository().changeRoutes(
          widget.activeTripId!,
          baselineEtaSec: widget.elapsedSec + fresh,
          routes: [
            for (final c in chosen)
              RouteOption(
                points: c.points,
                distanceM: c.distanceM ?? 0,
                durationSec: c.durationSec ?? fresh,
              ),
          ],
        );
        if (mounted) Navigator.pop(context);
        return;
      }
      final baseline = apiChosen.isEmpty
          ? _baseline
          : apiChosen
                .map((c) => c.durationSec!)
                .reduce((a, b) => a < b ? a : b);
      final id = await TripRepository().startTrip(
        groupId: widget.groupId,
        destName: _destName,
        dest: _dest!,
        baselineEtaSec: baseline,
        routes: [
          for (final c in chosen)
            RouteOption(
              points: c.points,
              distanceM: c.distanceM ?? 0,
              durationSec: c.durationSec ?? baseline,
            ),
        ],
      );
      await TrackerPart.instance.startFromUi(id, _dest!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _cands.where((c) => c.selected).toList();
    final screenH = MediaQuery.sizeOf(context).height;
    return Scaffold(
      // The keyboard overlays the bottom panel instead of squeezing the layout.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.activeTripId != null ? 'Change route' : 'Plan trip'),
      ),
      body: Column(
        children: [
          if (widget.activeTripId == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _doSearch(),
                      decoration: const InputDecoration(
                        hintText: 'Search, paste a Maps link, or lat,lng',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _busy ? null : _doSearch,
                  ),
                ],
              ),
            ),
          if (widget.activeTripId == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.flag),
                    label: Text('Destination'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.alt_route),
                    label: Text('Via point'),
                  ),
                ],
                selected: {_viaMode},
                onSelectionChanged: (s) => setState(() => _viaMode = s.first),
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter:
                    widget.presetDest ?? const LatLng(28.6139, 77.2090),
                initialZoom: 12,
                onTap: (_, p) => setState(() {
                  if ((_viaMode && _dest != null) ||
                      widget.activeTripId != null) {
                    _vias.add(p);
                  } else {
                    _dest = p;
                    _destName = 'Pinned destination';
                    _vias.clear();
                  }
                  _invalidate();
                }),
              ),
              children: [
                appTileLayer(context),
                mapAttribution(),
                PolylineLayer(
                  polylines: [
                    for (final c in _cands.where((c) => !c.selected))
                      Polyline(
                        points: c.points,
                        color: Colors.grey.withValues(alpha: 0.6),
                        strokeWidth: 3,
                      ),
                    for (final c in sel)
                      Polyline(
                        points: c.points,
                        color: _palette[_cands.indexOf(c) % _palette.length]
                            .withValues(alpha: 0.8),
                        strokeWidth: 5,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_origin != null)
                      Marker(
                        point: _origin!,
                        width: 24,
                        height: 24,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                        ),
                      ),
                    for (var i = 0; i < _vias.length; i++)
                      Marker(
                        point: _vias[i],
                        width: 28,
                        height: 28,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueGrey,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    if (_dest != null)
                      Marker(
                        point: _dest!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.flag,
                          color: Colors.red,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: screenH * 0.38),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_dest == null)
                    const Text(
                      'Search above, or tap the map to choose where you are going.',
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'To: $_destName${_vias.isEmpty ? '' : '  (${_vias.length} via)'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_vias.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              _vias.removeLast();
                              _invalidate();
                            }),
                            child: const Text('Undo via'),
                          ),
                      ],
                    ),
                  if (_dest != null && _cands.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.activeTripId != null
                            ? 'Tap along the road you are taking now, then find routes.'
                            : 'Not your usual road? Switch to "via point" and tap along the road she normally takes, then find routes.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  for (var i = 0; i < _cands.length; i++)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _cands[i].selected,
                      onChanged: (v) =>
                          setState(() => _cands[i].selected = v ?? false),
                      secondary: Icon(
                        Icons.circle,
                        color: _palette[i % _palette.length],
                      ),
                      title: Text(_cands[i].label),
                      subtitle: _cands[i].durationSec == null
                          ? const Text('Saved from a previous trip')
                          : Text(
                              '${(_cands[i].distanceM! / 1000).toStringAsFixed(1)} km - ${(_cands[i].durationSec! / 60).round()} min',
                            ),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else if (_cands.isEmpty)
                    FilledButton(
                      onPressed: (_dest == null || _origin == null)
                          ? null
                          : _findRoutes,
                      child: Text(
                        _origin == null
                            ? 'Getting your location...'
                            : 'Find routes',
                      ),
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        '${widget.activeTripId != null ? 'Switch to' : 'Start trip with'} ${sel.length} valid route${sel.length == 1 ? '' : 's'}',
                      ),
                      onPressed: sel.isEmpty ? null : _start,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
