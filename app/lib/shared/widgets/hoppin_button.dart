import 'package:flutter/material.dart';

/// Primary action button.
///
/// A loading button is disabled, not merely decorated: double-submitting a
/// sign-up creates a second auth user, which cannot be undone from the app.
class HoppinButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const HoppinButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : Text(label),
    );
  }
}
