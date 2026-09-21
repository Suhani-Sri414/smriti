import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client bootstrap.
///
/// Per AGENTS.md non-negotiable #1, `supabase_flutter` may only be imported
/// from `lib/core/sync/` and `lib/core/auth/`, so initialization lives here
/// rather than in `main.dart`.
const String supabaseUrl = 'https://yzhtgpaekoqaszxgbeyn.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl6aHRncGFla29xYXN6eGdiZXluIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1NDc0ODksImV4cCI6MjEwNDEyMzQ4OX0.n_o6rWy3ViTKi-EGcRTfPD_9yDS00GSssWRgq7ALRoo';

/// Initializes the Supabase client. Call once, before `runApp()`.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    // supabase_flutter 2.17 deprecates `anonKey` in favour of `publishableKey`.
    // The live backend issues the legacy anon JWT above, so `anonKey` stays
    // until the project migrates to an `sb_publishable_...` key.
    // ignore: deprecated_member_use
    anonKey: supabaseAnonKey,
    authOptions:
        const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );
}

/// Whether a Supabase session exists right now.
///
/// Lives here because only `lib/core/auth/` and `lib/core/sync/` may import
/// `supabase_flutter` (AGENTS.md non-negotiable #1). If this is false the app
/// keeps working completely - games, reminders, photos - and only sync stops.
/// The elder is never told (non-negotiable #9).
/// Returns false rather than throwing when the SDK was never initialised.
/// `Supabase.instance` asserts in that case, and this is called from a
/// fire-and-forget sync where a throw becomes an unhandled async error.
bool hasSupabaseSession() {
  try {
    return Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
}

/// Retrieves the active Supabase access token (JWT), or falls back to anon key.
String? getSupabaseAccessToken() {
  try {
    return Supabase.instance.client.auth.currentSession?.accessToken ??
        supabaseAnonKey;
  } catch (_) {
    return supabaseAnonKey;
  }
}
