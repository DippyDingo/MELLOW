import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/mellow_app.dart';
import 'package:mellow/data/database/app_database.dart';
import 'package:mellow/data/seed/demo_seed.dart';

/// Boots the app: opens the database, builds the provider container, shows the
/// first frame.
///
/// This is the only place that knows how the database is created. Everything
/// else receives it through [appDatabaseProvider], which makes tests trivial:
/// they override the provider with an in-memory database.
Future<void> bootstrap() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();

  final database = await AppDatabase.open();
  final container = createContainer(database: database);

  if (const bool.fromEnvironment('MELLOW_DEMO_SEED') || kDebugMode) {
    await DemoSeed.runIfEmpty(database);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MellowApp(),
    ),
  );

  binding.allowFirstFrame();
}

/// Builds a container with the given database.
///
/// Used by [bootstrap] and by tests, so production and test wiring cannot drift
/// apart.
ProviderContainer createContainer({required AppDatabase database}) {
  final container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
    ],
  );
  container.onDispose(() => unawaited(database.close()));
  return container;
}
