import 'package:flutter/material.dart';

import '../../../../core/money.dart';
import '../../data/fare_repository.dart';

/// Per-leg fare lines for a multi-stop quote, with the money model spelled
/// out — copy close to verbatim, per the backend's own wording, since a
/// rider seeing three legs may reasonably fear being charged three times.
class FareLegsBreakdown extends StatelessWidget {
  final List<FareLeg> legs;
  final Pence totalPence;

  const FareLegsBreakdown({
    super.key,
    required this.legs,
    required this.totalPence,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final leg in legs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    leg.toLabel,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(leg.farePence.format(), style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Stops are priced per leg and added up. Fees are charged once on '
          'the total.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
