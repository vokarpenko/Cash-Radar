import 'analytics_repository.dart';

/// Groups exact fixed-point values without converting them to floating point.
String analyticsAmount(BigInt amount) {
  final value = ExchangeRates.display(amount);
  final parts = value.split('.');
  final negative = parts.first.startsWith('−');
  final digits = negative ? parts.first.substring(1) : parts.first;
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('\u202f');
    grouped.write(digits[i]);
  }
  return '${negative ? '−' : ''}$grouped.${parts.last}';
}
