import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/map_point.dart';
import '../../models/report.dart';

/// A screen-space group of nearby points at the current zoom; a single point
/// is a cluster of one and renders as a pin.
class MapCluster {
  MapCluster(this.position, this.points);

  final LatLng position;
  final List<MapPoint> points;

  int get count => points.length;

  double get redFraction =>
      points.where((p) => p.tier == ReportTier.substantiated).length /
      math.max(points.length, 1);
}

/// Grid clustering in Web-Mercator pixel space: points that would land within
/// the same ~[cellPx] cell at [zoom] merge into one cluster at their centroid.
List<MapCluster> clusterMapPoints(
  List<MapPoint> points,
  double zoom, {
  double cellPx = 80,
}) {
  final worldSize = 256 * math.pow(2, zoom).toDouble();
  final cells = <({int x, int y}), List<MapPoint>>{};

  for (final p in points) {
    final x = (p.position.longitude + 180) / 360 * worldSize;
    final sinY =
        math.sin(p.position.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
    final y =
        (0.5 - math.log((1 + sinY) / (1 - sinY)) / (4 * math.pi)) * worldSize;
    final key = (x: x ~/ cellPx, y: y ~/ cellPx);
    cells.putIfAbsent(key, () => []).add(p);
  }

  return [
    for (final group in cells.values)
      MapCluster(
        group.length == 1
            ? group.first.position
            : LatLng(
                group.map((p) => p.position.latitude).reduce((a, b) => a + b) /
                    group.length,
                group.map((p) => p.position.longitude).reduce((a, b) => a + b) /
                    group.length,
              ),
        group,
      ),
  ];
}
