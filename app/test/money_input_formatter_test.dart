import 'package:cash_radar/features/accounts/money_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue value(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  test(
    'accepts numeric input and editing states without converting amounts',
    () {
      final formatter = MoneyInputFormatter();
      for (final text in [
        '',
        '0',
        '123',
        '12.',
        '12,',
        '12.3',
        '12,34',
        '999999999999999999.99',
      ]) {
        expect(formatter.formatEditUpdate(value(''), value(text)).text, text);
      }
      final previous = value('12.34');
      for (final text in [
        '12.345',
        '12.3.4',
        '12,3.4',
        '12a',
        'abc',
        '1 000',
        '-1',
        '1000000000000000000',
      ]) {
        expect(formatter.formatEditUpdate(previous, value(text)), previous);
      }
    },
  );
  test('negative sign is allowed only for the initial balance', () {
    final formatter = MoneyInputFormatter(allowNegative: true);
    for (final text in ['-', '-12', '-12,34', '']) {
      expect(formatter.formatEditUpdate(value(''), value(text)).text, text);
    }
    for (final text in ['--1', '1-', '-1.234']) {
      expect(formatter.formatEditUpdate(value('-1'), value(text)).text, '-1');
    }
  });
}
