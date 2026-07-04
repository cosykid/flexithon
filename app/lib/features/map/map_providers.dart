import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env.dart';
import '../../data/fake_reports_repository.dart';
import '../../data/reports_repository.dart';
import '../../data/supabase_reports_repository.dart';
import '../../models/map_point.dart';
import '../../models/report.dart';

final repositoryProvider = Provider<ReportsRepository>(
  (ref) => Env.useFake ? FakeReportsRepository() : SupabaseReportsRepository(),
);

/// Records have structural equality, so this is a stable FutureProvider key
/// (LatLngBounds equality is not guaranteed across instances).
typedef Bbox = ({double west, double south, double east, double north});

Bbox bboxOf(LatLngBounds b) =>
    (west: b.west, south: b.south, east: b.east, north: b.north);

LatLngBounds boundsOf(Bbox b) => LatLngBounds(
      LatLng(b.south, b.west),
      LatLng(b.north, b.east),
    );

/// Current viewport, set by MapScreen after (debounced) map movement.
final mapBboxProvider = StateProvider<Bbox?>((ref) => null);

/// Which tiers the user wants to see (filter chips).
final tierFilterProvider = StateProvider<Set<ReportTier>>(
  (ref) => {ReportTier.substantiated, ReportTier.partiallySubstantiated},
);

final mapPointsProvider = FutureProvider<List<MapPoint>>((ref) async {
  final bbox = ref.watch(mapBboxProvider);
  if (bbox == null) return [];
  final points =
      await ref.watch(repositoryProvider).fetchMapPoints(boundsOf(bbox));
  final filter = ref.watch(tierFilterProvider);
  return points.where((p) => filter.contains(p.tier)).toList();
});

final locationReportsProvider =
    FutureProvider.family<List<Report>, String>((ref, locationId) {
  return ref.watch(repositoryProvider).fetchLocationReports(locationId);
});

final myReportsProvider = FutureProvider<List<Report>>((ref) {
  return ref.watch(repositoryProvider).fetchMyReports();
});
