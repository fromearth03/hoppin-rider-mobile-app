import 'package:flutter/material.dart';

/// Labelled input matching the auth screens.
///
/// The label floats on the field's top border, as the design draws it. A
/// password field carries its own eye toggle inside the field on the right;
/// callers pass [obscurable] rather than managing the toggle themselves, so
/// every password field in the app behaves the same way.
class HoppinTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;

  /// Renders as a password field: text is hidden and an eye toggle appears
  /// inside the field.
  final bool obscurable;
  final TextInputType? keyboardType;
  final String? errorText;
  final Widget? prefixIcon;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? Function(String?)? validator;
  final AutovalidateMode? autovalidateMode;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;

  const HoppinTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.obscurable = false,
    this.keyboardType,
    this.errorText,
    this.prefixIcon,
    this.onChanged,
    this.enabled = true,
    this.validator,
    this.autovalidateMode,
    this.autofillHints,
    this.textInputAction,
  });

  @override
  State<HoppinTextField> createState() => _HoppinTextFieldState();
}

class _HoppinTextFieldState extends State<HoppinTextField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final obscured = widget.obscurable && _hidden;

    return TextFormField(
      controller: widget.controller,
      obscureText: obscured,
      keyboardType: widget.keyboardType,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.obscurable
            ? IconButton(
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                // Screen readers otherwise announce an unlabelled button, and
                // the icon alone does not say what it will do.
                tooltip: _hidden ? 'Show password' : 'Hide password',
              )
            : null,
      ),
    );
  }
}
