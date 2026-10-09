import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Standard OpenStreetMap tiles (no key needed). In dark mode the tiles are
/// darkened on the phone with a colour filter.
const _darkTiles = ColorFilter.matrix(<double>[
  -0.85, 0, 0, 0, 218, //
  0, -0.85, 0, 0, 222, //
  0, 0, -0.85, 0, 226, //
  0, 0, 0, 1, 0, //
]);

Widget appTileLayer(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.mohit.saferoute',
    tileBuilder: dark
        ? (context, tile, _) =>
              ColorFiltered(colorFilter: _darkTiles, child: tile)
        : null,
  );
}

Widget mapAttribution() => const SimpleAttributionWidget(
  source: Text('OpenStreetMap contributors', style: TextStyle(fontSize: 10)),
  alignment: Alignment.bottomLeft,
);

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, this.color, {super.key, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

/// Big tappable tile used on the group hub.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = highlight ? cs.onPrimary : cs.onSurface;
    return Card(
      color: highlight ? cs.primary : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: highlight
                      ? Colors.white.withValues(alpha: 0.2)
                      : cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: highlight ? cs.onPrimary : cs.primary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: fg.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft pulsing dot for "LIVE".
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.color = Colors.redAccent, this.size = 12});
  final Color color;
  final double size;
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.6 * _c.value),
            blurRadius: 10 * _c.value + 2,
            spreadRadius: 4 * _c.value,
          ),
        ],
      ),
    ),
  );
}

String initials(String name) {
  final p = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}
