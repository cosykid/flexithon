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
  /// Returns the new report's id so callers can watch its verification.
  Future<String> submitReport(ReportDraft draft);

  /// One of the current user's reports, or null if gone. Used to poll
  /// verification progress after submitting.
  Future<Report?> fetchReport(String reportId);

  /// Display URL for a report photo (signed URL for the private bucket).
  Future<String?> photoUrl(String? photoPath);

  /// The destination URL for an AI-verification source link, resolved at
  /// click time (fetched from the report_sources table on the backend).
  Future<String?> sourceUrl(AiSource source);
}
