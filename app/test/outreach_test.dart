import 'package:accessmap/models/outreach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocationOutreach', () {
    test('mailto URI encodes subject and body', () {
      const o = LocationOutreach(
        locationId: 'loc-1',
        status: 'drafted',
        businessEmail: 'venue@example.com',
        subject: 'Accessibility barrier: stairs & no ramp',
        body: 'Line one.\n\nPhotos:\nhttps://x.example/1.jpg',
      );
      expect(o.sendable, isTrue);
      final uri = o.mailtoUri;
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'venue@example.com');
      // Round-trip: mail clients decode the query back to the original text.
      expect(uri.queryParameters['subject'],
          'Accessibility barrier: stairs & no ramp');
      expect(uri.queryParameters['body'],
          'Line one.\n\nPhotos:\nhttps://x.example/1.jpg');
      // Raw query must not contain unencoded & from the subject text.
      expect(uri.query, isNot(contains('& no ramp')));
    });

    test('no_email_found draft is copy-only, not sendable', () {
      const o = LocationOutreach(
        locationId: 'loc-2',
        status: 'no_email_found',
        body: 'Draft text',
      );
      expect(o.sendable, isFalse);
      expect(o.copyOnly, isTrue);
    });

    test('pending row shows no action', () {
      const o = LocationOutreach(locationId: 'loc-3', status: 'pending');
      expect(o.sendable, isFalse);
      expect(o.copyOnly, isFalse);
    });
  });
}
