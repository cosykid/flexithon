/// Compile-time configuration. Pass with --dart-define, e.g.:
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=GOOGLE_PLACES_KEY=... \
///   --dart-define=GOOGLE_MAPS_WEB_KEY=... \
///   --dart-define=USE_FAKE=false
///
/// Native Google Maps SDK keys stay platform-side:
///   Android — MAPS_API_KEY gradle property / env var (android/app/build.gradle.kts)
///   iOS     — GMSApiKey entry in ios/Runner/Info.plist
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googlePlacesKey = String.fromEnvironment('GOOGLE_PLACES_KEY');

  /// Maps JavaScript API key, injected at startup on web (core/maps_loader.dart).
  static const googleMapsWebKey = String.fromEnvironment('GOOGLE_MAPS_WEB_KEY');

  /// Demo-day parachute: run the whole UI against fake in-memory data.
  static const useFake = bool.fromEnvironment('USE_FAKE', defaultValue: false);
}
