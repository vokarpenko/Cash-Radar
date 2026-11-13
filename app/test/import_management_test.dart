import 'dart:async';
import 'dart:typed_data';

import 'package:cash_radar/app/app_shell.dart';
import 'package:cash_radar/features/accounts/accounts_repository.dart';
import 'package:cash_radar/features/imports/import_repository.dart';
import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'support/fake_auth.dart';

class ImportAccounts implements AccountsRepository {
  ImportAccounts({this.active = true});
  final bool active;
  @override
  Future<List<AccountSummary>> loadAccounts() async => [
    AccountSummary(
      id: 'a1',
      name: 'Мой счёт',
      type: 'bank',
      currency: 'AMD',
      bankId: 'bank',
      bankName: 'Ameria Bank',
      isActive: active,
    ),
  ];
  @override
  Future<List<Bank>> loadBanks() async => [];
  @override
  Future<void> createAccount(AccountInput input) async {}
  @override
  Future<void> updateAccount(String id, AccountInput input) async {}
  @override
  Future<void> setActive(String id, bool active) async {}
}

class TestPicker implements StatementFilePicker {
  Completer<SelectedStatement?>? pending;
  SelectedStatement? selection;
  @override
  Future<SelectedStatement?> pick() async => pending == null
      ? (selection ??
            SelectedStatement('test.csv', Uint8List.fromList([1, 2, 3])))
      : await pending!.future;
}

class MemoryImports implements ImportsRepository {
  String status = 'ready', format = 'cashradar_csv_v1';
  bool prepared = false, duplicate = false, hasCandidate = false;
  String? reviewDecision;
  int confirms = 0, cancellations = 0;
  String? submittedOwner, submittedAccount, submittedPassword;
  ImportBatch get batch => ImportBatch(
    id: 'batch',
    accountId: 'a1',
    accountCurrency: 'AMD',
    filename: 'test.csv',
    status: status,
    rowCount: 1,
    errorCount: status == 'invalid' ? 1 : 0,
    importedCount: status == 'completed' ? 1 : 0,
    errors: status == 'invalid'
        ? [const ImportIssue(row: 2, message: 'Ошибка суммы.')]
        : [],
    createdAt: '2026-11-12T00:00:00Z',
    format: format,
  );
  @override
  Future<List<ImportBatch>> loadBatches() async => prepared ? [batch] : [];
  @override
  Future<ImportDetail> loadDetail(String id) async => ImportDetail(
    batch,
    status == 'cancelled'
        ? []
        : [
            ImportRow(
              id: 'item',
              candidates: hasCandidate
                  ? [
                      const ImportCandidate(
                        itemId: 'item',
                        type: 'transaction',
                        date: '2026-11-10',
                        source: 'manual',
                        description: 'Покупка',
                      ),
                    ]
                  : const [],
              candidateSignature: hasCandidate ? 'signature' : null,
              duplicateDecision: reviewDecision,
              duplicateSignature: reviewDecision == null ? null : 'signature',
              rowNumber: 2,
              date: '2026-11-11',
              type: 'expense',
              amount: '12.34',
              currency: 'EUR',
              accountAmount: '5000.00',
              category: 'Продукты',
              description: 'Покупка',
            ),
          ],
  );
  @override
  Future<PrepareResult> prepare(
    String accountId,
    SelectedStatement file,
    String expectedUserId, {
    String? password,
  }) async {
    submittedAccount = accountId;
    submittedOwner = expectedUserId;
    submittedPassword = password;
    prepared = true;
    return PrepareResult('batch', duplicate);
  }

  @override
  Future<void> resolveDuplicate(String itemId, String decision) async {
    reviewDecision = decision == 'clear' ? null : decision;
  }

  @override
  Future<void> confirm(String id) async {
    confirms++;
    status = 'completed';
  }

  @override
  Future<void> cancel(String id) async {
    cancellations++;
    status = 'cancelled';
  }
}

