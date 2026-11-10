import 'package:flutter/material.dart';

typedef HealthCheck = Future<bool> Function();

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, this.check, this.configurationError});

  final HealthCheck? check;
  final String? configurationError;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool _loading = false;
  String? _message;

  Future<void> _checkConnection() async {
    if (widget.check == null || _loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final available = await widget.check!().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(
        () => _message = available
            ? 'Подключение к базе данных работает.'
            : 'База данных вернула неожиданный ответ.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message =
            'Не удалось проверить подключение. Проверьте сеть, конфигурацию и миграцию.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CashRadar')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Проверка подключения к Supabase'),
              const SizedBox(height: 16),
              if (widget.configurationError case final error?) Text(error),
              if (_message case final message?) Text(message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.check == null || _loading
                    ? null
                    : _checkConnection,
                child: Text(_loading ? 'Проверка…' : 'Проверить подключение'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
