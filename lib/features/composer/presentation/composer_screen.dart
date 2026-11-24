import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/di/providers.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/email_address.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/domain/entities/account.dart';
import 'package:mellow/domain/entities/message.dart';
import 'package:mellow/features/accounts/application/accounts_controller.dart';
import 'package:mellow/features/composer/application/draft_store.dart';
import 'package:mellow/features/composer/application/send_controller.dart';

/// Smart Composer (spec 2.5).
///
/// Two entry points, one screen:
/// * "Новое сообщение" — empty recipient, subject and body;
/// * "Ответить" — the recipient, subject (`Re:`), `In-Reply-To` and the
///   `References` chain are filled from the answered message, so the reply
///   lands in the same conversation in every mail client (spec §8).
///
/// Sending is real for Gmail. For providers that are not implemented yet the
/// composer says so instead of pretending.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({
    super.key,
    this.initialRecipient,
    this.threadId,
    this.replyToMessageId,
    this.draftId,
  });

  final String? initialRecipient;

  /// Conversation the message belongs to; `null` for a new one.
  final String? threadId;

  /// Local id of the answered message; turns the screen into a reply.
  final String? replyToMessageId;

  /// Draft being continued; `null` for a fresh composer.
  final String? draftId;

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

  /// The message being answered, once loaded. Kept so the headers can be built
  /// from the *stored* values rather than from whatever the screen guessed.
  Message? _replyTo;
  bool _prefilled = false;

  /// Id of the stored draft once it exists, so every save updates one row.
  String? _draftId;

  /// Debounces typing: a keystroke must not become a database write each time.
  Timer? _autosaveTimer;

  /// Set right before the screen closes after a successful send, so the draft
  /// is not re-saved on the way out.
  bool _finished = false;

  static const Duration _autosaveDelay = Duration(milliseconds: 800);

  bool get _isReply => widget.replyToMessageId != null || widget.threadId != null;

  @override
  void initState() {
    super.initState();
    // Sending state belongs to one editing session: a previous failure must not
    // greet the user with an error banner for a message they no longer see.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sendControllerProvider.notifier).reset();
    });
    if (widget.replyToMessageId != null) {
      // Loaded after the first frame: the provider needs a mounted tree.
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefillReply());
    }
    if (widget.draftId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());
    }
  }

  /// Restores a draft exactly as it was left.
  ///
  /// Runs after the first frame because it reads the database, and never
  /// overwrites text that is already on screen: a draft opened from a
  /// notification while the user is typing must not delete a keystroke.
  Future<void> _loadDraft() async {
    final id = widget.draftId;
    if (id == null) return;
    final draft = await ref.read(draftStoreProvider).load(id);
    if (!mounted || draft == null) return;

    setState(() {
      _draftId = draft.id;
      if (_toController.text.trim().isEmpty) {
        _toController.text = draft.to.join(', ');
      }
      if (_ccController.text.trim().isEmpty && draft.cc.isNotEmpty) {
        _ccController.text = draft.cc.join(', ');
        _showCc = true;
      }
      if (_subjectController.text.trim().isEmpty) {
        _subjectController.text = draft.subject;
      }
      if (_bodyController.text.trim().isEmpty) {
        _bodyController.text = draft.bodyText;
      }
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    // No save here on purpose: reading a provider while the widget is being
    // unmounted is not allowed. The pending save is flushed by [PopScope]
    // before the screen goes away, and every keystroke already scheduled one.
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// Fills recipient and subject from the answered message, exactly once.
  ///
  /// Never overwrites text the user already typed: a slow database read must
  /// not delete a draft.
  Future<void> _prefillReply() async {
    final id = widget.replyToMessageId;
    if (id == null || _prefilled) return;
    _prefilled = true;

    final message = await ref.read(threadRepositoryProvider).getMessage(id);
    if (!mounted || message == null) return;

    setState(() {
      _replyTo = message;
      if (_toController.text.trim().isEmpty) {
        _toController.text = _replyRecipient(message);
      }
      if (_subjectController.text.trim().isEmpty) {
        _subjectController.text = _replySubject(message.subject);
      }
    });
  }

  /// Who a reply goes to: the sender, unless the message is one of ours — then
  /// it goes to the original recipients instead of back to ourselves.
  String _replyRecipient(Message message) {
    final own = ref.read(primaryAccountProvider)?.email.toLowerCase();
    final sender = message.from.address.toLowerCase();
    if (own != null && sender == own) {
      return message.to
          .map((address) => address.address)
          .where((address) => address.toLowerCase() != own)
          .join(', ');
    }
    return message.from.address;
  }

  /// RFC 5322: replies are prefixed once, and never stacked as `Re: Re:`.
  String _replySubject(String subject) {
    final trimmed = subject.trim();
    if (trimmed.isEmpty) return 'Re:';
    if (RegExp(r'^\s*(re|aw|ответ)\s*:', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }
    return 'Re: $trimmed';
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

  /// Schedules a save shortly after the user stops typing.
  void _onEdited() {
    setState(() {});
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, () => unawaited(_flushDraft()));
  }

  /// Writes the current text into the draft row.
  ///
  /// Silent on failure by design: a draft that cannot be written must not
  /// interrupt typing with a red banner. The text stays in the controller, and
  /// the next keystroke tries again.
  Future<void> _flushDraft() async {
    if (_finished) return;
    // Captured before any await: the screen may be gone by the time the write
    // finishes, and reaching into `ref` after that is a crash waiting to happen.
    final account = ref.read(primaryAccountProvider);
    final store = ref.read(draftStoreProvider);
    if (account == null) return;
    final hasContent = _toController.text.trim().isNotEmpty ||
        _subjectController.text.trim().isNotEmpty ||
        _bodyController.text.trim().isNotEmpty;
    if (!hasContent && _draftId == null) return;

    try {
      final saved = await store.save(
            account: account,
            to: _addressesOf(_toController.text),
            cc: _showCc ? _addressesOf(_ccController.text) : const <String>[],
            subject: _subjectController.text.trim(),
            bodyText: _bodyController.text,
            threadId: widget.threadId,
            replyToMessageId: widget.replyToMessageId,
            existingDraftId: _draftId,
          );
      if (saved != null && mounted) _draftId = saved.id;
    } catch (_) {
      // Nothing to do: see the comment above.
    }
  }

  Future<void> _send() async {
    final account = ref.read(primaryAccountProvider);
    if (account == null) return;
    if (!_validateRecipients()) return;

    final replyTo = _replyTo;
    final draft = OutgoingDraft(
      accountId: account.id,
      from: account.email,
      to: _addressesOf(_toController.text),
      cc: _showCc ? _addressesOf(_ccController.text) : const <String>[],
      subject: _subjectController.text.trim(),
      bodyText: _bodyController.text.trim(),
      threadId: widget.threadId,
      inReplyTo: replyTo?.messageIdHeader,
      references: <String>[
        ...?replyTo?.references,
        if (replyTo?.messageIdHeader != null) replyTo!.messageIdHeader!,
      ],
      replyToProviderMessageId: replyTo?.providerId,
    );

    // The draft row becomes the sent message: drop it first so a failure
    // cannot leave both a draft and a «Отправлено» copy of the same text.
    _finished = true;
    _autosaveTimer?.cancel();
    final draftId = _draftId;
    if (draftId != null) {
      await ref.read(draftStoreProvider).delete(draftId);
      _draftId = null;
    }

    await ref.read(sendControllerProvider.notifier).send(draft);
    if (!mounted) return;

    final state = ref.read(sendControllerProvider);
    if (state.isSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Письмо отправлено')),
      );
      _leaveAfterSend();
      return;
    }
    if (state.isQueued) {
      // Honest and reassuring at once: it will go out on its own.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Нет связи. Письмо сохранено и уйдёт само, как только появится '
            'интернет.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      _leaveAfterSend();
      return;
    }
    // Not sent: the text is still on screen, so autosave resumes.
    _finished = false;
  }

  List<String> _addressesOf(String raw) =>
      parseAddressList(raw).map((address) => address.address).toList(growable: false);

  /// Leaves the composer, choosing the destination by where we came from.
  void _leaveAfterSend() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Deep-linked into the composer: nowhere to go back to, so open the list.
    context.go(AppRoutes.conversations);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(primaryAccountProvider);
    final sendState = ref.watch(sendControllerProvider);
    final tokens = MellowColors.of(context);

    final canSend = account != null && !sendState.isSending;

    return PopScope<void>(
      // The system back gesture must not outrun the last keystroke either.
      onPopInvokedWithResult: (bool didPop, void _) {
        if (didPop && !_finished) unawaited(_flushDraft());
      },
      child: MellowScaffold(
        padding: false,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть',
            onPressed: () => _confirmDiscard(context),
          ),
          title: Text(_isReply ? 'Ответ' : 'Новое сообщение'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Вложения',
              icon: const Icon(Icons.attach_file),
              onPressed: () => _notImplemented(
                context,
                'Прикреплять файлы Mellow пока не умеет. Это в работе.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: MellowSpacing.md),
              child: IconButton.filled(
                tooltip: account == null
                    ? 'Сначала подключите аккаунт'
                    : 'Отправить',
                onPressed: canSend ? _send : null,
                icon: sendState.isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
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
            _AccountChip(account: account),
            if (sendState.error != null) ...<Widget>[
              const SizedBox(height: MellowSpacing.md),
              _ErrorNotice(
                message: sendState.error!,
                onRetry: canSend ? _send : null,
              ),
            ],
            const SizedBox(height: MellowSpacing.md),
            TextField(
              controller: _toController,
              readOnly: _isReply && _toController.text.trim().isNotEmpty,
              keyboardType: TextInputType.emailAddress,
              // An error shown for the previous value is stale as soon as the
              // user edits the field: keep it only until the next keystroke.
              onChanged: (_) {
                setState(() => _recipientError = null);
                _onEdited();
              },
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
                onChanged: (_) => _onEdited(),
                decoration: const InputDecoration(labelText: 'Копия'),
              ),
            ],
            const SizedBox(height: MellowSpacing.md),
            TextField(
              controller: _subjectController,
              onChanged: (_) => _onEdited(),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Тема',
                hintText: _isReply ? 'Re: …' : 'Сформируется автоматически',
              ),
            ),
            const SizedBox(height: MellowSpacing.lg),
            TextField(
              controller: _bodyController,
              minLines: 8,
              maxLines: null,
              autofocus: !_isReply,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => _onEdited(),
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
                    _footerNote(account),
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
      ),
    );
  }

  /// The truth about this build, in one sentence.
  ///
  /// Saying "sending works" for Gmail and "sending is not available" for the
  /// rest is exactly what the spec asks for: no feature is ever implied.
  String _footerNote(Account? account) {
    if (account == null) {
      return 'Аккаунт не подключён — подключите ящик, иначе отправлять некуда.';
    }
    if (account.provider != MailProviderKind.gmail) {
      return 'Из этого ящика Mellow пока отправить не может — сейчас '
          'работает только Gmail.';
    }
    return 'Письмо уйдёт из ${account.email} сразу после нажатия «Отправить».';
  }

  /// True when the user typed anything that is not saved anywhere yet.
  bool get _hasContent =>
      _toController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  Future<void> _confirmDiscard(BuildContext context) async {
    // A message that is already on its way must not disappear mid-flight.
    if (ref.read(sendControllerProvider).isSending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Письмо отправляется, подождите…')),
      );
      return;
    }

    // Read the controllers at press time: a frame built before the last
    // keystroke would otherwise decide there is nothing to lose.
    if (!_hasContent) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    // Nothing is lost any more, so the dialog only has to be honest about what
    // happens next — and it names where the draft can be found again.
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сохранить черновик?'),
        content: const Text(
          'Письмо останется в «Диалогах» с пометкой «Черновик». '
          'Открыть его можно в любой момент и продолжить.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (discard == true) {
      // Explicitly discarded: the stored copy goes away too.
      _finished = true;
      final id = _draftId;
      if (id != null) {
        await ref.read(draftStoreProvider).delete(id);
        _draftId = null;
      }
    } else {
      await _flushDraft();
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  void _notImplemented(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Row(
      children: <Widget>[
        Icon(Icons.alternate_email, size: 16, color: tokens.onSurfaceMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            account?.email ?? 'Аккаунт не подключён',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.onSurfaceMuted),
          ),
        ),
      ],
    );
  }
}

/// A failed send is visible, explained and retryable — never silent.
class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Container(
      padding: const EdgeInsets.all(MellowSpacing.md),
      decoration: BoxDecoration(
        color: tokens.danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(MellowRadius.md),
        border: Border.all(color: tokens.danger.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.onSurface),
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ),
        ],
      ),
    );
  }
}
