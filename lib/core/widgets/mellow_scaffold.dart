import 'package:flutter/material.dart';
import 'package:mellow/core/theme/mellow_theme.dart';

/// Page shell that applies the token background and consistent safe-area
/// handling. Every screen uses this instead of a raw [Scaffold].
class MellowScaffold extends StatelessWidget {
  const MellowScaffold({
    required this.body,
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBar,
    this.padding = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;

  /// Wraps [body] in the standard horizontal padding.
  final bool padding;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: appBar ??
          (title == null
              ? null
              : AppBar(
                  title: Text(title!),
                  leading: leading,
                  actions: actions,
                )),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: padding
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MellowSpacing.lg,
                ),
                child: body,
              )
            : body,
      ),
    );
  }
}

/// Centered placeholder used by empty lists, error states and "no results".
class MellowEmptyState extends StatelessWidget {
  const MellowEmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MellowSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: tokens.onSurfaceMuted),
            const SizedBox(height: MellowSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(color: tokens.onSurface),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: MellowSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: tokens.onSurfaceMuted),
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: MellowSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Thin section header used across settings and contact screens.
class MellowSectionHeader extends StatelessWidget {
  const MellowSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = MellowColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MellowSpacing.xs,
        MellowSpacing.xl,
        MellowSpacing.xs,
        MellowSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.onSurfaceMuted,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
