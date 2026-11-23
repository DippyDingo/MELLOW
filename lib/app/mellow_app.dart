import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/app/navigation/router.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/theme/theme_mode_resolver.dart';
import 'package:mellow/features/settings/application/settings_controller.dart';
import 'package:mellow/features/sync/application/sync_controller.dart';

/// Root widget: themes, localisation and the router.
///
/// Theme mode comes from persisted settings, so the choice survives restarts
/// and follows the system when the user picks "как в системе".
class MellowApp extends ConsumerStatefulWidget {
  const MellowApp({super.key});

  @override
  ConsumerState<MellowApp> createState() => _MellowAppState();
}

class _MellowAppState extends ConsumerState<MellowApp> {
  late final _router = createRouter();

  @override
  void initState() {
    super.initState();
    // One best-effort sync at startup when the user asked for it. The provider
    // swallows failures: the first frame must never wait for the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncOnLaunchProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      title: 'Mellow',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _MellowScrollBehavior(),
      theme: MellowTheme.light(),
      darkTheme: MellowTheme.dark(),
      themeMode: resolveThemeMode(settings),
      routerConfig: _router,
      locale: const Locale('ru'),
      supportedLocales: const <Locale>[
        Locale('ru'),
        Locale('en'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Clamp accessibility scaling so layouts stay usable at extreme sizes.
        final mediaQuery = MediaQuery.of(context);
        final textScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.6,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: textScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Scrollbars on desktop/web builds stay subtle and match the calm palette.
class _MellowScrollBehavior extends MaterialScrollBehavior {
  const _MellowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // No glow: it fights the calm surfaces.
    return child;
  }
}
