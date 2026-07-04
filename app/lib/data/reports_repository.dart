import 'dart:typed_data';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/map_point.dart';
import '../models/report.dart';
import '../models/venue.dart';

/// Everything the user has entered for a new report before submission.
class ReportDraft {
  final Uint8List? photoBytes; // already compressed (<=1024px, q80)
  final LatLng position;
  final Venue? venue;
  final String description;

  const ReportDraft({
    this.photoBytes,
    required this.position,
    this.venue,
    required this.description,
  });
}

abstract class ReportsRepository {
  /// Visible (partially/fully substantiated) locations in the viewport.
  Future<List<MapPoint>> fetchMapPoints(LatLngBounds bounds);

  /// Classified, visible reports at one location (newest first).
  Future<List<Report>> fetchLocationReports(String locationId);

  /// The current user's own reports, any status.
  Future<List<Report>> fetchMyReports();

  /// Uploads photo, inserts the report, kicks off AI verification.
  Future<void> submitReport(ReportDraft draft);

  /// Display URL for a report photo (signed URL for the private bucket).
  Future<String?> photoUrl(String? photoPath);
}
