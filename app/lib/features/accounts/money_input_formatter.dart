import 'package:flutter/services.dart';

/// Allows intermediate editing states, while preventing non-numeric input.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({this.allowNegative = false});
  final bool allowNegative;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pattern = allowNegative
        ? RegExp(r'^-?(?:\d{1,18}(?:[.,]\d{0,2})?)?$')
        : RegExp(r'^(?:\d{1,18}(?:[.,]\d{0,2})?)?$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
