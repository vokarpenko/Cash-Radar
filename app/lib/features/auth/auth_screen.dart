import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_theme.dart';
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
  bool _showPassword = false;
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
      _showPassword = false;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = switch (_mode) {
      AuthMode.signIn => 'Рады видеть вас',
      AuthMode.signUp => 'Создать аккаунт',
      AuthMode.forgotPassword => 'Восстановление доступа',
      AuthMode.updatePassword => 'Новый пароль',
    };
    final subtitle = switch (_mode) {
      AuthMode.signIn => 'Войдите, чтобы управлять финансами',
      AuthMode.signUp => 'Начните собирать финансы в одном месте',
      AuthMode.forgotPassword =>
        'Отправим инструкцию для восстановления на вашу почту',
      AuthMode.updatePassword => 'Придумайте новый пароль для вашего аккаунта',
    };
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.yellow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Icon(Icons.circle, color: AppColors.ink, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Text('CashRadar', style: theme.textTheme.titleLarge),
      ],
    );
    final form = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          if (_mode != AuthMode.updatePassword) ...[
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                filled: true,
                fillColor: scheme.surface,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Введите корректный email.';
                }
                return null;
              },
            ),
          ],
          if (_mode != AuthMode.forgotPassword) ...[
            if (_mode != AuthMode.updatePassword) const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              autofillHints: [
                _mode == AuthMode.signIn
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              decoration: InputDecoration(
                labelText: _mode == AuthMode.updatePassword
                    ? 'Новый пароль'
                    : 'Пароль',
                filled: true,
                fillColor: scheme.surface,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Скрыть пароль' : 'Показать пароль',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Введите пароль.';
                if (_mode != AuthMode.signIn && value.length < 8) {
                  return 'Минимум 8 символов.';
                }
                return null;
              },
            ),
          ],
          if (_mode == AuthMode.signIn)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _switchMode(AuthMode.forgotPassword),
                child: const Text('Забыли пароль?'),
              ),
            ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_message!),
            ),
          ],
          SizedBox(height: _mode == AuthMode.signIn ? 12 : 24),
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
          const SizedBox(height: 12),
          if (_mode == AuthMode.signIn)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Нет аккаунта?', style: theme.textTheme.bodyMedium),
                TextButton(
                  onPressed: _busy ? null : () => _switchMode(AuthMode.signUp),
                  child: const Text('Создать аккаунт'),
                ),
              ],
            )
          else if (_mode != AuthMode.updatePassword)
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => _switchMode(AuthMode.signIn),
                child: const Text('Назад ко входу'),
              ),
            ),
        ],
      ),
    );
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 780;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 32 : 24,
                  vertical: wide ? 32 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - (wide ? 64 : 48)).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 900 : 420),
                      child: wide
                          ? Card(
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(40),
                                        decoration: const BoxDecoration(
                                          color: AppColors.yellow,
                                        ),
                                        child: const Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: AppColors.ink,
                                              size: 32,
                                            ),
                                            SizedBox(height: 28),
                                            Text(
                                              'CashRadar',
                                              style: TextStyle(
                                                color: AppColors.ink,
                                                fontSize: 32,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'Ваши финансы в одном месте',
                                              style: TextStyle(
                                                color: AppColors.ink,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(40),
                                        child: form,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                brand,
                                const SizedBox(height: 48),
                                form,
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
