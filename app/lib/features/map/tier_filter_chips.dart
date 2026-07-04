import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/report.dart';
import 'map_providers.dart';

/// Google Maps layers-style button: a round white control that opens a
/// dropdown of checkable tier filters. A blue dot marks the button whenever
/// a tier is hidden, so an active filter is never invisible.
class TierFilterButton extends ConsumerWidget {
  const TierFilterButton({super.key});

  static const _tiers = [
    ReportTier.substantiated,
    ReportTier.partiallySubstantiated,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(tierFilterProvider);
    final inView = ref.watch(mapPointsRawProvider).valueOrNull;
    final filtering = !selected.containsAll(_tiers);

    return Semantics(
      button: true,
      label: 'Filter barriers${filtering ? ', filter active' : ''}',
      child: PopupMenuButton<ReportTier>(
        tooltip: 'Filter barriers',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        onSelected: (tier) {
          final next = {...selected};
          next.contains(tier) ? next.remove(tier) : next.add(tier);
          ref.read(tierFilterProvider.notifier).state = next;
        },
        itemBuilder: (context) => [
          for (final tier in _tiers)
            CheckedPopupMenuItem(
              value: tier,
              checked: selected.contains(tier),
              child: _TierMenuRow(
                tier: tier,
                count: inView?.where((p) => p.tier == tier).length,
              ),
            ),
        ],
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: KerbShadows.subtle,
              ),
              child: const Icon(Icons.layers_rounded,
                  size: 20, color: KerbColors.ink600),
            ),
            if (filtering)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: KerbColors.brand600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierMenuRow extends StatelessWidget {
  const _TierMenuRow({required this.tier, required this.count});

  final ReportTier tier;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(TierStyle.icon(tier), size: 18, color: TierStyle.textColor(tier)),
        const SizedBox(width: 10),
        Text(TierStyle.shortLabel(tier)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: TierStyle.fill(tier),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: TierStyle.textColor(tier),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
