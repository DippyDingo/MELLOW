import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/features/updates/application/update_controller.dart';
import 'package:mellow/core/widgets/update_sheet.dart';

/// In-app notice that a newer build is on GitHub.
///
/// Lives in `core/widgets` because two features show it: the inbox places it
/// above the list, and «О приложении» shows the same notice under the version.
/// It appears once, stays until acted on or dismissed, and hides itself for the
/// current build after «Позже».
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateState state = ref.watch(updateControllerProvider);
    if (!state.showBanner) return const SizedBox.shrink();

    final MellowColors tokens = MellowColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool downloading = state.phase == UpdatePhase.downloading;
    final bool ready = state.phase == UpdatePhase.downloaded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MellowSpacing.lg,
        0,
        MellowSpacing.lg,
        MellowSpacing.sm,
      ),
      child: Material(
        color: tokens.accentContainer,
        borderRadius: BorderRadius.circular(MellowRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(MellowSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.system_update_alt, size: 18, color: tokens.accent),
                  const SizedBox(width: MellowSpacing.sm),
                  Expanded(
                    child: Text(
                      ready
                          ? 'Обновление готово к установке'
                          : 'Доступно обновление',
                      style: textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(updateControllerProvider.notifier).dismiss(),
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Позже',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, bottom: MellowSpacing.sm),
                child: Text(
                  _subtitle(state),
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ),
              if (downloading)
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: MellowSpacing.sm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(MellowRadius.pill),
                    child: LinearProgressIndicator(
                      value: state.progress == 0 ? null : state.progress,
                      minHeight: 4,
                      backgroundColor: tokens.surface,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Row(
                  children: <Widget>[
                    if (downloading)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ref
                              .read(updateControllerProvider.notifier)
                              .cancelDownload(),
                          child: const Text('Отмена'),
                        ),
                      )
                    else if (ready)
                      Expanded(
                        child: FilledButton(
                          onPressed: () => openUpdateSheet(context),
                          child: const Text('Установить'),
                        ),
                      )
                    else
                      Expanded(
                        child: FilledButton(
                          onPressed: () => openUpdateSheet(context),
                          child: const Text('Обновить'),
                        ),
                      ),
                    if (!downloading && !ready) ...<Widget>[
                      const SizedBox(width: MellowSpacing.sm),
                      OutlinedButton(
                        onPressed: () => ref
                            .read(updateControllerProvider.notifier)
                            .dismiss(),
                        child: const Text('Позже'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(UpdateState state) {
    final String build = state.release?.title ?? 'новая сборка';
    return switch (state.phase) {
      UpdatePhase.downloading =>
        'Скачиваем $build · ${_percent(state)}% · ${_size(state.receivedBytes)} из ${_size(state.totalBytes)}',
      UpdatePhase.downloaded => '$build скачана. Осталось подтвердить установку.',
      _ => '$build · ${_size(state.release?.sizeBytes ?? 0)}',
    };
  }

  static String _percent(UpdateState state) =>
      (state.progress * 100).round().toString();

  static String _size(int bytes) {
    if (bytes <= 0) return '0 МБ';
    final double mb = bytes / (1024 * 1024);
    return '${mb.round()} МБ';
  }
}
