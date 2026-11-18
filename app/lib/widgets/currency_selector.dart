import 'package:flutter/material.dart';

import '../features/accounts/money.dart';

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String? value;
  final ValueChanged<String>? onChanged;

  static const _names = {
    'AMD': 'Армянский драм',
    'RUB': 'Российский рубль',
    'USD': 'Доллар США',
    'EUR': 'Евро',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = supportedCurrencies.contains(value) ? value : null;
    return PopupMenuButton<String>(
      tooltip: '',
      borderRadius: BorderRadius.circular(12),
      enabled: onChanged != null,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => [
        for (final code in supportedCurrencies)
          PopupMenuItem<String>(
            value: code,
            height: 56,
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    code,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _names[code] ?? code,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (code == selected)
                  Icon(Icons.check_circle, size: 20, color: scheme.primary),
              ],
            ),
          ),
      ],
      child: Semantics(
        label: 'Валюта: ${selected ?? 'не выбрана'}',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Ink(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected ?? 'Валюта',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: scheme.onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
