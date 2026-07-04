import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/env.dart';
import '../models/venue.dart';

/// Google Places (New) Text Search, used to tag a report to a venue.
/// Biased to the user's GPS position so "cafe" finds the one they're at.
class PlacesApi {
  Future<List<Venue>> textSearch(String query, {required LatLng near}) async {
    if (Env.googlePlacesKey.isEmpty || query.trim().isEmpty) return [];
    final res = await http.post(
      Uri.parse('https://places.googleapis.com/v1/places:searchText'),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': Env.googlePlacesKey,
        'X-Goog-FieldMask':
            'places.id,places.displayName,places.formattedAddress,places.location',
      },
      body: jsonEncode({
        'textQuery': query,
        'pageSize': 8,
        'locationBias': {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': 500.0,
          },
        },
      }),
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final places = data['places'] as List<dynamic>? ?? [];
    return places
        .map((p) => Venue.fromPlacesJson(p as Map<String, dynamic>))
        .toList();
  }
}
