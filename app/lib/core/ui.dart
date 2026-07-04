import 'package:flutter/material.dart';

import '../models/report.dart';
import 'theme.dart';

/// Shared Kerb components: badges, pills, empty states. Map pins and
/// clusters live in features/map/marker_icons.dart (Google Maps markers are
/// native bitmaps, not widgets).

/// App-wide messenger so background work (e.g. the verification watcher)
/// can announce results regardless of which screen is showing.
final kerbMessengerKey = GlobalKey<ScaffoldMessengerState>();

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
        border: Border.all(color: KerbColors.line),
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
