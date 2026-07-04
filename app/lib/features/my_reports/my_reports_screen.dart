import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/report.dart';
import '../map/map_providers.dart';

class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My reports')),
      body: RefreshIndicator(
        color: KerbColors.brand600,
        onRefresh: () => ref.refresh(myReportsProvider.future),
        child: switch (reports) {
          AsyncData(:final value) when value.isEmpty => ListView(
              children: const [
                SizedBox(height: 80),
                KerbEmptyState(
                  icon: Icons.accessible_forward_rounded,
                  title: 'No reports yet',
                  caption:
                      'Spot stairs with no ramp, a narrow doorway, a broken '
                      'lift? Report it and help someone route around it.',
                ),
              ],
            ),
          AsyncData(:final value) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: value.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _MyReportCard(report: value[i]),
            ),
          AsyncError(:final error) => ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Could not load reports: $error'),
                ),
              ],
            ),
          _ => const Center(
              child: CircularProgressIndicator(color: KerbColors.brand600),
            ),
        },
      ),
    );
  }
}

class _MyReportCard extends StatelessWidget {
  const _MyReportCard({required this.report});

  final Report report;

  Color get _color => switch (report.status) {
        ReportStatus.pending => KerbColors.pending,
        ReportStatus.rejected => KerbColors.ink300,
        ReportStatus.classified =>
          TierStyle.color(report.tier ?? ReportTier.unsubstantiated),
      };

  Color get _fill => switch (report.status) {
        ReportStatus.pending => KerbColors.pendingFill,
        ReportStatus.rejected => KerbColors.paper,
        ReportStatus.classified =>
          TierStyle.fill(report.tier ?? ReportTier.unsubstantiated),
      };

  IconData get _icon => switch (report.status) {
        ReportStatus.pending => Icons.hourglass_top_rounded,
        ReportStatus.rejected => Icons.block_rounded,
        ReportStatus.classified =>
          TierStyle.icon(report.tier ?? ReportTier.unsubstantiated),
      };

  String get _label => switch (report.status) {
        ReportStatus.pending => 'Verifying…',
        ReportStatus.rejected => 'Rejected',
        ReportStatus.classified =>
          TierStyle.label(report.tier ?? ReportTier.unsubstantiated),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KerbColors.surface,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _fill,
              borderRadius: BorderRadius.circular(KerbRadius.sm),
            ),
            child: Icon(_icon, size: 22, color: _color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.locationName ?? report.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _color,
                      ),
                    ),
                    Text(
                      '  ·  ${DateFormat.yMMMd().format(report.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
