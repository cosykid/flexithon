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
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    final reasoning = json['ai_reasoning'];
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
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
