import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mellow/app/navigation/routes.dart';
import 'package:mellow/core/config/app_config.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/features/onboarding/application/gmail_connect_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// Gmail connection screen: consent → token exchange → first sync.
///
/// The screen is honest about each step: it shows the real stage and never
/// claims success before the sync returned.
class GmailConnectScreen extends ConsumerStatefulWidget {
  const GmailConnectScreen({required this.email, super.key});

  final String email;

  @override
  ConsumerState<GmailConnectScreen> createState() => _GmailConnectScreenState();
}

class _GmailConnectScreenState extends ConsumerState<GmailConnectScreen> {
  final TextEditingController _redirectController = TextEditingController();

  /// Listens for `com.googleusercontent.apps...:/oauth2redirect?code=...`.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribe before the browser opens: a cold start delivers the redirect
    // through this stream, and missing it would strand the user on this screen.
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _onRedirect,
      onError: (Object _) {},
    );
    // Kick the flow after the first frame so the progress UI is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _redirectController.dispose();
    // The controller is reset by the next `start()`, never from `dispose`:
    // touching a provider while the widget tree is being torn down is not safe.
    super.dispose();
  }

  bool get _isGmailConfigured => AppConfig.fromEnvironment.isGoogleConfigured;

  /// Handles the redirect delivered by Android/iOS.
  ///
  /// Only URIs that carry `code` or `error` are treated as the answer to this
  /// flow: ordinary deep links must not be mistaken for an authorisation reply.
  void _onRedirect(Uri uri) {
    final isAnswer =
        uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error');
    if (!isAnswer) return;
    if (!mounted) return;

    final state = ref.read(gmailConnectControllerProvider);
    if (state.step == GmailConnectStep.done ||
        state.step == GmailConnectStep.exchangingCode ||
        state.step == GmailConnectStep.verifying ||
        state.step == GmailConnectStep.syncing) {
      return;
    }

    ref.read(gmailConnectControllerProvider.notifier).complete(uri.toString());
  }

  Future<void> _start() async {
    final controller = ref.read(gmailConnectControllerProvider.notifier);
    await controller.start(widget.email);

    final uri = ref.read(gmailConnectControllerProvider).authorizationUri;
    if (uri == null) return;

    // Open the system browser: Google blocks OAuth in embedded webviews.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть браузер')),
      );
    }
  }

  /// Fills the field from the clipboard: the browser copies the redirect URL
  /// when the user long-presses the address bar, which is the shortest manual
  /// path until an app-link handler is wired up.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _redirectController.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gmailConnectControllerProvider);
    final tokens = MellowColors.of(context);
    final theme = Theme.of(context).textTheme;

    return MellowScaffold(
      title: 'Подключение Gmail',
      body: ListView(
        children: <Widget>[
          Text(widget.email, style: theme.titleMedium),
          const SizedBox(height: MellowSpacing.sm),
          Text(
            'Mellow использует официальный OAuth 2.0 Google. Пароль от почты '
            'приложение не видит и не хранит.',
            style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: MellowSpacing.xl),
          _StepRow(
            label: 'Подтверждение в браузере',
            done: state.step.index > GmailConnectStep.awaitingConsent.index,
            active: state.step == GmailConnectStep.awaitingConsent,
          ),
          _StepRow(
            label: 'Получение токена доступа',
            done: state.step.index > GmailConnectStep.exchangingCode.index,
            active: state.step == GmailConnectStep.exchangingCode,
          ),
          _StepRow(
            label: 'Проверка доступа к ящику',
            done: state.step.index > GmailConnectStep.verifying.index,
            active: state.step == GmailConnectStep.verifying,
          ),
          _StepRow(
            label: 'Загрузка последних писем',
            done: state.step == GmailConnectStep.done,
            active: state.step == GmailConnectStep.syncing,
          ),
          const SizedBox(height: MellowSpacing.xl),
          if (!_isGmailConfigured)
            Container(
              margin: const EdgeInsets.only(bottom: MellowSpacing.md),
              padding: const EdgeInsets.all(MellowSpacing.md),
              decoration: BoxDecoration(
                color: tokens.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(MellowRadius.md),
                border: Border.all(color: tokens.warning.withOpacity(0.35)),
              ),
              child: Text(
                'Эта сборка собрана без GOOGLE_CLIENT_ID, поэтому вход в Gmail '
                'не сможет открыть согласие Google. Всё остальное приложение '
                '(интерфейс, темы, локальные данные) работает.',
                style: theme.bodySmall?.copyWith(color: tokens.warning),
              ),
            ),
          if (state.message != null && state.error == null)
            Text(state.message!, style: theme.bodyMedium),
          if (state.error != null)
            Container(
              padding: const EdgeInsets.all(MellowSpacing.md),
              decoration: BoxDecoration(
                color: tokens.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(MellowRadius.md),
                border: Border.all(color: tokens.danger.withOpacity(0.35)),
              ),
              child: Text(
                state.error!,
                style: theme.bodySmall?.copyWith(color: tokens.danger),
              ),
            ),
          const SizedBox(height: MellowSpacing.xl),
          if (state.step == GmailConnectStep.awaitingConsent ||
              state.step == GmailConnectStep.failed) ...<Widget>[
            Text(
              'Если браузер не вернулся в приложение автоматически, вставьте '
              'адрес из адресной строки сюда:',
              style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: MellowSpacing.sm),
            TextField(
              controller: _redirectController,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'com.googleusercontent.apps...:/oauth2redirect?code=…',
                suffixIcon: IconButton(
                  tooltip: 'Вставить из буфера',
                  icon: const Icon(Icons.content_paste, size: 18),
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: MellowSpacing.sm),
            FilledButton(
              onPressed: () {
                final raw = _redirectController.text.trim();
                if (raw.isEmpty) return;
                ref
                    .read(gmailConnectControllerProvider.notifier)
                    .complete(raw);
              },
              child: const Text('Завершить подключение'),
            ),
            const SizedBox(height: MellowSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                state.authorizationUri ??
                    Uri.parse('https://accounts.google.com'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Открыть браузер снова'),
            ),
          ],
          if (state.step == GmailConnectStep.done) ...<Widget>[
            FilledButton(
              onPressed: () => context.go(AppRoutes.conversations),
              child: const Text('К диалогам'),
            ),
            const SizedBox(height: MellowSpacing.sm),
            OutlinedButton(
              onPressed: () => context.push(AppRoutes.sync),
              child: const Text('Открыть синхронизацию'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final color = done
        ? tokens.success
        : active
            ? tokens.accent
            : tokens.onSurfaceMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: MellowSpacing.md),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: done
                ? Icon(Icons.check_circle, size: 20, color: color)
                : active
                    ? CircularProgressIndicator(strokeWidth: 2, color: color)
                    : Icon(Icons.circle_outlined, size: 20, color: color),
          ),
          const SizedBox(width: MellowSpacing.md),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: done || active ? tokens.onSurface : tokens.onSurfaceMuted,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
