import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/report.dart';
import '../map/map_providers.dart';
import 'report_pipeline.dart';

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
              itemCount: _listItemCount(value),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (_showPipelineSummary(value) && i == 0) {
                  return ReportPipelineSummaryCard(reports: value);
                }
                final index = _showPipelineSummary(value) ? i - 1 : i;
                return _MyReportCard(
                  report: value[index],
                  totalReportCount: value.length,
                );
              },
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

  static bool _showPipelineSummary(List<Report> reports) => reports.isNotEmpty;

  static int _listItemCount(List<Report> reports) =>
      reports.length + (_showPipelineSummary(reports) ? 1 : 0);
}

class _MyReportCard extends StatefulWidget {
  const _MyReportCard({
    required this.report,
    required this.totalReportCount,
  });

  final Report report;
  final int totalReportCount;

  static const _autoExpandThreshold = 5;

  @override
  State<_MyReportCard> createState() => _MyReportCardState();
}

class _MyReportCardState extends State<_MyReportCard> {
  /// When null, expand/collapse follows [totalReportCount] vs threshold.
  bool? _userExpanded;

  Report get report => widget.report;

  bool get _isExpanded =>
      _userExpanded ?? (widget.totalReportCount < _MyReportCard._autoExpandThreshold);

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
  void didUpdateWidget(_MyReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasUnderThreshold =
        oldWidget.totalReportCount < _MyReportCard._autoExpandThreshold;
    final isUnderThreshold =
        widget.totalReportCount < _MyReportCard._autoExpandThreshold;
    if (wasUnderThreshold != isUnderThreshold) {
      _userExpanded = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KerbColors.surface,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
              IconButton(
                tooltip: _isExpanded ? 'Hide pipeline' : 'Show pipeline',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => setState(() => _userExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: KerbColors.ink600,
                ),
              ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            ReportPipelineIndicator(report: report, compact: true),
          ],
        ],
      ),
    );
  }
}
