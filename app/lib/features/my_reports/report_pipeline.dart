import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/report.dart';

/// One stage in the post-submit verification pipeline.
class PipelineStep {
  const PipelineStep({
    required this.label,
    required this.caption,
    required this.icon,
  });

  final String label;
  final String caption;
  final IconData icon;
}

enum PipelineStepState { complete, active, upcoming, failed, skipped }

/// Maps a [Report] to the four user-facing pipeline stages.
abstract final class ReportPipelineProgress {
  static const steps = [
    PipelineStep(
      label: 'Submitted',
      caption: 'Photo and details saved',
      icon: Icons.cloud_upload_outlined,
    ),
    PipelineStep(
      label: 'Verifying',
      caption: 'AI checks photo and venue claims',
      icon: Icons.psychology_outlined,
    ),
    PipelineStep(
      label: 'Reviewed',
      caption: 'Verification tier assigned',
      icon: Icons.fact_check_outlined,
    ),
    PipelineStep(
      label: 'On map',
      caption: 'Visible to other users',
      icon: Icons.map_outlined,
    ),
  ];

  static List<PipelineStepState> statesFor(Report report) {
    return switch (report.status) {
      ReportStatus.pending => const [
          PipelineStepState.complete,
          PipelineStepState.active,
          PipelineStepState.upcoming,
          PipelineStepState.upcoming,
        ],
      ReportStatus.rejected => const [
          PipelineStepState.complete,
          PipelineStepState.failed,
          PipelineStepState.skipped,
          PipelineStepState.skipped,
        ],
      ReportStatus.classified => switch (report.tier) {
          ReportTier.substantiated || ReportTier.partiallySubstantiated => const [
              PipelineStepState.complete,
              PipelineStepState.complete,
              PipelineStepState.complete,
              PipelineStepState.complete,
            ],
          _ => const [
              PipelineStepState.complete,
              PipelineStepState.complete,
              PipelineStepState.complete,
              PipelineStepState.skipped,
            ],
        },
    };
  }

  /// Index of the stage the user is currently in (0-based).
  static int activeIndex(Report report) {
    final states = statesFor(report);
    final active = states.indexOf(PipelineStepState.active);
    if (active >= 0) return active;
    final failed = states.indexOf(PipelineStepState.failed);
    if (failed >= 0) return failed;
    final lastComplete = states.lastIndexOf(PipelineStepState.complete);
    return lastComplete.clamp(0, steps.length - 1);
  }

  static String statusLine(Report report) {
    return switch (report.status) {
      ReportStatus.pending => 'Step ${activeIndex(report) + 1} of ${steps.length}: '
          '${steps[activeIndex(report)].label} — ${steps[activeIndex(report)].caption}',
      ReportStatus.rejected =>
        'Verification failed — the photo did not match the description.',
      ReportStatus.classified => switch (report.tier) {
          ReportTier.substantiated => 'Complete — your report is on the map.',
          ReportTier.partiallySubstantiated =>
            'Complete — on the map as partially substantiated.',
          _ => 'Reviewed — not shown on the map (unsubstantiated).',
        },
    };
  }

  /// How many reports are currently in each pipeline stage (by active index).
  static List<int> countsByStage(List<Report> reports) {
    final counts = List<int>.filled(steps.length, 0);
    for (final report in reports) {
      counts[activeIndex(report)]++;
    }
    return counts;
  }

  static PipelineStepState summaryStateForStage(
    int stageIndex,
    int count,
    List<Report> reports,
  ) {
    if (count == 0) return PipelineStepState.upcoming;
    if (stageIndex == 1) {
      if (reports.any((r) => r.status == ReportStatus.pending)) {
        return PipelineStepState.active;
      }
      if (reports.any((r) => r.status == ReportStatus.rejected)) {
        return PipelineStepState.failed;
      }
    }
    return PipelineStepState.complete;
  }
}

/// Horizontal pipeline showing where a report is in the verification flow.
class ReportPipelineIndicator extends StatelessWidget {
  const ReportPipelineIndicator({
    super.key,
    required this.report,
    this.compact = false,
  });

