import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

class NotificationCollectorStatus {
  const NotificationCollectorStatus({
    required this.permission,
    required this.enabled,
    this.deviceId,
    this.ownerId,
    this.queued = 0,
    this.dropped = 0,
  });
  final bool permission, enabled;
  final String? deviceId, ownerId;
  final int queued, dropped;
}

/// Native module holds a scoped device credential, never the Supabase session.
class NotificationBridge {
  static const _channel = MethodChannel('cashradar/notifications');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<NotificationCollectorStatus> status() async {
    if (!supported) {
      return const NotificationCollectorStatus(
        permission: false,
        enabled: false,
      );
    }
    final data =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return NotificationCollectorStatus(
      permission: data['permission'] == true,
      enabled: data['enabled'] == true,
      deviceId: data['deviceId'] as String?,
      ownerId: data['ownerId'] as String?,
      queued: data['queued'] as int? ?? 0,
      dropped: data['dropped'] as int? ?? 0,
    );
  }

  static Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  static Future<void> syncOwner(String? userId) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('syncOwner', {'userId': userId});
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> enable(
    SupabaseClient client,
    String userId,
    AppConfig config,
  ) async {
    if (!supported ||
        config.validationError != null ||
        client.auth.currentUser?.id != userId) {
      throw StateError('Unavailable');
    }
    final initial = await status();
    if (!initial.permission) throw StateError('Permission required');
    final created = await client.rpc('register_notification_device');
    final id = created['device_id'] as String;
    final token = created['device_token'] as String;
    try {
      if (client.auth.currentUser?.id != userId) {
        throw StateError('Session changed');
      }
      await _channel.invokeMethod<void>('activate', {
        'userId': userId,
        'deviceId': id,
        'token': token,
        'url': config.url,
        'publicKey': config.publishableKey,
        'allowLocal': config.allowInsecureLocal,
      });
      if (client.auth.currentUser?.id != userId) {
        await syncOwner(client.auth.currentUser?.id);
        throw StateError('Session changed');
      }
      if (initial.deviceId != null) {
        try {
          await client.rpc(
            'revoke_notification_device',
            params: {'p_device': initial.deviceId},
          );
        } catch (_) {
          /* old device remains inaccessible locally */
        }
      }
    } catch (_) {
      try {
        await client.rpc(
          'revoke_notification_device',
          params: {'p_device': id},
        );
      } catch (_) {
        /* device expires automatically */
      }
      rethrow;
    }
  }

  static Future<void> disable(SupabaseClient client) async {
    if (!supported) return;
    String? id;
    try {
      id = (await status()).deviceId;
    } on MissingPluginException {
      return;
    }
    await _channel.invokeMethod<void>('deactivate');
    if (id != null) {
      try {
        await client.rpc(
          'revoke_notification_device',
          params: {'p_device': id},
        );
      } catch (_) {
        /* local credential already removed */
      }
    }
  }
}
