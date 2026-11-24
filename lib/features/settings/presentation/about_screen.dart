import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/update_check.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';
import 'package:mellow/core/widgets/update_banner.dart';
import 'package:mellow/features/updates/application/update_controller.dart';

/// About screen: version, update state, product promise and honest limits.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  /// Kept in step with `pubspec.yaml`; the settings screen shows it as «Версия».
  static const String version = '1.0.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final UpdateState update = ref.watch(updateControllerProvider);

    return MellowScaffold(
      title: 'О приложении',
      body: ListView(
        children: <Widget>[
          const SizedBox(height: MellowSpacing.lg),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(MellowRadius.lg),
              ),
              child: Icon(Icons.mail_outline, color: tokens.accent, size: 36),
            ),
          ),
          const SizedBox(height: MellowSpacing.md),
          Center(child: Text('Mellow', style: textTheme.headlineSmall)),
          Center(
            child: Text(
              'Версия $version',
              style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
          ),
          const SizedBox(height: MellowSpacing.md),
          Center(
            child: Text(
              UpdateChannel.buildSha.isEmpty
                  ? 'Сборка: локальная'
                  : 'Сборка: ${UpdateChannel.buildSha}',
              style: textTheme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
          ),
          const SizedBox(height: MellowSpacing.sm),
          const UpdateBanner(),
          if (UpdateChannel.isConfigured)
            Center(
              child: update.phase == UpdatePhase.checking
                  ? const Padding(
                      padding: EdgeInsets.all(MellowSpacing.sm),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => ref
                          .read(updateControllerProvider.notifier)
                          .check(automatic: false),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Проверить обновления'),
                    ),
            ),
          if (UpdateChannel.isConfigured)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MellowSpacing.xl),
              child: Text(
                _stateLabel(update),
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
              ),
            ),
          const SizedBox(height: MellowSpacing.xl),
          Text(
            'Email, который ощущается как мессенджер.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: MellowSpacing.lg),
          Text(
            'Mellow не является почтовым сервером. Приложение подключается к '
            'вашим существующим ящикам и работает с ними через официальные '
            'протоколы.',
            style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: MellowSpacing.md),
          Text(
            'Скорость доставки, ограничения отправки и подтверждения прочтения '
            'определяются почтовым провайдером. Статус «Отправлено» означает, что '
            'сервер принял письмо, а не что адресат его прочитал.',
            style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: MellowSpacing.xxl),
        ],
      ),
    );
  }

  /// One honest line about where the update flow stands.
  ///
  /// Every branch is a fact the app knows: it never says «обновлений нет»
  /// when the check failed, and never promises a silent install.
  static String _stateLabel(UpdateState update) {
    return switch (update.phase) {
      UpdatePhase.checking => 'Проверяем GitHub…',
      UpdatePhase.available => 'Доступна новая сборка. Обновление ставится '
          'по подтверждению, данные сохраняются.',
      UpdatePhase.downloading => 'Скачиваем обновление…',
      UpdatePhase.downloaded => 'Обновление скачано и ждёт подтверждения.',
      UpdatePhase.upToDate => 'Установлена последняя сборка.',
      UpdatePhase.failed => update.message ?? 'Не удалось проверить обновления.',
      UpdatePhase.idle => 'Обновления не проверялись.',
    };
  }
}
