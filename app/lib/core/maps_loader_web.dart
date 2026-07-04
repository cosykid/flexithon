import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import 'env.dart';

/// Injects the Google Maps JavaScript API using the GOOGLE_MAPS_WEB_KEY
/// dart-define, and resolves once the script has loaded so `google.maps`
/// exists before the first GoogleMap widget builds.
Future<void> loadMapsApi() {
  if (Env.googleMapsWebKey.isEmpty) {
    debugPrint('GOOGLE_MAPS_WEB_KEY not set — web map will not render.');
    return Future.value();
  }
  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js'
        '?key=${Uri.encodeQueryComponent(Env.googleMapsWebKey)}'
    ..onload = (() => completer.complete()).toJS
    ..onerror = ((JSAny? _) {
      debugPrint('Google Maps JS failed to load — check key and origin.');
      completer.complete();
    }).toJS;
  web.document.head!.append(script);
  return completer.future;
}
