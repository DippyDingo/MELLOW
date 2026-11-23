import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/features/conversations/application/thread_list_controller.dart';

/// Bottom navigation shell with four sections (spec 5.1).
class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const List<_Tab> _tabs = <_Tab>[
    _Tab(AppRoutes.conversations, 'Диалоги', Icons.forum_outlined, Icons.forum),
    _Tab(AppRoutes.contacts, 'Люди', Icons.people_outline, Icons.people),
    _Tab(AppRoutes.favorites, 'Избранное', Icons.star_border_rounded, Icons.star_rounded),
    _Tab(AppRoutes.settings, 'Настройки', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    var index = _tabs.indexWhere((tab) => location.startsWith(tab.path));
    if (index < 0) index = 0;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final tokens = MellowColors.of(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(top: BorderSide(color: tokens.divider)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 64,
            selectedIndex: index,
            onDestinationSelected: (selected) {
              if (selected == index) return;
              context.go(_tabs[selected].path);
            },
            destinations: <Widget>[
              for (var i = 0; i < _tabs.length; i++)
                NavigationDestination(
                  icon: Badge.count(
                    count: i == 0 ? unread : 0,
                    isLabelVisible: i == 0 && unread > 0,
                    backgroundColor: tokens.unreadBadge,
                    textColor: tokens.onUnreadBadge,
                    child: Icon(_tabs[i].icon),
                  ),
                  selectedIcon: Badge.count(
                    count: i == 0 ? unread : 0,
                    isLabelVisible: i == 0 && unread > 0,
                    backgroundColor: tokens.unreadBadge,
                    textColor: tokens.onUnreadBadge,
                    child: Icon(_tabs[i].selectedIcon),
                  ),
                  label: _tabs[i].label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
