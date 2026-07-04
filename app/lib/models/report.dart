enum ReportTier {
  unsubstantiated,
  partiallySubstantiated,
  substantiated;

  static ReportTier? fromDb(String? value) => switch (value) {
        'unsubstantiated' => ReportTier.unsubstantiated,
        'partially_substantiated' => ReportTier.partiallySubstantiated,
        'substantiated' => ReportTier.substantiated,
        _ => null,
      };
}

enum ReportStatus {
  pending,
  classified,
  rejected;

  static ReportStatus fromDb(String value) => switch (value) {
        'classified' => ReportStatus.classified,
        'rejected' => ReportStatus.rejected,
        _ => ReportStatus.pending,
      };
}

/// A link to where the AI verifier found the information backing a claim.
/// The URL lives in the `report_sources` table and is fetched from Supabase
/// at click time via [ReportsRepository.sourceUrl]; [url] is only pre-filled
/// by the fake repository.
class AiSource {
  final String id;
  final String? title;
  final String? claim;
  final String? url;

  const AiSource({required this.id, this.title, this.claim, this.url});

  static AiSource? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return AiSource(
      id: id,
      title: json['title'] as String?,
      claim: json['claim'] as String?,
    );
  }
}

class Report {
  final String id;
  final String locationId;
  final String? locationName;
  final String? photoPath;
  final String description;
  final String? barrierType;
  final ReportStatus status;
  final ReportTier? tier;
  final bool? imageConfirmsBarrier;
  final bool? venueClaimsAccessible;
  final bool? webCorroborationFound;
  final String? aiReasoning;
  final List<AiSource> aiSources;
  final DateTime createdAt;

  const Report({
    required this.id,
    required this.locationId,
    this.locationName,
    this.photoPath,
    required this.description,
    this.barrierType,
    required this.status,
    this.tier,
    this.imageConfirmsBarrier,
    this.venueClaimsAccessible,
    this.webCorroborationFound,
    this.aiReasoning,
    this.aiSources = const [],
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    final reasoning = json['ai_reasoning'];
    final sourceRows = json['report_sources'] is List
        ? List<dynamic>.of(json['report_sources'] as List)
        : const <dynamic>[];
    sourceRows.sort((a, b) {
      final pa = a is Map ? (a['position'] as int? ?? 0) : 0;
      final pb = b is Map ? (b['position'] as int? ?? 0) : 0;
      return pa.compareTo(pb);
    });
    return Report(
      id: json['id'] as String,
      locationId: json['location_id'] as String,
      locationName: (json['locations'] as Map<String, dynamic>?)?['name'] as String?,
      photoPath: json['photo_path'] as String?,
      description: json['description'] as String? ?? '',
      barrierType: json['barrier_type'] as String?,
      status: ReportStatus.fromDb(json['status'] as String? ?? 'pending'),
      tier: ReportTier.fromDb(json['tier'] as String?),
      imageConfirmsBarrier: json['image_confirms_barrier'] as bool?,
      venueClaimsAccessible: json['venue_claims_accessible'] as bool?,
      webCorroborationFound: json['web_corroboration_found'] as bool?,
      aiReasoning: reasoning is Map ? reasoning['reasoning'] as String? : null,
      aiSources:
          sourceRows.map(AiSource.fromJson).whereType<AiSource>().toList(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
