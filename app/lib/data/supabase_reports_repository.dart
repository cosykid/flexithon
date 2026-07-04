import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase.dart';
import '../models/map_point.dart';
import '../models/report.dart';
import 'reports_repository.dart';

class SupabaseReportsRepository implements ReportsRepository {
  @override
  Future<List<MapPoint>> fetchMapPoints(LatLngBounds bounds) async {
    final rows = await supa.rpc('points_in_bbox', params: {
      'min_lng': bounds.southwest.longitude,
      'min_lat': bounds.southwest.latitude,
      'max_lng': bounds.northeast.longitude,
      'max_lat': bounds.northeast.latitude,
    }) as List<dynamic>;
    return rows
        .map((r) => MapPoint.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // Source links are joined without their URLs: the URL is looked up in
  // report_sources only when the user actually taps a link (sourceUrl).
  static const _reportSelect =
      '*, locations(name), report_sources(id, title, claim, position)';

  @override
  Future<List<Report>> fetchLocationReports(String locationId) async {
    final rows = await supa
        .from('reports')
        .select(_reportSelect)
        .eq('location_id', locationId)
        .eq('status', 'classified')
        .order('created_at', ascending: false);
    return rows.map(Report.fromJson).toList();
  }

  @override
  Future<List<Report>> fetchMyReports() async {
    final uid = supa.auth.currentUser!.id;
    final rows = await supa
        .from('reports')
        .select(_reportSelect)
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return rows.map(Report.fromJson).toList();
  }

  @override
  Future<String> submitReport(ReportDraft draft) async {
    final uid = supa.auth.currentUser!.id;

    final locationId = await supa.rpc('upsert_location', params: {
      'p_lat': draft.venue?.position.latitude ?? draft.position.latitude,
      'p_lng': draft.venue?.position.longitude ?? draft.position.longitude,
      'p_place_ref': draft.venue?.placeId,
      'p_name': draft.venue?.name,
      'p_address': draft.venue?.address,
    }) as String;

    String? photoPath;
    if (draft.photoBytes != null) {
      photoPath = '$uid/${const Uuid().v4()}.jpg';
      await supa.storage.from('report-photos').uploadBinary(
            photoPath,
            draft.photoBytes!,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    }

    final inserted = await supa
        .from('reports')
        .insert({
          'user_id': uid,
          'location_id': locationId,
          'geog':
              'SRID=4326;POINT(${draft.position.longitude} ${draft.position.latitude})',
          'photo_path': photoPath,
          'description': draft.description,
        })
        .select('id')
        .single();

    // Fire-and-forget: verification runs server-side; the report shows as
    // pending in My Reports until classified. The sweep path catches drops.
    // ignore: unawaited_futures
    supa.functions
        .invoke('classify-report', body: {'report_id': inserted['id']})
        .then((_) {}, onError: (_) {});

    return inserted['id'] as String;
  }

  @override
  Future<Report?> fetchReport(String reportId) async {
    final row = await supa
        .from('reports')
        .select(_reportSelect)
        .eq('id', reportId)
        .maybeSingle();
    return row == null ? null : Report.fromJson(row);
  }

  @override
  Future<String?> photoUrl(String? photoPath) async {
    if (photoPath == null) return null;
    return supa.storage.from('report-photos').createSignedUrl(photoPath, 3600);
  }

  @override
  Future<String?> sourceUrl(AiSource source) async {
    final row = await supa
        .from('report_sources')
        .select('url')
        .eq('id', source.id)
        .maybeSingle();
    return row?['url'] as String?;
  }
}
