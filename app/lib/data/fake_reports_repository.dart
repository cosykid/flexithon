import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_point.dart';
import '../models/outreach.dart';
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

    // Seed My Reports so the pipeline UI, tier spectrum and outreach button
    // all have something to show on a cold demo boot. The substantiated one
    // sits at an outreach-eligible location (substantiated, 5+ reports).
    final outreachPoint = _points.firstWhere(
      (p) => p.tier == ReportTier.substantiated && p.reportCount >= 5,
      orElse: () => _points.first,
    );
    final now = DateTime.now();
    _mine.addAll([
      Report(
        id: 'mine-seed-0',
        locationId: outreachPoint.locationId,
        locationName: outreachPoint.name,
        description: 'Entrance is up a flight of stairs, no ramp anywhere.',
        barrierType: 'stairs',
        status: ReportStatus.classified,
        tier: ReportTier.substantiated,
        imageConfirmsBarrier: true,
        aiReasoning: 'Demo mode: photo shows the stepped entrance clearly.',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Report(
        id: 'mine-seed-1',
        locationId: 'fake-0',
        locationName: 'Demo location 0',
        description: 'Door too narrow for my chair, staff had to unload via café.',
        barrierType: 'narrow_entrance',
        status: ReportStatus.classified,
        tier: ReportTier.partiallySubstantiated,
        imageConfirmsBarrier: true,
        venueClaimsAccessible: true,
        aiReasoning:
            'Demo mode: photo shows the narrow door; venue claims accessibility online.',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      Report(
        id: 'mine-seed-2',
        locationId: 'fake-1',
        locationName: 'Demo location 1',
        description: 'Lift out of order again.',
        status: ReportStatus.classified,
        tier: ReportTier.unsubstantiated,
        aiReasoning: 'Demo mode: no photo was provided, claim can\'t be verified.',
        createdAt: now.subtract(const Duration(days: 8)),
      ),
    ]);
    _outreachLocationId = outreachPoint.locationId;
  }

  final List<MapPoint> _points = [];
  final List<Report> _mine = [];
  final Set<String> _photolessMine = {};
  late final String _outreachLocationId;

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
        aiSources: [
          if (point.tier == ReportTier.partiallySubstantiated)
            const AiSource(
              id: 'fake-src-maps',
              title: 'Google Maps listing',
              claim: 'Venue claims wheelchair accessibility on Google Maps',
              url: 'https://www.google.com/maps/place/?q=place_id:demo',
            ),
          if (point.tier == ReportTier.substantiated)
            const AiSource(
              id: 'fake-src-review',
              title: 'Local accessibility review',
              claim: 'Review mentions stepped entrance with no ramp',
              url: 'https://example.com/accessibility-review',
            ),
        ],
        createdAt: DateTime.now().subtract(Duration(days: i * 3)),
      ),
    );
  }

  @override
  Future<List<Report>> fetchMyReports() async {
    for (var i = 0; i < _mine.length; i++) {
      _mine[i] = _matured(_mine[i]);
    }
    return List.of(_mine);
  }

  @override
  Future<String> submitReport(ReportDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final id = 'mine-${_mine.length}';
    if (draft.photoBytes == null) _photolessMine.add(id);
    _mine.insert(
      0,
      Report(
        id: id,
        locationId: 'mine-loc-${_mine.length}',
        locationName: draft.venue?.name,
        description: draft.description,
        status: ReportStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<Report?> fetchReport(String reportId) async {
    final i = _mine.indexWhere((r) => r.id == reportId);
    if (i < 0) return null;
    return _mine[i] = _matured(_mine[i]);
  }

  /// Simulate the AI pipeline: classifies ~6s after submission, mirroring
  /// the real rules — no photo dead-ends at unsubstantiated.
  Report _matured(Report report) {
    if (report.status != ReportStatus.pending ||
        DateTime.now().difference(report.createdAt).inSeconds < 6) {
      return report;
    }
    final hasPhoto = !_photolessMine.contains(report.id);
    return Report(
      id: report.id,
      locationId: report.locationId,
      locationName: report.locationName,
      description: report.description,
      barrierType: hasPhoto ? 'stairs' : null,
      status: ReportStatus.classified,
      tier: hasPhoto ? ReportTier.substantiated : ReportTier.unsubstantiated,
      imageConfirmsBarrier: hasPhoto ? true : null,
      aiReasoning: hasPhoto
          ? 'Demo mode: simulated verification — photo shows the barrier.'
          : 'Demo mode: no photo was provided, so the claim can\'t be verified.',
      createdAt: report.createdAt,
    );
  }

  @override
  Future<String?> photoUrl(String? photoPath) async => null;

  @override
  Future<String?> sourceUrl(AiSource source) async => source.url;

  @override
  Future<Map<String, LocationOutreach>> fetchOutreach(
      Set<String> locationIds) async {
    // Mirror the real gating: only the seeded substantiated location with
    // 5+ reports has a draft — not every location the user touched.
    if (!locationIds.contains(_outreachLocationId)) return {};
    return {
      _outreachLocationId: LocationOutreach(
        locationId: _outreachLocationId,
        status: 'drafted',
        businessEmail: 'access@demo-venue.example',
        subject: 'Accessibility barrier reports at your venue',
        body: 'Hello,\n\nSeveral community members have reported an '
            'accessibility barrier at your venue (stairs at the entrance '
            'with no ramp). Could you share your plans for an accessible '
            'entrance?\n\nKind regards,',
      ),
    };
  }
}
