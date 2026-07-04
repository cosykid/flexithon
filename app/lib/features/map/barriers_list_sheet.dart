import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/map_point.dart';
import '../report_detail/report_detail_sheet.dart';

/// List of every barrier in the current viewport — a screen-reader-friendly
/// twin of the map markers (native Google markers carry no widget semantics)
/// and a faster scan than tapping pins one by one.
void showBarriersListSheet(BuildContext context, List<MapPoint> points) {
  final sorted = [...points]..sort((a, b) {
      final byTier = b.tier.index.compareTo(a.tier.index);
      return byTier != 0 ? byTier : b.reportCount.compareTo(a.reportCount);
    });

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: KerbColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(KerbRadius.lg)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KerbColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Barriers in view', style: kerbDisplay(size: 22)),
            const SizedBox(height: 4),
            Text(
              '${sorted.length} location${sorted.length == 1 ? '' : 's'} '
              'with reported access barriers',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final point in sorted)
              _BarrierTile(
                point: point,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showReportDetailSheet(context, point);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _BarrierTile extends StatelessWidget {
  const _BarrierTile({required this.point, required this.onTap});

  final MapPoint point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: KerbColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KerbRadius.md),
          side: const BorderSide(color: KerbColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KerbRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TierStyle.fill(point.tier),
                    borderRadius: BorderRadius.circular(KerbRadius.sm),
                  ),
                  child: Icon(
                    TierStyle.icon(point.tier),
                    size: 22,
                    color: TierStyle.color(point.tier),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        point.name ?? 'Reported barrier',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${TierStyle.shortLabel(point.tier)}  ·  '
                        '${point.reportCount} report${point.reportCount == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: KerbColors.ink300),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
