import 'package:accessmap/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tier parses from db values', () {
    expect(ReportTier.fromDb('substantiated'), ReportTier.substantiated);
    expect(ReportTier.fromDb('partially_substantiated'),
        ReportTier.partiallySubstantiated);
    expect(ReportTier.fromDb('unsubstantiated'), ReportTier.unsubstantiated);
    expect(ReportTier.fromDb(null), isNull);
  });
}
