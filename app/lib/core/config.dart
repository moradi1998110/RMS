class AppConfig {
  const AppConfig._();

  // Can be pointed at another server, such as a self-hosted one, at build time.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://ztprvcfwlzxycdjeektg.supabase.co');

  // Passed at build time. A publishable key is meant to ship inside the app.
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Android's version code, passed at build time. It is 0 in development and tests,
  /// where no update is ever offered.
  static const appBuild = int.fromEnvironment('APP_BUILD');
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'تجريبي');
}
