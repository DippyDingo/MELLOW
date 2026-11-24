import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/providers/discovery/provider_discovery.dart';

/// Step 1 of account connection (spec 2.1): enter the address, Mellow detects
/// the provider and routes to the matching authorisation flow.
///
/// Gmail opens the real OAuth 2.0 + PKCE flow. Other providers are recognised
/// but explicitly not connectable yet — the screen says so instead of
/// pretending to save an account.
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  ProviderGuess? _guess;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detect(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _guess = null;
        _error = null;
      });
      return;
    }
    final parsed = parseEmailAddress(trimmed);
    if (parsed == null) {
      setState(() {
        _guess = null;
        _error = 'Проверьте адрес: похоже, в нём опечатка';
      });
      return;
    }
    setState(() {
      _error = null;
      _guess = ProviderDiscovery.guess(parsed.address);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final guess = _guess;

    return MellowScaffold(
      title: 'Добавить аккаунт',
      body: ListView(
        children: <Widget>[
          Text(
            'Введите адрес почты. Mellow определит провайдера и предложит '
            'безопасный способ входа.',
            style: textTheme.bodyMedium?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: MellowSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onChanged: _detect,
            decoration: InputDecoration(
              hintText: 'name@example.com',
              errorText: _error,
              prefixIcon: const Icon(Icons.alternate_email, size: 20),
            ),
          ),
          if (guess != null) ...<Widget>[
            const SizedBox(height: MellowSpacing.lg),
            _ProviderCard(guess: guess),
          ],
          const SizedBox(height: MellowSpacing.xl),
          FilledButton(
            onPressed: guess == null ? null : () => _continue(context, guess),
            child: const Text('Продолжить'),
          ),
          const SizedBox(height: MellowSpacing.lg),
          const _PrivacyNote(),
        ],
      ),
    );
  }

  /// Routes the user to the flow the detected provider actually supports.
  ///
  /// Gmail has a working implementation; everything else says plainly which
  /// sprint brings it instead of opening a dead-end form.
  void _continue(BuildContext context, ProviderGuess guess) {
    final email = _controller.text.trim();

    if (guess.provider == MailProviderKind.gmail) {
      context.push(
        '${AppRoutes.gmailConnect}?email=${Uri.encodeQueryComponent(email)}',
      );
      return;
    }

    _showComingSoon(context, guess);
  }

  void _showComingSoon(BuildContext context, ProviderGuess guess) {
    final provider = ProviderDiscovery.providerLabel(guess.provider);
    final method = switch (guess.provider) {
      MailProviderKind.outlook => 'OAuth 2.0 через Microsoft Graph',
      MailProviderKind.yandex ||
      MailProviderKind.mailRu ||
      MailProviderKind.imap =>
        'IMAP / SMTP с паролем приложения',
      MailProviderKind.gmail => 'OAuth 2.0 через Gmail API',
      MailProviderKind.demo => 'демонстрационный режим',
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          MellowSpacing.lg,
          0,
          MellowSpacing.lg,
          MellowSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(provider, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: MellowSpacing.sm),
            Text('Способ входа: $method'),
            const SizedBox(height: MellowSpacing.lg),
            const Text(
              'Сейчас Mellow подключает только Gmail. Этот сервис появится '
              'позже — мы не сохраняем настройки, с которыми вход всё равно не '
              'сработает.',
            ),
            const SizedBox(height: MellowSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Понятно'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.guess});

  final ProviderGuess guess;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final isManual = guess.provider.isImapBased && !guess.isCertain;

    return Container(
      padding: const EdgeInsets.all(MellowSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(MellowRadius.lg),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isManual ? Icons.tune : Icons.verified_user_outlined,
                color: tokens.accent,
              ),
              const SizedBox(width: MellowSpacing.sm),
              Text(
                ProviderDiscovery.providerLabel(guess.provider),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: MellowSpacing.sm),
          Text(
            isManual
                ? 'Провайдер не распознан автоматически — серверы IMAP и SMTP '
                    'нужно будет указать вручную.'
                : 'Серверы найдены. Вход выполняется через защищённый протокол '
                    'провайдера.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          if (guess.imapHost != null || guess.smtpHost != null) ...<Widget>[
            const SizedBox(height: MellowSpacing.md),
            if (guess.imapHost != null)
              Text(
                'IMAP: ${guess.imapHost}:${ProviderDiscovery.imapPort}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (guess.smtpHost != null)
              Text(
                'SMTP: ${guess.smtpHost}:${ProviderDiscovery.smtpPort}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.shield_outlined, size: 16, color: tokens.onSurfaceMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Mellow не хранит обычные пароли в открытом виде и запрашивает '
            'только необходимые разрешения.',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
        ),
      ],
    );
  }
}
