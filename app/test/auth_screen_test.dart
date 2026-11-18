import 'package:cash_radar/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth.dart';

void main() {
  late FakeAuth auth;
  setUp(() => auth = FakeAuth());
  tearDown(() => auth.controller.close());

  Future<void> enterCredentials(
    WidgetTester tester, {
    String password = 'password123',
  }) async {
    await tester.enterText(
      find.byType(TextFormField).first,
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, password);
  }

  testWidgets('toggles password visibility', (tester) async {
    await tester.pumpWidget(CashRadarApp(auth: auth));
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Показать пароль'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
    await tester.tap(find.byTooltip('Скрыть пароль'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
  });

  testWidgets('registers and asks for email confirmation', (tester) async {
    await tester.pumpWidget(CashRadarApp(auth: auth));
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    await enterCredentials(tester);
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();
    expect(auth.requestedEmail, 'person@example.com');
    expect(find.textContaining('подтвердите адрес'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('signs in and protects the page again after sign out', (
    tester,
  ) async {
    await tester.pumpWidget(CashRadarApp(auth: auth));
    expect(find.text('Добро пожаловать в CashRadar'), findsNothing);
    await enterCredentials(tester);
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Добро пожаловать в CashRadar'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Выйти')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Добро пожаловать в CashRadar'), findsNothing);
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('requests recovery without disclosing account existence', (
    tester,
  ) async {
    await tester.pumpWidget(CashRadarApp(auth: auth));
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.tap(find.text('Отправить письмо'));
    await tester.pumpAndSettle();
    expect(auth.requestedEmail, 'person@example.com');
    expect(find.textContaining('Если аккаунт существует'), findsOneWidget);
  });

  testWidgets('recovery link requests a new password for an active session', (
    tester,
  ) async {
    auth.active = true;
    await tester.pumpWidget(CashRadarApp(auth: auth, initialRecovery: true));
    await tester.enterText(find.byType(TextFormField), 'newpassword123');
    await tester.tap(find.text('Сохранить пароль'));
    await tester.pumpAndSettle();
    expect(auth.passwordValue, 'newpassword123');
    expect(find.text('Добро пожаловать в CashRadar'), findsOneWidget);
  });

  testWidgets('rejects a short registration password', (tester) async {
    await tester.pumpWidget(CashRadarApp(auth: auth));
    await tester.tap(find.text('Создать аккаунт'));
    await tester.pumpAndSettle();
    await enterCredentials(tester, password: '123');
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();
    expect(find.text('Минимум 8 символов.'), findsOneWidget);
    expect(auth.requestedEmail, isNull);
  });
}
