import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

enum AuthMode { signIn, signUp, forgotPassword, updatePassword }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.auth,
    this.initialMode = AuthMode.signIn,
    this.onPasswordUpdated,
  });

  final AuthService auth;
  final AuthMode initialMode;
  final VoidCallback? onPasswordUpdated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late AuthMode _mode;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode, {String? message}) {
    setState(() {
      _mode = mode;
      _password.clear();
      _message = message;
    });
  }

  String _errorMessage(Object error) {
    if (error is AuthException) {
      switch (error.code) {
        case 'invalid_credentials':
          return 'Неверный email или пароль.';
        case 'email_not_confirmed':
          return 'Подтвердите email по ссылке из письма.';
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
          return 'Слишком много запросов. Повторите попытку позже.';
        case 'email_address_not_authorized':
          return 'Отправка письма на этот адрес пока не настроена.';
      }
    }
    return 'Не удалось выполнить запрос. Проверьте данные и подключение.';
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      switch (_mode) {
        case AuthMode.signIn:
          await widget.auth.signIn(email, password);
        case AuthMode.signUp:
          final signedIn = await widget.auth.signUp(email, password);
          if (!mounted) return;
          if (!signedIn) {
            _switchMode(
              AuthMode.signIn,
              message:
                  'Если регистрация доступна, проверьте почту и подтвердите адрес.',
            );
          }
        case AuthMode.forgotPassword:
          await widget.auth.resetPassword(email);
          if (!mounted) return;
          _switchMode(
            AuthMode.signIn,
            message: 'Если аккаунт существует, инструкция отправлена на почту.',
          );
        case AuthMode.updatePassword:
          await widget.auth.updatePassword(password);
          if (!mounted) return;
          widget.onPasswordUpdated?.call();
      }
    } catch (error) {
      if (mounted) setState(() => _message = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      AuthMode.signIn => 'Вход',
      AuthMode.signUp => 'Регистрация',
      AuthMode.forgotPassword => 'Восстановление доступа',
      AuthMode.updatePassword => 'Новый пароль',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('CashRadar')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  if (_mode != AuthMode.updatePassword)
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (!RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(email)) {
                          return 'Введите корректный email.';
                        }
                        return null;
                      },
                    ),
                  if (_mode != AuthMode.forgotPassword)
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: [
                        _mode == AuthMode.signIn
                            ? AutofillHints.password
                            : AutofillHints.newPassword,
                      ],
                      decoration: InputDecoration(
                        labelText: _mode == AuthMode.updatePassword
                            ? 'Новый пароль'
                            : 'Пароль',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите пароль.';
                        }
                        if (_mode != AuthMode.signIn && value.length < 8) {
                          return 'Минимум 8 символов.';
                        }
                        return null;
                      },
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(_message!),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'Подождите…'
                          : switch (_mode) {
                              AuthMode.signIn => 'Войти',
                              AuthMode.signUp => 'Зарегистрироваться',
                              AuthMode.forgotPassword => 'Отправить письмо',
                              AuthMode.updatePassword => 'Сохранить пароль',
                            },
                    ),
                  ),
                  if (_mode == AuthMode.signIn) ...[
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _switchMode(AuthMode.signUp),
                      child: const Text('Создать аккаунт'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _switchMode(AuthMode.forgotPassword),
                      child: const Text('Забыли пароль?'),
                    ),
                  ] else if (_mode != AuthMode.updatePassword)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _switchMode(AuthMode.signIn),
                      child: const Text('Назад ко входу'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
