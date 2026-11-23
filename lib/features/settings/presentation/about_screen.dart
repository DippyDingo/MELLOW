import 'package:flutter/material.dart';
import 'package:mellow/core/theme/mellow_theme.dart';
import 'package:mellow/core/widgets/mellow_scaffold.dart';

/// About screen: version, product promise and honest limitations.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;

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
}
