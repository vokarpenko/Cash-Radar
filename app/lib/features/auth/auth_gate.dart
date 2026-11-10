import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import 'auth_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, this.initialRecovery = false});

  final AuthService auth;
  final bool initialRecovery;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  late bool _hasSession;
  late bool _recovery;

  @override
  void initState() {
    super.initState();
    _hasSession = widget.auth.hasSession;
    _recovery = widget.initialRecovery && _hasSession;
    _subscription = widget.auth.changes.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          _hasSession = state.session != null && !state.session!.isExpired;
          if (state.event == AuthChangeEvent.passwordRecovery) _recovery = true;
          if (state.event == AuthChangeEvent.signedOut) _recovery = false;
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось обновить сессию. Проверьте подключение.'),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSession && _recovery) {
      return AuthScreen(
        auth: widget.auth,
        initialMode: AuthMode.updatePassword,
        onPasswordUpdated: () {
          if (kIsWeb) {
            unawaited(
              SystemNavigator.routeInformationUpdated(
                uri: Uri(path: Uri.base.path),
                replace: true,
              ),
            );
          }
          setState(() => _recovery = false);
        },
      );
    }
    if (!_hasSession) return AuthScreen(auth: widget.auth);
    return Scaffold(
      appBar: AppBar(title: const Text('CashRadar')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Вы вошли в CashRadar.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.auth.signOut();
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Не удалось выйти. Повторите попытку.'),
                    ),
                  );
                }
              },
              child: const Text('Выйти'),
            ),
          ],
        ),
      ),
    );
  }
}
