import 'package:cash_radar/features/accounts/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves exact decimal amounts and rejects excess precision', () {
    expect(
      Money.tryParse('999999999999999999.99')!.value,
      '999999999999999999.99',
    );
    expect(Money.tryParse('-000123,45')!.value, '-123.45');
    expect(Money.tryParse('-0,00')!.value, '0.00');
    expect(Money.tryParse('0.1')!.display, '0.10');
    expect(Money.tryParse('1234567890123456789'), isNull);
    expect(Money.tryParse('0.001'), isNull);
    expect(Money.tryParse('1.2300'), isNull);
    expect(Money.tryParse('1e3'), isNull);
    expect(Money.tryParse('NaN'), isNull);
    expect(Money.tryParse(''), isNull);
  });
  test(
    'displays stored values without rounding or losing significant digits',
    () {
      expect(Money.displayStored('1000.0000'), '1000.00');
      expect(Money.displayStored('1.2300'), '1.23');
      expect(Money.displayStored('1.2301'), '1.2301');
      expect(
        Money.displayStored('1000000000000000000.00'),
        '1000000000000000000.00',
      );
    },
  );
}
