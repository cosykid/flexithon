import 'package:accessmap/features/my_reports/report_pipeline.dart';
import 'package:accessmap/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

Report _report({
  required ReportStatus status,
  ReportTier? tier,
}) {
  return Report(
    id: 'r1',
    locationId: 'loc1',
    description: 'steps',
    status: status,
    tier: tier,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('pending report is active on verifying stage', () {
    final states = ReportPipelineProgress.statesFor(_report(status: ReportStatus.pending));
    expect(states[1], PipelineStepState.active);
    expect(ReportPipelineProgress.activeIndex(_report(status: ReportStatus.pending)), 1);
  });

  test('substantiated report completes all stages', () {
    final report = _report(
      status: ReportStatus.classified,
      tier: ReportTier.substantiated,
    );
    expect(ReportPipelineProgress.statesFor(report), everyElement(PipelineStepState.complete));
  });

  test('unsubstantiated report skips on-map stage', () {
    final report = _report(
      status: ReportStatus.classified,
      tier: ReportTier.unsubstantiated,
    );
    final states = ReportPipelineProgress.statesFor(report);
    expect(states[3], PipelineStepState.skipped);
  });

  test('rejected report fails at verifying stage', () {
    final states = ReportPipelineProgress.statesFor(_report(status: ReportStatus.rejected));
    expect(states[1], PipelineStepState.failed);
  });

  test('countsByStage groups reports by active stage', () {
    final reports = [
      _report(status: ReportStatus.pending),
      _report(status: ReportStatus.pending),
      _report(status: ReportStatus.classified, tier: ReportTier.substantiated),
      _report(status: ReportStatus.classified, tier: ReportTier.unsubstantiated),
      _report(status: ReportStatus.rejected),
    ];
    expect(ReportPipelineProgress.countsByStage(reports), [0, 3, 1, 1]);
  });
}
