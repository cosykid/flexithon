import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../models/report.dart';
import 'env.dart';
import 'theme.dart';

/// Shared Kerb components: map chrome, pins, badges, empty states.

/// App-wide messenger so background work (e.g. the verification watcher)
/// can announce results regardless of which screen is showing.
final kerbMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Basemap. Stadia "Alidade Smooth" when a key is set; CARTO light for
/// keyless dev — both are calm, low-saturation canvases that let the
/// tier-coloured pins carry the information.
class KerbTileLayer extends StatelessWidget {
  const KerbTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: Env.stadiaApiKey.isEmpty
          ? 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png'
          : 'https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}.png?api_key=${Env.stadiaApiKey}',
      userAgentPackageName: 'com.hackathon.accessmap',
      // Aborts in-flight tile fetches when panned/zoomed past — less mobile
      // data, faster map settle.
      tileProvider: CancellableNetworkTileProvider(),
    );
  }
}

/// Compact attribution pill positioned by the caller (RichAttributionWidget
/// anchors to the map's bottom corners, which our floating nav bar covers).
class KerbAttributionPill extends StatelessWidget {
  const KerbAttributionPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        '© OpenStreetMap · CARTO · Stadia',
        style: TextStyle(fontSize: 9.5, color: KerbColors.ink600),
      ),
    );
  }
}

/// Map marker that carries its tier so cluster widgets can aggregate it.
/// Height matches KerbPin exactly (42 puck + 7 notch) so with
/// Alignment.topCenter the notch tip sits on the point.
class TierMarker extends Marker {
  const TierMarker({
    required this.tier,
    required super.point,
    required super.child,
    super.key,
  }) : super(width: 46, height: 49, alignment: Alignment.topCenter);

  final ReportTier tier;
}

/// A pin: white puck with a tier-coloured ring and shape-coded icon,
/// grounded by a small notch so it reads as "this exact spot".
class KerbPin extends StatelessWidget {
  const KerbPin({super.key, required this.tier});

  final ReportTier tier;

  @override
  Widget build(BuildContext context) {
    final color = TierStyle.color(tier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: KerbShadows.subtle,
          ),
          child: Icon(TierStyle.icon(tier), size: 22, color: color),
        ),
        CustomPaint(size: const Size(12, 7), painter: _NotchPainter(color)),
      ],
    );
  }
}

class _NotchPainter extends CustomPainter {
  const _NotchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.color != color;
}

/// Fades its child in on first mount. Safe on the map only when the widget
/// instance is stable across rebuilds (see the pin cache in MapScreen) —
/// otherwise every camera tick re-triggers the fade.
class KerbFadeIn extends StatelessWidget {
  const KerbFadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
    );
  }
}

/// Cluster circle: count in the middle, filled with the weighted blend of
/// its members' tier colours — mostly partial reports read amber, mostly
/// substantiated reads red, mixes land in between.
class KerbCluster extends StatelessWidget {
  const KerbCluster({super.key, required this.markers});

  final List<Marker> markers;

  @override
  Widget build(BuildContext context) {
    final tiers = markers.whereType<TierMarker>().toList();
    final substantiated =
        tiers.where((m) => m.tier == ReportTier.substantiated).length;
    final total = math.max(tiers.length, 1);
    final redFraction = substantiated / total;
    final fill = Color.lerp(
      KerbColors.warnBright,
      KerbColors.danger,
      redFraction,
    )!;
    final size = markers.length >= 100
        ? 60.0
        : markers.length >= 10
            ? 52.0
            : 46.0;

    return KerbFadeIn(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: KerbShadows.subtle,
        ),
        child: Text(
          '${markers.length}',
          style: kerbDisplay(size: size * 0.32, color: Colors.white),
        ),
      ),
    );
  }
}

class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.compact = false});

  final ReportTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: TierStyle.fill(tier),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TierStyle.icon(tier), size: compact ? 14 : 16, color: TierStyle.textColor(tier)),
          const SizedBox(width: 5),
          Text(
            compact ? TierStyle.shortLabel(tier) : TierStyle.label(tier),
            style: TextStyle(
              color: TierStyle.textColor(tier),
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// White floating pill used for map-surface chrome (brand chip, loaders).
class KerbFloatingPill extends StatelessWidget {
  const KerbFloatingPill({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: KerbShadows.subtle,
      ),
      child: child,
    );
  }
}

class KerbEmptyState extends StatelessWidget {
  const KerbEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: KerbColors.brand100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: KerbColors.brand700),
            ),
            const SizedBox(height: 16),
            Text(title, style: kerbDisplay(size: 18)),
            const SizedBox(height: 6),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
