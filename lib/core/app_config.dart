/// Supabase address and public (anon) key, set with `--dart-define`.
/// Do not ship them as a `.env` asset: it would be downloadable. The anon key
/// is public by design; the database rules (RLS) protect the data.
///
/// Local run:  flutter run -d chrome --dart-define-from-file=.env
/// Vercel:     vercel-build.sh passes the two values from its env settings.
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
