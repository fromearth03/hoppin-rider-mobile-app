import 'package:flutter/material.dart';

/// One label/value line inside a receipt card.
///
/// Shared by the journey summary and the fare card so both read as one
/// system rather than two ad-hoc layouts.
class ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;

  const ReceiptRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: emphasise
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
