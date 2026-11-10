class AppConfig {
  const AppConfig({
    required this.url,
    required this.publishableKey,
    this.allowInsecureLocal = false,
  });

  final String url;
  final String publishableKey;
  final bool allowInsecureLocal;

  static AppConfig fromEnvironment() => const AppConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    allowInsecureLocal: bool.fromEnvironment('ALLOW_INSECURE_LOCAL_SUPABASE'),
  );

  String? get validationError {
    if (url.isEmpty || publishableKey.isEmpty) {
      return 'Укажите SUPABASE_URL и SUPABASE_PUBLISHABLE_KEY в конфигурации.';
    }
    final uri = Uri.tryParse(url);
    final localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
    final allowedLocal =
        uri != null &&
        allowInsecureLocal &&
        uri.scheme == 'http' &&
        localHosts.contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && !allowedLocal)) {
      return 'SUPABASE_URL должен использовать HTTPS или разрешённый локальный адрес.';
    }
    return null;
  }
}
