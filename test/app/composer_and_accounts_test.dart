import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/bootstrap/bootstrap.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/mellow_app.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/seed/demo_seed.dart';
import 'package:mellow/domain/entities/account.dart';

/// Walks the app the way a user would, starting from the shell.
Future<ProviderContainer> pumpApp(WidgetTester tester) async {
  final db = AppDatabase.inMemory();
  await DemoSeed.run(db);
  final container = createContainer(database: db);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MellowApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('composer validates recipients before pretending to send',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Новое сообщение'), findsOneWidget);

    // Empty recipient -> validation message, no fake "sent" state.
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Добавьте хотя бы одного получателя'), findsOneWidget);

    // Invalid address keeps the error.
    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.tap(find.byIcon(Icons.send_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Добавьте хотя бы одного получателя'), findsOneWidget);

    // A valid address clears the error. The send itself needs a real mailbox,
    // so it is covered by `send_controller_test.dart` against a fake adapter.
    await tester.enterText(find.byType(TextField).first, 'alex@example.com');
    await tester.pumpAndSettle();
    expect(find.text('Добавьте хотя бы одного получателя'), findsNothing);
  });

  testWidgets('replying opens the composer with the recipient and subject',
      (tester) async {
    await pumpApp(tester);

    // Open the seeded conversation with Мария and use the reply bar.
    await tester.tap(find.text('Мария Соколова'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ответить…'));
    await tester.pumpAndSettle();

    // The reply screen is prefilled, not an empty "new message" form.
    expect(find.text('Ответ'), findsOneWidget);
    expect(find.text('Новое сообщение'), findsNothing);
    expect(find.text('maria.sokolova@mail.ru'), findsOneWidget);
    expect(find.text('Re: Планы на выходные'), findsWidgets);
  });

  testWidgets('closing a filled composer asks for confirmation', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'Черновик темы');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Закрыть без сохранения?'), findsOneWidget);

    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Новое сообщение'), findsOneWidget);
  });

  testWidgets('add account screen detects the provider from the address',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Почтовые аккаунты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Добавить аккаунт'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'person@yandex.ru');
    await tester.pumpAndSettle();
    expect(find.text('Яндекс Почта'), findsOneWidget);
    expect(find.textContaining('imap.yandex.ru'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'broken@address');
    await tester.pumpAndSettle();
    expect(find.text('Проверьте адрес: похоже, в нём опечатка'), findsOneWidget);
  });

  testWidgets('accounts list shows the connected demo mailbox', (tester) async {
    final container = await pumpApp(tester);
    final accounts = await container.read(accountRepositoryProvider).getAccounts();
    expect(accounts.single.provider, MailProviderKind.gmail);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Почтовые аккаунты'));
    await tester.pumpAndSettle();

    expect(find.text('mellow.demo@gmail.com'), findsOneWidget);
    expect(find.text('Основной'), findsOneWidget);
    expect(find.text('Подключён'), findsOneWidget);
  });

  testWidgets('contact profile lists addresses and conversations',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Александр Петров'));
    await tester.pumpAndSettle();

    expect(find.text('alex@example.com'), findsWidgets);
    expect(find.text('alexander@company.com'), findsWidgets);
    expect(find.text('Разработка приложения'), findsOneWidget);
    expect(find.text('Документы по проекту'), findsOneWidget);
  });
}
