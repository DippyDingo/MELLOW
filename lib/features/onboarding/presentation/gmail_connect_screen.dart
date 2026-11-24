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
  String? _manualError;

  /// True when the redirect arrived with the launch itself, so the browser
  /// must not be opened again on top of it.
  bool _answeredFromColdStart = false;

  /// Listens for `com.googleusercontent.apps...:/oauth2redirect?code=...`.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribe before the browser opens: a warm redirect arrives through this
    // stream, and missing it would strand the user on this screen.
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _onRedirect,
      onError: (Object _) {},
    );
    // Kick the flow after the first frame so the progress UI is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// Decides what this screen should do when it opens.
  ///
  /// Three cases matter, and they are easy to confuse:
  /// * the OS launched Mellow *because* the browser came back — the answer is
  ///   in `getInitialLink()`, and the flow must be finished, not restarted;
  /// * Mellow was killed while the consent screen was open — the PKCE secret is
  ///   restored from the keystore, then the same redirect is applied;
  /// * nothing pending — open the browser as usual.
  Future<void> _start() async {
    await _handleColdStartLink();

    final controller = ref.read(gmailConnectControllerProvider.notifier);
    final restored = await controller.restorePending();
    if (!mounted) return;
    // The redirect was the launch: the flow is already finishing, and opening
    // the browser again would throw the answer away.
    if (_answeredFromColdStart) return;

    // Reuse the consent link of a restored flow instead of minting a new one:
    // the PKCE secret in the keystore only matches the original request.
    if (!restored) await controller.start(widget.email);

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

  /// Applies a redirect that launched the app, before anything else runs.
  Future<void> _handleColdStartLink() async {
    if (!_isGmailConfigured) return;
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial == null) return;
      final isAnswer = initial.queryParameters.containsKey('code') ||
          initial.queryParameters.containsKey('error');
      if (!isAnswer) return;
      // The PKCE secret must be back in memory before the code is redeemed.
      await ref.read(gmailConnectControllerProvider.notifier).restorePending();
      if (!mounted) return;
      _answeredFromColdStart = true;
      await ref
          .read(gmailConnectControllerProvider.notifier)
          .complete(initial.toString());
    } catch (_) {
      // A malformed initial link is treated as «no link»: the normal path below
      // still lets the user start the flow again.
    }
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

  /// Fills the field from the clipboard: the browser can copy the redirect URL
  /// when the user long-presses the address bar, which is the shortest manual
  /// path while the automatic return is not working.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _redirectController.text = text;
  }

  /// Pulls the code out of whatever the user pasted.
  ///
  /// People paste the whole address, a truncated one, or only the code; the
  /// flow only needs `code`. Returns null when nothing usable is there, so the
  /// screen can say so instead of silently doing nothing.
  String? _codeFrom(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final fromUri = uri?.queryParameters['code'];
    if (fromUri != null && fromUri.isNotEmpty) return fromUri;
    // A bare code (no URL at all) is accepted: Google codes are long and start
    // with `4/`.
    if (!text.contains('://') && !text.contains(' ')) return text;
    return null;
  }

  /// Sends the pasted answer into the flow, or explains why it cannot.
  Future<void> _submitManual() async {
    final raw = _redirectController.text;
    final code = _codeFrom(raw);
    if (code == null) {
      setState(() {
        _manualError =
            'В этой строке нет кода авторизации. Скопируйте адрес из адресной '
            'строки браузера целиком — в нём есть «code=…».';
      });
      return;
    }
    setState(() => _manualError = null);
    await ref.read(gmailConnectControllerProvider.notifier).complete(raw.trim());
  }

  /// Opens the browser again with the same consent link.
  Future<void> _openBrowser() async {
    final Uri? uri =
        ref.read(gmailConnectControllerProvider).authorizationUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                'В этой сборке нет доступа к Google, поэтому подключить ящик '
                'нельзя. Это ограничение сборки, а не ошибка ваших действий.',
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
          if (!_isGmailConfigured) ...<Widget>[
            Text(
              'Что делать сейчас',
              style: theme.titleMedium,
            ),
            const SizedBox(height: MellowSpacing.sm),
            const Text(
              'Вводить ничего не нужно. В этой сборке нет доступа к Google — '
              'подключение ящика включится, когда сборка получит его.',
            ),
          ] else if (state.step == GmailConnectStep.awaitingConsent ||
              state.step == GmailConnectStep.failed) ...<Widget>[
            Text('Что делать сейчас', style: theme.titleMedium),
            const SizedBox(height: MellowSpacing.sm),
            const _NumberedStep(
              number: 1,
              text: 'В открывшемся браузере выберите аккаунт Gmail и нажмите '
                  '«Разрешить». Пароль Mellow не увидит.',
            ),
            const _NumberedStep(
              number: 2,
              text: 'После согласия Google вернёт вас в Mellow сам. Если '
                  'вернул в браузер — скопируйте адрес из адресной строки '
                  'целиком (долгое нажатие → «Копировать»).',
            ),
            const _NumberedStep(
              number: 3,
              text: 'Вернитесь сюда: вставьте адрес в поле ниже и нажмите '
                  '«Продолжить». Обычно шаг 2 срабатывает сам, и поле ниже не '
                  'нужно.',
            ),
            const SizedBox(height: MellowSpacing.md),
            OutlinedButton.icon(
              onPressed: _openBrowser,
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Открыть браузер ещё раз'),
            ),
            const SizedBox(height: MellowSpacing.lg),
            Text(
              'Если приложение не вернулось само',
              style: theme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: MellowSpacing.sm),
            TextField(
              controller: _redirectController,
              autocorrect: false,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Вставьте адрес из браузера',
                errorText: _manualError,
                suffixIcon: IconButton(
                  tooltip: 'Вставить из буфера',
                  icon: const Icon(Icons.content_paste, size: 18),
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: MellowSpacing.sm),
            FilledButton(
              onPressed: _submitManual,
              child: const Text('Продолжить'),
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

/// One line of the «what to do now» instructions.
///
/// Numbered because the flow crosses two apps (Mellow and the browser) and
/// people lose track of where they are; plain prose did not survive the trip.
class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final MellowColors tokens = MellowColors.of(context);
    final TextTheme theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: MellowSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.labelSmall?.copyWith(color: tokens.accent),
            ),
          ),
          const SizedBox(width: MellowSpacing.sm),
          Expanded(child: Text(text, style: theme.bodySmall)),
        ],
      ),
    );
  }
}