void main() {
  late FakeAuth auth;
  late TestPicker picker;
  late MemoryImports imports;
  setUp(() {
    auth = FakeAuth()..active = true;
    picker = TestPicker();
    imports = MemoryImports();
  });
  tearDown(() => auth.controller.close());
  Future<void> open(
    WidgetTester tester, {
    bool mobile = false,
    bool activeAccount = true,
  }) async {
    tester.view.physicalSize = mobile
        ? const Size(390, 800)
        : const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWithValue(
            ImportAccounts(active: activeAccount),
          ),
          statementFilePickerProvider.overrideWithValue(picker),
          importsRepositoryProvider.overrideWithValue(imports),
        ],
        child: CashRadarApp(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(AppShell))).go('/imports');
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester, {String? password}) async {
    await Scrollable.ensureVisible(
      tester.element(find.byType(DropdownButtonFormField<String>).first),
      alignment: 0.25,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мой счёт · AMD · Ameria Bank').last);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Выбрать файл')),
      alignment: 0.25,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать файл'));
    await tester.pumpAndSettle();
    if (password != null) {
      final field = find.byType(TextField).first;
      await tester.ensureVisible(field);
      await tester.enterText(field, password);
      await tester.pumpAndSettle();
    }
    await Scrollable.ensureVisible(
      tester.element(find.text('Подготовить импорт')),
      alignment: 0.25,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подготовить импорт'));
    await tester.pumpAndSettle();
  }

  testWidgets('prepares a private preview and confirms once', (tester) async {
    await open(tester);
    await prepare(tester);
    expect(imports.submittedAccount, 'a1');
    expect(imports.submittedOwner, 'test-user');
    expect(find.text('Предпросмотр: test.csv'), findsOneWidget);
    expect(find.text('Счёт: Мой счёт · Ameria Bank'), findsOneWidget);
    expect(find.text('−12.34 EUR'), findsOneWidget);
    expect(find.text('Строка 2, по счёту: 5000.00 AMD'), findsOneWidget);
    await tester.ensureVisible(find.text('Подтвердить импорт'));
    await tester.tap(find.text('Подтвердить импорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(imports.confirms, 1);
    expect(find.textContaining('Импортирован · формат'), findsOneWidget);
    expect(find.text('Подтвердить импорт'), findsNothing);
  });
  testWidgets(
    'requests a password only for an encrypted file and clears it after preparation',
    (tester) async {
      picker.selection = SelectedStatement(
        'sample.xlsx',
        Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]),
      );
      imports.format = 'acba_xlsx_v1';
      await open(tester);
      await prepare(tester, password: 'synthetic-only');
      expect(imports.submittedPassword, 'synthetic-only');
      expect(find.textContaining('формат: ACBA XLSX'), findsOneWidget);
      expect(find.text('Пароль от файла ACBA'), findsNothing);
    },
  );
  testWidgets('requires explicit review of a possible duplicate', (
    tester,
  ) async {
    imports.hasCandidate = true;
    await open(tester);
    await prepare(tester);
    expect(
      find.text('Возможное совпадение — проверьте строку'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить импорт'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Пропустить строку'));
    await tester.tap(find.text('Пропустить строку'));
    await tester.pumpAndSettle();
    expect(find.text('Решение: пропустить'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить импорт'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('labels Ameria XLSX in the preview', (tester) async {
    imports.format = 'ameria_xlsx_v1';
    await open(tester);
    await prepare(tester);
    expect(find.textContaining('формат: Ameria XLSX'), findsOneWidget);
  });
  testWidgets('shows invalid rows and prevents partial confirmation', (
    tester,
  ) async {
    imports.status = 'invalid';
    await open(tester);
    await prepare(tester);
    expect(find.text('Строка 2: Ошибка суммы.'), findsOneWidget);
    expect(find.text('Подтвердить импорт'), findsNothing);
    await Scrollable.ensureVisible(
      tester.element(find.text('Отменить подготовку')),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить подготовку'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Отменить подготовку'),
      ),
    );
    await tester.pumpAndSettle();
    expect(imports.cancellations, 1);
    expect(find.textContaining('Отменён · формат'), findsOneWidget);
  });
  testWidgets('clears pending selection when the user changes', (tester) async {
    picker.pending = Completer<SelectedStatement?>();
    await open(tester);
    await tester.tap(find.text('Выбрать файл'));
    await tester.pump();
    auth.changeUser('other-user');
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Выбрать файл'),
          )
          .onPressed,
      isNotNull,
    );
    picker.pending!.complete(
      SelectedStatement('private.csv', Uint8List.fromList([1])),
    );
    await tester.pumpAndSettle();
    expect(find.text('private.csv'), findsNothing);
    expect(imports.prepared, isFalse);
  });
  testWidgets('does not confirm an import for an archived account', (
    tester,
  ) async {
    imports.prepared = true;
    await open(tester, activeAccount: false);
    await tester.ensureVisible(find.text('test.csv'));
    await tester.tap(find.text('test.csv'));
    await tester.pumpAndSettle();
    expect(find.textContaining('счёт архивирован'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Подтвердить импорт'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('preview fits on a narrow screen with large sums', (
    tester,
  ) async {
    await open(tester, mobile: true);
    await prepare(tester);
    await tester.ensureVisible(find.text('Подтвердить импорт'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
