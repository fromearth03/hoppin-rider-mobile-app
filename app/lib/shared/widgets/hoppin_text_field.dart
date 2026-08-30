import 'package:flutter/material.dart';

/// Labelled input matching the auth screens.
///
/// The label sits above the field rather than floating inside it, so it stays
/// readable while the field holds text – the design draws it that way and it
/// is the more accessible arrangement.
class HoppinTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? errorText;
  final Widget? prefixIcon;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  const HoppinTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.errorText,
    this.prefixIcon,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          enabled: enabled,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            prefixIcon: prefixIcon,
          ),
        ),
      ],
    );
  }
}
