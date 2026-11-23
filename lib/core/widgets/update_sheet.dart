import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/utils/update_check.dart';
import 'package:mellow/features/updates/application/update_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the «what's new» sheet. Callable from the banner and from settings.
Future<void> openUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const UpdateSheet(),
  );
}

/// Bottom sheet: release notes, download, progress and the install button.
///
/// The install step is intentionally a button, not an automatic action: Android
/// shows its own confirmation and a silent install is impossible on a phone
/// without root. Promising «обновится само» would be a lie.
class UpdateSheet extends ConsumerWidget {
  const UpdateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateState state = ref.watch(updateControllerProvider);
    final UpdateController controller = ref.read(updateControllerProvider.notifier);
    final MellowColors tokens = MellowColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final UpdateRelease? release = state.release;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MellowSpacing.xl,
          0,
          MellowSpacing.xl,
          MellowSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              release?.title ?? 'Обновление Mellow',
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: MellowSpacing.xs),
            Text(
              _subtitle(release),
              style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: MellowSpacing.lg),
            if ((release?.notes ?? '').trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(MellowSpacing.md),
                decoration: BoxDecoration(
                  color: tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(MellowRadius.md),
                ),
                child: Text(
                  release!.notes!.trim(),
                  style: textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: MellowSpacing.lg),
            if (state.phase == UpdatePhase.downloading)
              _DownloadProgress(state: state, onCancel: controller.cancelDownload)
            else if (state.filePath != null)
              _InstallBlock(state: state)
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: controller.download,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(
                    'Скачать · ${_size(release?.sizeBytes ?? 0)}',
                  ),
                ),
              ),
            if (state.message != null) ...<Widget>[
              const SizedBox(height: MellowSpacing.md),
              Text(
                state.message!,
                style: textTheme.bodySmall?.copyWith(
                  color: state.phase == UpdatePhase.failed
                      ? tokens.danger
                      : tokens.onSurfaceMuted,
                ),
              ),
            ],
            const SizedBox(height: MellowSpacing.sm),
            Center(
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(UpdateChannel.releasesUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Все сборки на GitHub'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(UpdateRelease? release) {
    if (release == null) return 'Проверьте обновления в разделе «О приложении»';
    final DateTime? at = release.publishedAt;
    final String date = at == null
        ? ''
        : ' · собрано ${at.day}.${at.month.toString().padLeft(2, '0')}.${at.year}';
    return 'Сборка ${release.shortSha}$date';
  }

  static String _size(int bytes) {
    if (bytes <= 0) return 'неизвестный размер';
    return '${(bytes / (1024 * 1024)).round()} МБ';
  }
}

/// Progress, transferred size and a way out mid-transfer.
class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.state, required this.onCancel});

  final UpdateState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final MellowColors tokens = MellowColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(MellowRadius.pill),
          child: LinearProgressIndicator(
            value: state.progress == 0 ? null : state.progress,
            minHeight: 6,
            backgroundColor: tokens.surfaceMuted,
          ),
        ),
        const SizedBox(height: MellowSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '${(state.progress * 100).round()}% · '
              '${UpdateSheet._size(state.receivedBytes)} из '
              '${UpdateSheet._size(state.totalBytes)}',
              style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
            ),
            TextButton(onPressed: onCancel, child: const Text('Отмена')),
          ],
        ),
      ],
    );
  }
}

/// The last step: hand the file to Android's own installer.
class _InstallBlock extends StatelessWidget {
  const _InstallBlock({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final MellowColors tokens = MellowColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _install(context),
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Установить'),
          ),
        ),
        const SizedBox(height: MellowSpacing.sm),
        Text(
          'Android спросит подтверждение. Данные — аккаунты, письма, настройки — '
          'сохраняются при обновлении поверх.',
          style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
        ),
      ],
    );
  }

  Future<void> _install(BuildContext context) async {
    final Future<void> Function(String path)? opener = _opener;
    final String? path = state.filePath;
    if (path == null) return;

    if (opener == null) {
      // The plugin is not wired into this build yet.
      await launchUrl(
        Uri.parse(UpdateChannel.releasesUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    if (!await File(path).exists()) {
      return;
    }
    await opener(path);
  }

  /// Injected by the app once the `open_filex` plugin is available; keeps this
  /// widget buildable and testable before the plugin is added to `pubspec`.
  static Future<void> Function(String path)? _opener;
}

/// Lets the composition root connect the platform installer.
// ignore: use_setters_to_change_properties
void registerInstaller(Future<void> Function(String path) opener) {
  _InstallBlock._opener = opener;
}
