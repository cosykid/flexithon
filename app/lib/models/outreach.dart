/// A ready-to-send venue-outreach email drafted server-side once a location
/// accumulates enough classified reports (see draft-outreach edge function).
class LocationOutreach {
  final String locationId;
  final String status; // pending | drafted | no_email_found | failed
  final String? businessEmail;
  final String? subject;
  final String? body;

  const LocationOutreach({
    required this.locationId,
    required this.status,
    this.businessEmail,
    this.subject,
    this.body,
  });

  bool get sendable => status == 'drafted' && businessEmail != null;

  /// Draft exists but no address found — user can still copy the letter.
  bool get copyOnly => status == 'no_email_found' && (body ?? '').isNotEmpty;

  factory LocationOutreach.fromJson(Map<String, dynamic> json) {
    return LocationOutreach(
      locationId: json['location_id'] as String,
      status: json['status'] as String? ?? 'pending',
      businessEmail: json['business_email'] as String?,
      subject: json['subject'] as String?,
      body: json['body'] as String?,
    );
  }

  /// mailto: URI that opens the user's mail app with the draft pre-filled.
  /// mailto cannot carry attachments — photo links are already in [body].
  Uri get mailtoUri => Uri(
        scheme: 'mailto',
        path: businessEmail ?? '',
        query: 'subject=${Uri.encodeComponent(subject ?? '')}'
            '&body=${Uri.encodeComponent(body ?? '')}',
      );
}
