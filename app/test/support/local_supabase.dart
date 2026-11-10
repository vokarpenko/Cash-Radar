import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryVerifierStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }
}

Future<String> readLocalMailLink(String email) async {
  final client = HttpClient();
  try {
    final uri = Uri.http('127.0.0.1:54324', '/view/latest.html', {
      'query': 'to:$email',
    });
    for (var attempt = 0; attempt < 30; attempt++) {
      final response = await (await client.getUrl(uri)).close();
      final html = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        final match = RegExp(
          r'href="([^"]+/auth/v1/verify[^"]+)"',
        ).firstMatch(html);
        if (match != null) return match.group(1)!.replaceAll('&amp;', '&');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Local confirmation email was not captured');
  } finally {
    client.close(force: true);
  }
}

Future<void> followLocalMailLink(SupabaseClient client, String link) async {
  final uri = Uri.parse(link);
  if (uri.host != '127.0.0.1' && uri.host != 'localhost') {
    throw StateError('Refusing to follow a non-local email link');
  }
  final http = HttpClient();
  try {
    final request = await http.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    final redirect = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (redirect == null) throw StateError('Local email link had no redirect');
    final code = Uri.parse(redirect).queryParameters['code'];
    if (code == null) throw StateError('Local email redirect had no PKCE code');
    await client.auth.exchangeCodeForSession(code);
  } finally {
    http.close(force: true);
  }
}

Future<void> localSql(String sql) async {
  final result = await Process.run('docker', [
    'exec',
    'supabase_db_Cash-Radar',
    'psql',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-v',
    'ON_ERROR_STOP=1',
    '-c',
    sql,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Local SQL test failed: ${result.stderr}');
  }
}
