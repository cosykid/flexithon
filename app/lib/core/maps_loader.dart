// Web needs the Maps JavaScript API injected before the first GoogleMap
// widget builds; native platforms get a no-op.
export 'maps_loader_stub.dart' if (dart.library.js_interop) 'maps_loader_web.dart';
