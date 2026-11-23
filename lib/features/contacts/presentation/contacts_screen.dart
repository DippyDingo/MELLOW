import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/contact_list.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/features/contacts/application/contacts_controller.dart';

/// "Люди" tab — all contacts, searchable.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        title: const Text('Люди'),
        titleSpacing: MellowSpacing.lg,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MellowSpacing.lg,
              MellowSpacing.sm,
              MellowSpacing.lg,
              MellowSpacing.sm,
            ),
            child: Consumer(
              builder: (context, ref, _) => TextField(
                onChanged: (value) =>
                    ref.read(contactsSearchQueryProvider.notifier).state = value,
                decoration: const InputDecoration(
                  hintText: 'Имя или адрес',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ),
          Expanded(
            child: contacts.when(
              data: (items) => items.isEmpty
                  ? const MellowEmptyState(
                      title: 'Контакты появятся здесь',
                      message:
                          'Mellow создаёт контакт автоматически, когда вы '
                          'получаете или отправляете письмо.',
                      icon: Icons.people_outline,
                    )
                  : ContactList(contacts: items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => MellowEmptyState(
                title: 'Не удалось загрузить контакты',
                message: error.toString(),
                icon: Icons.error_outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
