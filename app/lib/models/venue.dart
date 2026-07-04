import 'package:latlong2/latlong.dart';

/// A Google Places Text Search result used for tagging a report to a venue.
class Venue {
  final String placeId;
  final String name;
  final String? address;
  final LatLng position;

  const Venue({
    required this.placeId,
    required this.name,
    this.address,
    required this.position,
  });

  factory Venue.fromPlacesJson(Map<String, dynamic> json) => Venue(
        placeId: json['id'] as String,
        name: (json['displayName'] as Map<String, dynamic>?)?['text'] as String? ?? 'Unknown',
        address: json['formattedAddress'] as String?,
        position: LatLng(
          ((json['location'] as Map<String, dynamic>?)?['latitude'] as num?)?.toDouble() ?? 0,
          ((json['location'] as Map<String, dynamic>?)?['longitude'] as num?)?.toDouble() ?? 0,
        ),
      );
}
