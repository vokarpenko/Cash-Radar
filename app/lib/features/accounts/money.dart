/// A validated decimal string, never a floating-point value.
class Money {
  const Money._(this.value);
  final String value;

  static Money? tryParse(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^-?\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
    final negative = normalized.startsWith('-');
    final parts = (negative ? normalized.substring(1) : normalized).split('.');
    final integer = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (integer.length > 18) return null;
    final fraction = parts.length == 2 ? parts[1] : '';
    final zero =
        integer == '0' && (fraction.isEmpty || int.parse(fraction) == 0);
    final sign = negative && !zero ? '-' : '';
    return Money._('$sign$integer${fraction.isEmpty ? '' : '.$fraction'}');
  }

  /// Displays stored decimals without rounding or relying on floating point.
  /// PostgreSQL can retain insignificant trailing zeros from older values.
  static String displayStored(String value) {
    if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value)) return value;
    final parts = value.split('.');
    var fraction = parts.length == 1 ? '' : parts[1];
    while (fraction.length > 2 && fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    return '${parts[0]}.${fraction.padRight(2, '0')}';
  }

  /// Formats a stored amount for read-only display without losing precision.
  static String formatStored(String value) => groupDigits(displayStored(value));

  /// Groups the integer part of a decimal string with non-breaking spaces.
  static String groupDigits(String value) {
    if (!RegExp(r'^[-−]?\d+(?:\.\d+)?$').hasMatch(value)) return value;
    final parts = value.split('.');
    final hasSign = parts.first.startsWith('-') || parts.first.startsWith('−');
    final sign = hasSign ? parts.first.substring(0, 1) : '';
    final digits = hasSign ? parts.first.substring(1) : parts.first;
    final result = StringBuffer(sign);
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) result.write('\u00a0');
      result.write(digits[i]);
    }
    if (parts.length == 2) result.write('.${parts[1]}');
    return result.toString();
  }

  String get display => displayStored(value);
}

const supportedCurrencies = ['AMD', 'RUB', 'USD', 'EUR'];
