import 'package:cash_radar/features/categorization/ai_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows public names while blocking common identifiers', () {
    for (final name in ['Starbucks', 'Սուպերմարկետ', 'Shop & Cafe 24']) {
      expect(isEligibleAiName(name), isTrue, reason: name);
    }
    for (final name in [
      'name@example.com',
      'VISA 1234',
      '123456789',
      'https://example.com',
      'example.com',
      'A\nB',
    ]) {
      expect(isEligibleAiName(name), isFalse, reason: name);
    }
  });
  test('preselects at most ten eligible groups and skips identifiers', () {
    final rows = [
      {'group_id': 'private', 'merchant': 'card 1234'},
      for (var i = 0; i < 12; i++)
        {'group_id': 'group-$i', 'merchant': 'Public Shop'},
    ];
    final selected = initiallySelectedAiGroups(rows);
    expect(selected.length, 10);
    expect(selected, contains('group-0'));
    expect(selected, isNot(contains('group-10')));
    expect(selected, isNot(contains('private')));
  });
}
