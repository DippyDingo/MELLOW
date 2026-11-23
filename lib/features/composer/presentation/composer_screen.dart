import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';

/// Smart Composer (spec 2.5).
///
/// Sprint 01 delivers the screen, validation and draft-safe state handling.
/// Actual sending arrives with the mail adapters in sprint 03/05; until then the
/// send action is explicitly disabled instead of pretending to work.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key, this.initialRecipient, this.threadId});

  final String? initialRecipient;
  final String? threadId;

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  late final TextEditingController _toController =
      TextEditingController(text: widget.initialRecipient ?? '');
  final TextEditingController _ccController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  bool _showCc = false;
  String? _recipientError;

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// Validates every recipient field; returns false and sets [_recipientError].
  bool _validateRecipients() {
    final raw = <String>[
      _toController.text,
      if (_showCc) _ccController.text,
    ].where((value) => value.trim().isNotEmpty).join(',');

    final addresses = parseAddressList(raw);
    if (addresses.isEmpty) {
      setState(() => _recipientError = 'Добавьте хотя бы одного получателя');
      return false;
    }
    setState(() => _recipientError = null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(primaryAccountProvider);
    final tokens = MellowColors.of(context);
    final hasContent = _toController.text.trim().isNotEmpty ||
        _subjectController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty;

    return MellowScaffold(
      padding: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Закрыть',
          onPressed: () => _confirmDiscard(context, hasContent),
        ),
        title: widget.threadId == null ? const Text('Новое сообщение') : const Text('Ответ'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Вложения',
            icon: const Icon(Icons.attach_file),
            onPressed: () => _notImplemented(context, 'Вложения появятся в спринте 05'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: MellowSpacing.md),
            child: IconButton.filled(
              tooltip: account == null
                  ? 'Сначала подключите аккаунт'
                  : 'Отправить',
              onPressed: account == null
                  ? null
                  : () {
                      if (!_validateRecipients()) return;
                      _notImplemented(
                        context,
                        'Отправка станет доступна после подключения почтового адаптера',
                      );
                    },
              icon: const Icon(Icons.send_outlined),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MellowSpacing.lg,
          MellowSpacing.sm,
          MellowSpacing.lg,
          MellowSpacing.xxl,
        ),
        children: <Widget>[
          _AccountChip(accountLabel: account?.email),
          const SizedBox(height: MellowSpacing.md),
          TextField(
            controller: _toController,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Кому',
              hintText: 'name@example.com',
              errorText: _recipientError,
              suffixIcon: _showCc
                  ? null
                  : TextButton(
                      onPressed: () => setState(() => _showCc = true),
                      child: const Text('Копия'),
                    ),
            ),
          ),
          if (_showCc) ...<Widget>[
            const SizedBox(height: MellowSpacing.md),
            TextField(
              controller: _ccController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Копия'),
            ),
          ],
          const SizedBox(height: MellowSpacing.md),
          TextField(
            controller: _subjectController,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Тема',
              hintText: widget.threadId == null
                  ? 'Сформируется автоматически'
                  : 'Re: …',
            ),
          ),
          const SizedBox(height: MellowSpacing.lg),
          TextField(
            controller: _bodyController,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Напишите сообщение…',
              border: InputBorder.none,
              filled: false,
            ),
          ),
          const SizedBox(height: MellowSpacing.lg),
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline, size: 14, color: tokens.onSurfaceMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Текст пока живёт только на этом экране: локальные черновики '
                  'появятся вместе с отправкой (спринт 05). Тема и заголовки '
                  'Message-ID / In-Reply-To / References проставляются '
                  'автоматически при отправке.',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, bool hasContent) async {
    if (!hasContent) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть без сохранения?'),
        content: const Text('Текст сообщения будет потерян.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Продолжить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (discard == true && context.mounted) Navigator.of(context).pop();
  }

  void _notImplemented(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.accountLabel});

  final String? accountLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Row(
      children: <Widget>[
        Icon(Icons.alternate_email, size: 16, color: tokens.onSurfaceMuted),
        const SizedBox(width: 6),
        Text(
          accountLabel ?? 'Аккаунт не подключён',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tokens.onSurfaceMuted),
        ),
      ],
    );
  }
}