  final Report report;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final states = ReportPipelineProgress.statesFor(report);
    final activeIndex = ReportPipelineProgress.activeIndex(report);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PipelineRow(
          compact: compact,
          children: [
            for (var i = 0; i < ReportPipelineProgress.steps.length; i++) ...[
              if (i > 0)
                _Connector(
                  filled: states[i - 1] == PipelineStepState.complete,
                  compact: compact,
                ),
              _StepNode(
                step: ReportPipelineProgress.steps[i],
                state: states[i],
                compact: compact,
                isCurrent: i == activeIndex && states[i] == PipelineStepState.active,
              ),
            ],
          ],
        ),
        SizedBox(height: compact ? 6 : 10),
        Text(
          ReportPipelineProgress.statusLine(report),
          style: TextStyle(
            fontSize: compact ? 11.5 : 12.5,
            height: compact ? 1.3 : 1.35,
            color: _statusColor(states),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Color _statusColor(List<PipelineStepState> states) {
    if (states.contains(PipelineStepState.failed)) return KerbColors.danger;
    if (states.contains(PipelineStepState.active)) return KerbColors.brand700;
    if (states.last == PipelineStepState.complete) return KerbColors.success;
    return KerbColors.ink600;
  }
}

/// Aggregate pipeline — same layout as a report card, with counts per stage.
class ReportPipelineSummaryIndicator extends StatelessWidget {
  const ReportPipelineSummaryIndicator({
    super.key,
    required this.reports,
    this.compact = true,
  });

  final List<Report> reports;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final counts = ReportPipelineProgress.countsByStage(reports);

    return _PipelineRow(
      compact: compact,
      children: [
        for (var i = 0; i < ReportPipelineProgress.steps.length; i++) ...[
          if (i > 0)
            _Connector(
              filled: false,
              compact: compact,
            ),
          _StepNode(
            step: ReportPipelineProgress.steps[i],
            state: ReportPipelineProgress.summaryStateForStage(i, counts[i], reports),
            compact: compact,
            isCurrent: counts[i] > 0 &&
                ReportPipelineProgress.summaryStateForStage(i, counts[i], reports) ==
                    PipelineStepState.active,
            count: counts[i],
          ),
        ],
      ],
    );
  }
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.compact,
    required this.children,
  });

  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(children: children);
  }
}

class _Connector extends StatelessWidget {
  const _Connector({
    required this.filled,
    required this.compact,
  });

  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: EdgeInsets.only(bottom: compact ? 14 : 18),
        color: filled ? KerbColors.success : KerbColors.line,
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.step,
    required this.state,
    required this.compact,
    required this.isCurrent,
    this.count,
  });

  final PipelineStep step;
  final PipelineStepState state;
  final bool compact;
  final bool isCurrent;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 34.0;

    return SizedBox(
      width: compact ? 52 : 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _background,
              shape: BoxShape.circle,
              border: Border.all(color: _border, width: isCurrent ? 2 : 1),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: KerbColors.brand600.withValues(alpha: 0.25),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: count != null
                ? Text(
                    '$count',
                    style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w800,
                      color: _foreground,
                      height: 1,
                    ),
                  )
                : Icon(_icon, size: compact ? 14.0 : 17.0, color: _foreground),
          ),
          const SizedBox(height: 4),
          Text(
            step.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 9.5 : 11,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: _labelColor,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Color get _background => switch (state) {
        PipelineStepState.complete => KerbColors.success.withValues(alpha: 0.12),
        PipelineStepState.active => KerbColors.brand100,
        PipelineStepState.failed => KerbColors.dangerFill,
        PipelineStepState.skipped => KerbColors.paper,
        PipelineStepState.upcoming => KerbColors.paper,
      };

  Color get _border => switch (state) {
        PipelineStepState.complete => KerbColors.success,
        PipelineStepState.active => KerbColors.brand600,
        PipelineStepState.failed => KerbColors.danger,
        PipelineStepState.skipped => KerbColors.line,
        PipelineStepState.upcoming => KerbColors.line,
      };

  Color get _foreground => switch (state) {
        PipelineStepState.complete => KerbColors.success,
        PipelineStepState.active => KerbColors.brand700,
        PipelineStepState.failed => KerbColors.danger,
        PipelineStepState.skipped => KerbColors.ink300,
        PipelineStepState.upcoming => KerbColors.ink300,
      };

  Color get _labelColor => switch (state) {
        PipelineStepState.complete => KerbColors.success,
        PipelineStepState.active => KerbColors.brand700,
        PipelineStepState.failed => KerbColors.danger,
        PipelineStepState.skipped => KerbColors.ink300,
        PipelineStepState.upcoming => KerbColors.ink600,
      };

  IconData get _icon => switch (state) {
        PipelineStepState.complete => Icons.check_rounded,
        PipelineStepState.failed => Icons.close_rounded,
        PipelineStepState.skipped => Icons.remove_rounded,
        PipelineStepState.active || PipelineStepState.upcoming => step.icon,
      };
}

/// Static preview shown while composing a report (all stages upcoming).
class ReportSubmitPipelineHint extends StatelessWidget {
  const ReportSubmitPipelineHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What happens after you submit',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: KerbColors.ink600,
          ),
        ),
        const SizedBox(height: 10),
        _PipelineRow(
          compact: true,
          children: [
            for (var i = 0; i < ReportPipelineProgress.steps.length; i++) ...[
              if (i > 0)
                const _Connector(
                  filled: false,
                  compact: true,
                ),
              _StepNode(
                step: ReportPipelineProgress.steps[i],
                state: i == 0 ? PipelineStepState.active : PipelineStepState.upcoming,
                compact: true,
                isCurrent: i == 0,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Your report is saved, then AI verifies the photo and checks the '
          'venue\'s accessibility claims before it can appear on the map.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: KerbColors.ink600, height: 1.35),
        ),
      ],
    );
  }
}

class ReportPipelineSummaryCard extends StatelessWidget {
  const ReportPipelineSummaryCard({
    super.key,
    required this.reports,
  });

  final List<Report> reports;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KerbColors.brand100,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.brand600.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, size: 18, color: KerbColors.brand700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Summary',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: KerbColors.brand700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ReportPipelineSummaryIndicator(reports: reports),
        ],
      ),
    );
  }
}
