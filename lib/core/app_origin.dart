/// Where this app is being served from, for building the links Supabase
/// mails out (password recovery, signup confirmation).
///
/// Use [appOrigin] instead of `Uri.base.origin`: that getter throws on
/// non-http schemes, and on Android `Uri.base` is a `file:` URL.
library;

/// The deployed web address, used when there is no browser origin.
/// Change it here if the domain changes.
const kProductionOrigin = 'https://neighbor-sync.vercel.app';

/// The browser's own origin on web; [kProductionOrigin] everywhere else.
///
/// The returned address must also be in Supabase's Redirect URLs allow
/// list, or Supabase swaps in the project's Site URL.
String appOrigin() {
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') return base.origin;
  return kProductionOrigin;
}
