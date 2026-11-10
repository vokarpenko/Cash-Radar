import 'package:cash_radar/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires both configuration values', () {
    expect(
      const AppConfig(url: '', publishableKey: '').validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        url: 'https://example.com',
        publishableKey: '',
      ).validationError,
      isNotNull,
    );
  });

  test('requires an HTTPS URL', () {
    expect(
      const AppConfig(
        url: 'http://example.com',
        publishableKey: 'key',
      ).validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        url: 'https://example.com',
        publishableKey: 'key',
      ).validationError,
      isNull,
    );
  });

  test('allows local HTTP only when explicitly enabled', () {
    expect(
      const AppConfig(
        url: 'http://127.0.0.1:54321',
        publishableKey: 'key',
      ).validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        url: 'http://127.0.0.1:54321',
        publishableKey: 'key',
        allowInsecureLocal: true,
      ).validationError,
      isNull,
    );
    expect(
      const AppConfig(
        url: 'http://example.com',
        publishableKey: 'key',
        allowInsecureLocal: true,
      ).validationError,
      isNotNull,
    );
  });
}
