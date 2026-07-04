import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../data/fake_reports_repository.dart';
import '../../data/reports_repository.dart';
import '../../data/supabase_reports_repository.dart';
import '../../models/map_point.dart';
import '../../models/report.dart';

/// True when running on fake in-memory data — either requested via
/// --dart-define=USE_FAKE=true or forced at startup because Supabase is
/// unconfigured/unreachable (main() overrides this so the app never
/// white-screens on a bad backend config).
final useFakeProvider = Provider<bool>((ref) => Env.useFake);

final repositoryProvider = Provider<ReportsRepository>(
  (ref) => ref.watch(useFakeProvider)
      ? FakeReportsRepository()
      : SupabaseReportsRepository(),
);

/// Records have structural equality, so this is a stable FutureProvider key
/// (LatLngBounds equality is not guaranteed across instances).
typedef Bbox = ({double west, double south, double east, double north});

Bbox bboxOf(LatLngBounds b) => (
      west: b.southwest.longitude,
      south: b.southwest.latitude,
      east: b.northeast.longitude,
      north: b.northeast.latitude,
    );

LatLngBounds boundsOf(Bbox b) => LatLngBounds(
      southwest: LatLng(b.south, b.west),
      northeast: LatLng(b.north, b.east),
    );

/// Current viewport, set by MapScreen after (debounced) camera idle.
final mapBboxProvider = StateProvider<Bbox?>((ref) => null);

/// Which tiers the user wants to see (filter chips).
final tierFilterProvider = StateProvider<Set<ReportTier>>(
  (ref) => {ReportTier.substantiated, ReportTier.partiallySubstantiated},
);

/// Everything in the viewport, unfiltered — the chips read this for counts.
final mapPointsRawProvider = FutureProvider<List<MapPoint>>((ref) async {
  final bbox = ref.watch(mapBboxProvider);
  if (bbox == null) return [];
  return ref.watch(repositoryProvider).fetchMapPoints(boundsOf(bbox));
});

/// The raw viewport points narrowed to the active tier filter.
final mapPointsProvider = Provider<AsyncValue<List<MapPoint>>>((ref) {
  final raw = ref.watch(mapPointsRawProvider);
  final filter = ref.watch(tierFilterProvider);
  return raw.whenData(
    (points) => points.where((p) => filter.contains(p.tier)).toList(),
  );
});

final locationReportsProvider =
    FutureProvider.family<List<Report>, String>((ref, locationId) {
  return ref.watch(repositoryProvider).fetchLocationReports(locationId);
});

final myReportsProvider = FutureProvider<List<Report>>((ref) {
  return ref.watch(repositoryProvider).fetchMyReports();
});
