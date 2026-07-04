import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/report.dart';
import 'map_providers.dart';

class TierFilterChips extends ConsumerWidget {
  const TierFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(tierFilterProvider);
    final inView = ref.watch(mapPointsRawProvider).valueOrNull;
    return Row(
      children: [
        for (final tier in const [
          ReportTier.substantiated,
          ReportTier.partiallySubstantiated,
        ]) ...[
          _TierChip(
            tier: tier,
            count: inView?.where((p) => p.tier == tier).length,
            selected: selected.contains(tier),
            onTap: () {
              final next = {...selected};
              next.contains(tier) ? next.remove(tier) : next.add(tier);
              ref.read(tierFilterProvider.notifier).state = next;
            },
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.tier,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ReportTier tier;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${TierStyle.label(tier)} filter${count == null ? '' : ', $count in view'}',
      child: GestureDetector(
        onTap: onTap,
        // Border width and content are constant across states so toggling
        // never shifts layout — only colours animate.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? TierStyle.fill(tier) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? TierStyle.color(tier) : KerbColors.line,
              width: 1.4,
            ),
            boxShadow: KerbShadows.subtle,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TierStyle.icon(tier),
                size: 16,
                color: selected ? TierStyle.textColor(tier) : KerbColors.ink300,
              ),
              const SizedBox(width: 6),
              Text(
                TierStyle.shortLabel(tier),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? TierStyle.textColor(tier) : KerbColors.ink600,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.75)
                        : KerbColors.paper,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? TierStyle.textColor(tier)
                          : KerbColors.ink600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
