/// Compile-time configuration. Pass with --dart-define, e.g.:
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=STADIA_API_KEY=... \
///   --dart-define=GOOGLE_PLACES_KEY=... \
///   --dart-define=USE_FAKE=false
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const stadiaApiKey = String.fromEnvironment('STADIA_API_KEY');
  static const googlePlacesKey = String.fromEnvironment('GOOGLE_PLACES_KEY');

  /// Demo-day parachute: run the whole UI against fake in-memory data.
  static const useFake = bool.fromEnvironment('USE_FAKE', defaultValue: false);
}
