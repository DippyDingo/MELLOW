import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mellow/app/bootstrap/bootstrap.dart';
import 'package:mellow/app/mellow_app.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/seed/demo_seed.dart';
import 'package:mellow/domain/repositories/settings_repository.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';

/// Boots the real widget tree against an in-memory database.
Future<ProviderContainer> pumpApp(WidgetTester tester) async {
  final db = AppDatabase.inMemory();
  await DemoSeed.run(db);
  final container = createContainer(database: db);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MellowApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('app starts on the conversations tab with seeded threads',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('Диалоги'), findsWidgets);
    // Thread titles are contact names.
    expect(find.text('Александр Петров'), findsWidgets);
    expect(find.text('Мария Соколова'), findsOneWidget);
  });

  testWidgets('bottom navigation switches sections', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();
    expect(find.text('Люди'), findsWidgets);

    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('Избранное'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Настройки'), findsWidgets);
    expect(find.text('Почтовые аккаунты'), findsOneWidget);
  });

  testWidgets('opening a thread shows its messages', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Мария Соколова'));
    await tester.pumpAndSettle();

    // The app bar shows the subject; the participants are the subtitle.
    expect(find.text('Планы на выходные'), findsOneWidget);
    expect(find.textContaining('термос'), findsOneWidget);
  });

  testWidgets('theme preference is persisted and applied', (tester) async {
    final container = await pumpApp(tester);

    await container
        .read(settingsControllerProvider.notifier)
        .setThemePreference(ThemePreference.dark);
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    final stored = await container.read(settingsControllerProvider.future);
    expect(stored.themePreference, ThemePreference.dark);
  });

  testWidgets('search narrows the conversation list', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField).first, 'отпуск');
    await tester.pumpAndSettle();

    // Subject/preview search: only the trip thread survives.
    expect(find.text('Александр Петров'), findsNothing);
    expect(find.text('Мария Соколова'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'мария');
    await tester.pumpAndSettle();

    // Search is subject/preview based in sprint 01, so contact names are not
    // matched; the empty result is honest rather than silently wrong.
    expect(find.text('Александр Петров'), findsNothing);
  });

  testWidgets('dark theme renders without overflow on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = await pumpApp(tester);
    await container
        .read(settingsControllerProvider.notifier)
        .setThemePreference(ThemePreference.dark);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
