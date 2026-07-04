import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/map_point.dart';
import '../../models/report.dart';
import '../map/map_providers.dart';

void showReportDetailSheet(BuildContext context, MapPoint point) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportDetailSheet(point: point),
  );
}

class ReportDetailSheet extends ConsumerWidget {
  const ReportDetailSheet({super.key, required this.point});

  final MapPoint point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(locationReportsProvider(point.locationId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
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
              Text(
                point.name ?? 'Reported barrier',
                style: kerbDisplay(size: 22),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TierBadge(tier: point.tier),
                  const SizedBox(width: 10),
                  const Icon(Icons.flag_rounded, size: 15, color: KerbColors.ink600),
                  const SizedBox(width: 4),
                  Text(
                    '${point.reportCount} report${point.reportCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (point.tier == ReportTier.partiallySubstantiated) ...[
                const SizedBox(height: 14),
                const _ContradictionCallout(),
              ],
              const SizedBox(height: 18),
              ...switch (reports) {
                AsyncData(:final value) =>
                  value.map((r) => _ReportCard(report: r)),
                AsyncError(:final error) => [
                    Text('Could not load reports: $error'),
                  ],
                _ => const [
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: KerbColors.brand600,
                        ),
                      ),
                    ),
                  ],
              },
            ],
          ),
        );
      },
    );
  }
}

class _ContradictionCallout extends StatelessWidget {
  const _ContradictionCallout();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KerbColors.warnFill,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.warnBright.withValues(alpha: 0.5)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, size: 20, color: KerbColors.warn),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This venue claims wheelchair accessibility online, but reports '
              'with photos say otherwise.',
              style: TextStyle(
                color: KerbColors.warn,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: KerbColors.surface,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.photoPath != null)
            FutureBuilder<String?>(
              future: repo.photoUrl(report.photoPath),
              builder: (context, snap) {
                if (snap.data == null) return const SizedBox.shrink();
                return CachedNetworkImage(
                  imageUrl: snap.data!,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (report.barrierType != null)
                      _BarrierTag(type: report.barrierType!),
                    const Spacer(),
                    Text(
                      DateFormat.yMMMd().format(report.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(report.description),
                if (report.aiReasoning != null) ...[
                  const SizedBox(height: 12),
                  _AiSummary(text: report.aiReasoning!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarrierTag extends StatelessWidget {
  const _BarrierTag({required this.type});

  final String type;

  static IconData _icon(String type) => switch (type) {
        'stairs' => Icons.stairs_rounded,
        'no_ramp' => Icons.do_not_step_rounded,
        'narrow_entrance' => Icons.door_front_door_rounded,
        'broken_lift' => Icons.elevator_rounded,
        _ => Icons.block_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KerbColors.paper,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: KerbColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(type), size: 14, color: KerbColors.ink600),
          const SizedBox(width: 5),
          Text(
            type.replaceAll('_', ' '),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: KerbColors.ink600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed AI verification note; expands on tap.
class _AiSummary extends StatefulWidget {
  const _AiSummary({required this.text});

  final String text;

  @override
  State<_AiSummary> createState() => _AiSummaryState();
}

class _AiSummaryState extends State<_AiSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KerbColors.brand100.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(KerbRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 15, color: KerbColors.brand700),
                const SizedBox(width: 6),
                Text(
                  'AI verification',
                  style: kerbDisplay(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: KerbColors.brand700,
                  ),
                ),
                const Spacer(),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: KerbColors.brand700,
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              Text(
                widget.text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: KerbColors.ink900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
