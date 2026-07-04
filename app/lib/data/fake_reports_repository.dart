import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_point.dart';
import '../models/report.dart';
import 'reports_repository.dart';

/// In-memory data for Day-1 UI development and as the demo-day network
/// parachute (--dart-define=USE_FAKE=true). Points scattered around Sydney.
class FakeReportsRepository implements ReportsRepository {
  FakeReportsRepository() {
    final rng = math.Random(42);
    const center = LatLng(-33.8988, 151.2093); // Sydney
    for (var i = 0; i < 30; i++) {
      final tier = i % 3 == 0
          ? ReportTier.partiallySubstantiated
          : ReportTier.substantiated;
      _points.add(MapPoint(
        locationId: 'fake-$i',
        position: LatLng(
          center.latitude + (rng.nextDouble() - 0.5) * 0.12,
          center.longitude + (rng.nextDouble() - 0.5) * 0.14,
        ),
        tier: tier,
        name: 'Demo location $i',
        reportCount: 1 + rng.nextInt(6),
      ));
    }
  }

  final List<MapPoint> _points = [];
  final List<Report> _mine = [];

  @override
  Future<List<MapPoint>> fetchMapPoints(LatLngBounds bounds) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _points.where((p) => bounds.contains(p.position)).toList();
  }

  @override
  Future<List<Report>> fetchLocationReports(String locationId) async {
    final point = _points.firstWhere((p) => p.locationId == locationId);
    return List.generate(
      point.reportCount,
      (i) => Report(
        id: '$locationId-r$i',
        locationId: locationId,
        locationName: point.name,
        description:
            'Entrance only reachable via a flight of stairs, no ramp anywhere nearby.',
        barrierType: 'stairs',
        status: ReportStatus.classified,
        tier: point.tier,
        imageConfirmsBarrier: true,
        venueClaimsAccessible:
            point.tier == ReportTier.partiallySubstantiated ? true : null,
        webCorroborationFound: point.tier == ReportTier.substantiated,
        aiReasoning:
            'The photo clearly shows a stepped entrance with no ramp in frame.',
        createdAt: DateTime.now().subtract(Duration(days: i * 3)),
      ),
    );
  }

  @override
  Future<List<Report>> fetchMyReports() async => List.of(_mine);

  @override
  Future<void> submitReport(ReportDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _mine.insert(
      0,
      Report(
        id: 'mine-${_mine.length}',
        locationId: 'fake-mine',
        locationName: draft.venue?.name,
        description: draft.description,
        status: ReportStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<String?> photoUrl(String? photoPath) async => null;
}
