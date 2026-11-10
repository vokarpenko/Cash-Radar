import 'package:cash_radar/health/health_screen.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows configuration errors and disables the check', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CashRadarApp(configurationError: 'Нет настроек'),
    );
    expect(find.text('Нет настроек'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('shows a successful database check', (tester) async {
    await tester.pumpWidget(CashRadarApp(check: () async => true));
    await tester.tap(find.text('Проверить подключение'));
    await tester.pumpAndSettle();
    expect(find.text('Подключение к базе данных работает.'), findsOneWidget);
  });

  testWidgets('shows a failed check without exposing the error', (
    tester,
  ) async {
    Future<bool> fail() => Future.error(Exception('private details'));
    await tester.pumpWidget(MaterialApp(home: HealthScreen(check: fail)));
    await tester.tap(find.text('Проверить подключение'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Не удалось проверить подключение.'),
      findsOneWidget,
    );
    expect(find.textContaining('private details'), findsNothing);
  });
}
