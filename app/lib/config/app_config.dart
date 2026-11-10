class AppConfig {
  const AppConfig({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;

  static AppConfig fromEnvironment() => const AppConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  String? get validationError {
    if (url.isEmpty || publishableKey.isEmpty) {
      return 'Укажите SUPABASE_URL и SUPABASE_PUBLISHABLE_KEY в конфигурации.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      return 'SUPABASE_URL должен быть действительным HTTPS-адресом.';
    }
    return null;
  }
}
