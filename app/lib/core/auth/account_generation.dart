import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Changes on authentication transitions, not on token refresh.
final accountGenerationProvider = StateProvider<int>((ref) => 0);
