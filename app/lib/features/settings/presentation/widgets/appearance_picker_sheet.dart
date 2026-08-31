import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_mode_provider.dart';

/// Opens the Appearance picker, matching the first card in `Group 968.png`:
/// a rounded grouped card with Dark / Light / Default rows, each with a
/// leading icon and a trailing radio button.
///
/// This is the one row on the Settings screen with a real effect: choosing
/// an option here writes straight to [themeModeProvider], which
/// `HoppinApp.build` reads for `MaterialApp.themeMode`. The choice changes
/// the resolved theme immediately and lives only for the current session.
Future<void> showAppearancePickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _AppearancePickerSheet(),
  );
}

class _AppearancePickerSheet extends ConsumerWidget {
  const _AppearancePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (mode) {
              if (mode != null) _select(context, ref, mode);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AppearanceOptionRow(
                  icon: Icons.nightlight_round,
                  label: 'Dark',
                  value: ThemeMode.dark,
                  onTap: () => _select(context, ref, ThemeMode.dark),
                ),
                _divider(theme),
                _AppearanceOptionRow(
                  icon: Icons.nightlight_outlined,
                  label: 'Light',
                  value: ThemeMode.light,
                  onTap: () => _select(context, ref, ThemeMode.light),
                ),
                _divider(theme),
                _AppearanceOptionRow(
                  icon: Icons.lightbulb_outline,
                  label: 'Default',
                  value: ThemeMode.system,
                  onTap: () => _select(context, ref, ThemeMode.system),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) => Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: theme.brightness == Brightness.light
            ? AppColors.lightBorder
            : AppColors.darkBorder,
      );

  void _select(BuildContext context, WidgetRef ref, ThemeMode mode) {
    ref.read(themeModeProvider.notifier).state = mode;
    Navigator.of(context).maybePop();
  }
}

class _AppearanceOptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeMode value;
  final VoidCallback onTap;

  const _AppearanceOptionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.textTheme.bodyLarge?.color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyLarge),
            ),
            // The group's value and onChanged live on the ancestor
            // RadioGroup<ThemeMode> above -- this Radio only needs to say
            // which value it represents.
            Radio<ThemeMode>(
              value: value,
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
