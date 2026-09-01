import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The vehicle category picked on the HOME screen, carried through route
/// entry into fare-confirm so the rider is not asked twice: picked → the
/// confirm screen arrives preselected with its quote loading; not picked →
/// the confirm screen offers the grid as before.
final draftVehicleCategoryProvider = StateProvider<String?>((_) => null);
