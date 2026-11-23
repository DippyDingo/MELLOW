import 'package:flutter/material.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_avatar.dart';
import 'package:mellow/domain/entities/contact.dart';

/// One row in the contacts / favourites list.
class ContactTile extends StatelessWidget {
  const ContactTile({
    required this.contact,
    super.key,
    this.onTap,
    this.trailing,
  });

  final Contact contact;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final secondary = contact.addresses.length > 1
        ? contact.addresses.skip(1).map((a) => a.email).join(', ')
        : null;

    return ListTile(
      onTap: onTap,
      leading: MellowAvatar(
        label: contact.displayName,
        seed: contact.primaryAddress,
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              contact.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(color: tokens.onSurface),
            ),
          ),
          if (contact.isFavorite)
            Icon(Icons.star_rounded, size: 16, color: tokens.warning),
        ],
      ),
      subtitle: Text(
        secondary == null
            ? contact.primaryAddress
            : '${contact.primaryAddress} · $secondary',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
      ),
      trailing: trailing,
    );
  }
}
