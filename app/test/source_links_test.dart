import 'package:accessmap/data/fake_reports_repository.dart';
import 'package:accessmap/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI source links', () {
    test('Report.fromJson parses source metadata without eager URLs', () {
      final report = Report.fromJson({
        'id': 'report-1',
        'location_id': 'location-1',
        'description': 'Two stairs at the entrance.',
        'status': 'classified',
        'tier': 'partially_substantiated',
        'ai_reasoning': {
          'reasoning': 'Photo shows stairs, venue claims accessibility.',
          // Legacy/inlined URLs should not be used by the app anymore.
          'sources': [
            {
              'url': 'https://example.com/legacy',
              'title': 'Legacy source',
              'claim': 'Legacy claim',
            },
          ],
        },
        'report_sources': [
          {
            'id': 'source-2',
            'title': 'Second source',
            'claim': 'Second claim',
            'position': 2,
          },
          {'title': 'Malformed source without an id', 'position': 1},
          {
            'id': 'source-1',
            'title': 'First source',
            'claim': 'First claim',
            'position': 1,
          },
        ],
        'created_at': '2026-07-04T06:00:00Z',
      });

      expect(report.aiReasoning, 'Photo shows stairs, venue claims accessibility.');
      expect(report.aiSources.map((s) => s.id), ['source-1', 'source-2']);
      expect(report.aiSources.first.title, 'First source');
      expect(report.aiSources.first.claim, 'First claim');
      expect(report.aiSources.every((s) => s.url == null), isTrue);
    });

    test('fake partial report exposes citation metadata and resolves URL on tap', () async {
      final repo = FakeReportsRepository();

      final reports = await repo.fetchLocationReports('fake-0');
      final report = reports.first;
      final source = report.aiSources.single;
      final url = await repo.sourceUrl(source);

      expect(report.tier, ReportTier.partiallySubstantiated);
      expect(source.title, 'Google Maps listing');
      expect(source.claim, 'Venue claims wheelchair accessibility on Google Maps');
      expect(url, 'https://www.google.com/maps/place/?q=place_id:demo');
    });

    test('fake substantiated report resolves its review source URL', () async {
      final repo = FakeReportsRepository();

      final reports = await repo.fetchLocationReports('fake-1');
      final report = reports.first;
      final source = report.aiSources.single;

      expect(report.tier, ReportTier.substantiated);
      expect(await repo.sourceUrl(source), 'https://example.com/accessibility-review');
    });
  });
}
