import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/contact_list.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/features/contacts/application/contacts_controller.dart';

/// "Избранное" tab — favourite people, the people who matter most.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteContactsProvider);

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        title: const Text('Избранное'),
        titleSpacing: MellowSpacing.lg,
      ),
      body: favorites.when(
        data: (contacts) => contacts.isEmpty
            ? const MellowEmptyState(
                title: 'Пока никого нет в избранном',
                message: 'Откройте человека и нажмите «В избранное», '
                    'чтобы быстро возвращаться к важным перепискам.',
                icon: Icons.star_border_rounded,
              )
            : ContactList(contacts: contacts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => MellowEmptyState(
          title: 'Не удалось загрузить избранное',
          message: error.toString(),
          icon: Icons.error_outline,
        ),
      ),
    );
  }
}
