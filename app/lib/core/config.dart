class AppConfig {
  const AppConfig._();

  static const supabaseUrl = 'https://ztprvcfwlzxycdjeektg.supabase.co';

  // Passed at build time. A publishable key is meant to ship inside the app.
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
}
