/// A validated decimal string, never a floating-point value.
class Money {
  const Money._(this.value);
  final String value;

  static Money? tryParse(String input) {
    final normalized = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^-?\d+(?:\.\d{1,4})?$').hasMatch(normalized)) return null;
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

  String get display {
    final parts = value.split('.');
    final fraction = parts.length == 1 ? '' : parts[1];
    return '${parts[0]}.${fraction.padRight(2, '0')}';
  }
}

const supportedCurrencies = ['AMD', 'RUB', 'USD', 'EUR'];
