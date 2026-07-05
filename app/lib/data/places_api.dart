import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../models/venue.dart';

/// Google Places (New) Text Search, used to tag a report to a venue.
/// Biased to the user's GPS position so "cafe" finds the one they're at.
class PlacesApi {
  /// [radiusMeters] biases results toward [near]. Venue tagging uses a tight
  /// radius; map search uses a wider one so users can jump across the city.
  Future<List<Venue>> textSearch(
    String query, {
    required LatLng near,
    double radiusMeters = 500,
  }) async {
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
            'radius': radiusMeters,
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
