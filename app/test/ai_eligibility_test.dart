import 'package:cash_radar/features/categorization/ai_eligibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preselects groups regardless of content, up to the request limit', () {
    final rows = [
      {'group_id': 'first', 'merchant': 'VIVA Payment: 12345678 / reference'},
      for (var i = 0; i < 27; i++)
        {'group_id': 'group-$i', 'merchant': 'Public Shop'},
    ];
    final selected = initiallySelectedAiGroups(rows);
    expect(selected.length, 25);
    expect(selected, contains('first'));
    expect(selected, contains('group-23'));
    expect(selected, isNot(contains('group-24')));
  });
}
