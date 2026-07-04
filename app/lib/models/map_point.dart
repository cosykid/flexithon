import 'package:latlong2/latlong.dart';

import 'report.dart';

/// One row of the points_in_bbox RPC: a visible location on the map.
class MapPoint {
  final String locationId;
  final LatLng position;
  final ReportTier tier;
  final String? name;
  final int reportCount;

  const MapPoint({
    required this.locationId,
    required this.position,
    required this.tier,
    this.name,
    required this.reportCount,
  });

  factory MapPoint.fromJson(Map<String, dynamic> json) => MapPoint(
        locationId: json['location_id'] as String,
        position: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        tier: ReportTier.fromDb(json['tier'] as String?) ?? ReportTier.unsubstantiated,
        name: json['name'] as String?,
        reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      );
}
