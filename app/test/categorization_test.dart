import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/categorization/rules_repository.dart';
import 'package:cash_radar/features/settings/currency_repository.dart';
import 'package:cash_radar/features/transactions/transactions_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/fake_auth.dart';

class FakeRules implements RulesRepository {
  final List<CategoryRule> rules = [];
  @override
  Future<RuleData> load() async => RuleData(List.of(rules), [], []);
  @override
  Future<void> addRule({
    required String kind,
    required String matchType,
    required String pattern,
    required String categoryId,
    required int priority,
  }) async {
    rules.add(
      CategoryRule(
        id: 'r1',
        kind: kind,
        matchType: matchType,
        pattern: pattern,
        categoryId: categoryId,
        priority: priority,
        enabled: true,
      ),
    );
  }

  @override
  Future<void> setRuleEnabled(String id, bool enabled) async {}
  @override
  Future<void> deleteRule(String id) async {
    rules.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> addAlias({
    required String kind,
    required String alias,
    required String canonicalName,
    String? categoryId,
  }) async {}
  @override
  Future<void> deleteAlias(String id) async {}
  @override
  Future<void> deleteMemory(String id) async {}
}

void main() {
  testWidgets('creates and removes a prioritized merchant rule', (
    tester,
  ) async {
    final auth = FakeAuth()..active = true, repo = FakeRules();
    addTearDown(auth.controller.close);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rulesRepositoryProvider.overrideWithValue(repo),
          baseCurrencyProvider.overrideWith((ref) async => 'AMD'),
          transactionCategoriesProvider.overrideWith(
            (ref) async => [
              const TransactionCategory(
                id: 'food',
                name: 'Рестораны',
                kind: 'expense',
              ),
            ],
          ),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Правила категорий'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить правило'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Название или часть названия'),
      'Synthetic Cafe',
    );
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Категория'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Рестораны').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.rules.single.pattern, 'Synthetic Cafe');
    expect(repo.rules.single.priority, 100);
    expect(find.text('Synthetic Cafe → Рестораны'), findsOneWidget);
    await tester.tap(find.byTooltip('Удалить правило'));
    await tester.pumpAndSettle();
    expect(repo.rules, isEmpty);
    expect(find.text('Правил пока нет.'), findsOneWidget);
  });
}
