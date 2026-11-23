import 'package:flutter/material.dart';
import 'package:mellow/app/navigation/app_shell.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/features/composer/presentation/composer_screen.dart';
import 'package:mellow/features/contacts/presentation/contact_screen.dart';
import 'package:mellow/features/conversations/presentation/conversations_screen.dart';
import 'package:mellow/features/conversations/presentation/thread_screen.dart';
import 'package:mellow/features/favorites/presentation/favorites_screen.dart';
import 'package:mellow/features/onboarding/presentation/add_account_screen.dart';
import 'package:mellow/features/onboarding/presentation/gmail_connect_screen.dart';
import 'package:mellow/features/settings/presentation/about_screen.dart';
import 'package:mellow/features/settings/presentation/accounts_screen.dart';
import 'package:mellow/features/settings/presentation/appearance_screen.dart';
import 'package:mellow/features/settings/presentation/privacy_screen.dart';
import 'package:mellow/features/settings/presentation/settings_screen.dart';
import 'package:mellow/features/sync/presentation/sync_screen.dart';

/// Router of the app.
///
/// Four top-level tabs live inside [AppShell] so the bottom bar keeps its state;
/// everything else is pushed on top of the shell.
GoRouter createRouter({String initialLocation = AppRoutes.conversations}) {
  return GoRouter(
    initialLocation: initialLocation,
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.conversations,
            pageBuilder: (context, state) =>
                NoTransitionPage<void>(child: const ConversationsScreen()),
          ),
          GoRoute(
            path: AppRoutes.contacts,
            pageBuilder: (context, state) =>
                NoTransitionPage<void>(child: const ContactsScreen()),
          ),
          GoRoute(
            path: AppRoutes.favorites,
            pageBuilder: (context, state) =>
                NoTransitionPage<void>(child: const FavoritesScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) =>
                NoTransitionPage<void>(child: const SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.threadPattern,
        builder: (context, state) =>
            ThreadScreen(threadId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.contactPattern,
        builder: (context, state) =>
            ContactScreen(contactId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.compose,
        builder: (context, state) => ComposerScreen(
          initialRecipient: state.uri.queryParameters['to'],
          threadId: state.uri.queryParameters['threadId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.accounts,
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: AppRoutes.addAccount,
        builder: (context, state) => const AddAccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.gmailConnect,
        builder: (context, state) => GmailConnectScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.sync,
        builder: (context, state) => const SyncScreen(),
      ),
      GoRoute(
        path: AppRoutes.appearance,
        builder: (context, state) => const AppearanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Страница не найдена: ${state.uri}'),
      ),
    ),
  );
}
