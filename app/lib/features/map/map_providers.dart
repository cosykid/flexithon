import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../data/fake_reports_repository.dart';
import '../../data/reports_repository.dart';
import '../../data/supabase_reports_repository.dart';
import '../../models/map_point.dart';
import '../../models/outreach.dart';
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
///
/// Refetches (pan/zoom) keep the previous points visible: the loading state
/// carries the last data forward so markers never blink out mid-gesture —
/// only `isLoading` flips for the spinner.
final mapPointsProvider = Provider<AsyncValue<List<MapPoint>>>((ref) {
  final raw = ref.watch(mapPointsRawProvider);
  final filter = ref.watch(tierFilterProvider);
  final points = raw.valueOrNull;
  if (points == null) {
    return raw.whenData(
      (p) => p.where((e) => filter.contains(e.tier)).toList(),
    );
  }
  final filtered = AsyncData(
    points.where((p) => filter.contains(p.tier)).toList(),
  );
  return raw.isLoading
      ? const AsyncValue<List<MapPoint>>.loading().copyWithPrevious(filtered)
      : filtered;
});

final locationReportsProvider =
    FutureProvider.family<List<Report>, String>((ref, locationId) {
  return ref.watch(repositoryProvider).fetchLocationReports(locationId);
});

final myReportsProvider = FutureProvider<List<Report>>((ref) {
  return ref.watch(repositoryProvider).fetchMyReports();
});

/// Server-drafted venue-outreach emails for the locations the user has
/// reported at, keyed by location id. Only locations that reached the
/// outreach threshold (see draft-outreach edge function) have an entry.
final myOutreachProvider =
    FutureProvider<Map<String, LocationOutreach>>((ref) async {
  final reports = await ref.watch(myReportsProvider.future);
  final locationIds = reports.map((r) => r.locationId).toSet();
  return ref.watch(repositoryProvider).fetchOutreach(locationIds);
});

/// Last-known status per report when the user opened My Reports.
/// Badges only reflect changes after that snapshot.
final myReportsSeenStatusesProvider =
    StateProvider<Map<String, ReportStatus>>((ref) => {});

/// Pending reports the user has not seen on My Reports yet.
final unseenPendingReportsCountProvider = Provider<int>((ref) {
  final reports = ref.watch(myReportsProvider).valueOrNull;
  if (reports == null) return 0;
  final seen = ref.watch(myReportsSeenStatusesProvider);
  return reports
      .where((r) =>
          r.status == ReportStatus.pending &&
          seen[r.id] != ReportStatus.pending)
      .length;
});

/// Newly classified reports since the user last opened My Reports.
final unseenVerifiedReportsCountProvider = Provider<int>((ref) {
  final reports = ref.watch(myReportsProvider).valueOrNull;
  if (reports == null) return 0;
  final seen = ref.watch(myReportsSeenStatusesProvider);
  return reports
      .where((r) =>
          r.status == ReportStatus.classified &&
          seen[r.id] != ReportStatus.classified)
      .length;
});

void markMyReportsSeen(WidgetRef ref) {
  final reports = ref.read(myReportsProvider).valueOrNull;
  if (reports == null) return;
  ref.read(myReportsSeenStatusesProvider.notifier).state = {
    for (final r in reports) r.id: r.status,
  };
}

/// Count of the user's reports still in AI verification (`pending`).
final pendingReportsCountProvider = Provider<int>((ref) {
  final reports = ref.watch(myReportsProvider).valueOrNull;
  if (reports == null) return 0;
  return reports.where((r) => r.status == ReportStatus.pending).length;
});

/// Count of the user's reports that finished verification successfully.
final verifiedReportsCountProvider = Provider<int>((ref) {
  final reports = ref.watch(myReportsProvider).valueOrNull;
  if (reports == null) return 0;
  return reports.where((r) => r.status == ReportStatus.classified).length;
});

/// While any report is pending, refresh My Reports every few seconds so the
/// nav badge clears when verification finishes.
final pendingReportsPollProvider = Provider<void>((ref) {
  final pending = ref.watch(pendingReportsCountProvider);
  if (pending == 0) return;

  final timer = Timer.periodic(const Duration(seconds: 3), (_) {
    ref.invalidate(myReportsProvider);
  });
  ref.onDispose(timer.cancel);
});
