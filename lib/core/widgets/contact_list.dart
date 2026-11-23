import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/contact_tile.dart';
import 'package:mellow/domain/entities/contact.dart';

/// Alphabetically grouped contact list.
///
/// Shared by "Люди" and "Избранное", which is why it lives in `core/widgets`
/// instead of a feature folder.
class ContactList extends StatelessWidget {
  const ContactList({required this.contacts, super.key});

  final List<Contact> contacts;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Contact>>{};
    for (final contact in contacts) {
      (grouped[contact.initial] ??= <Contact>[]).add(contact);
    }
    final letters = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: letters.length,
      itemBuilder: (context, index) {
        final letter = letters[index];
        final items = grouped[letter]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MellowSpacing.lg,
                MellowSpacing.md,
                MellowSpacing.lg,
                MellowSpacing.xs,
              ),
              child: Text(
                letter,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: MellowColors.of(context).onSurfaceMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final contact in items)
              ContactTile(
                contact: contact,
                onTap: () => context.push(AppRoutes.contact(contact.id)),
              ),
          ],
        );
      },
    );
  }
}
