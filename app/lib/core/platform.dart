import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// google_maps_flutter renders on Android, iOS and web. Desktop trial builds
/// get a graceful fallback instead of a MissingPluginException — run the
/// trial in Chrome to see the map.
final bool mapsSupported = kIsWeb || Platform.isAndroid || Platform.isIOS;
