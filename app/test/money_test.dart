import 'package:cash_radar/features/accounts/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves exact financial amounts without floating point', () {
    expect(
      Money.tryParse('999999999999999999.9999')!.value,
      '999999999999999999.9999',
    );
    expect(Money.tryParse('-000123,4500')!.value, '-123.4500');
    expect(Money.tryParse('-0,00')!.value, '0.00');
    expect(Money.tryParse('0.1')!.display, '0.10');
    expect(Money.tryParse('1234567890123456789'), isNull);
    expect(Money.tryParse('0.00001'), isNull);
    expect(Money.tryParse('1e3'), isNull);
    expect(Money.tryParse('NaN'), isNull);
    expect(Money.tryParse(''), isNull);
  });
}
