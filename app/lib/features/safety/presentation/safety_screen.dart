import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/safety_repository.dart';

final emergencyContactsProvider =
    FutureProvider.autoDispose<List<EmergencyContact>>((ref) async {
  final result = await ref.watch(safetyRepositoryProvider).listContacts();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

final platformContactsProvider =
    FutureProvider.autoDispose<PlatformContacts>((ref) async {
  final result = await ref.watch(safetyRepositoryProvider).platformContacts();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// Safety: raise an alarm, share the trip, reach support.
///
/// The SOS here is REAL. It writes a row and surfaces on the admin safety
/// dashboard, so it is behind a confirmation - an accidental tap that dispatches
/// a live alert costs someone's time and erodes trust in the button.
class SafetyScreen extends ConsumerStatefulWidget {
  /// Null when the rider is not on a trip. The alarm still works.
  final String? rideId;

  const SafetyScreen({super.key, this.rideId});

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  bool _raising = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _confirmAndRaise() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise an emergency alert?'),
        content: const Text(
          'Our safety team is notified immediately and will contact you. '
          'Only use this if you feel unsafe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            child: const Text('Raise alert'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _raising = true;
      _message = null;
    });

    // No position is sent: this app has no location permission wired yet, and
    // sending 0,0 would place the rider in the Atlantic on the safety
    // dashboard - worse than sending nothing. The alert still reaches the team.
    final result = await ref
        .read(safetyRepositoryProvider)
        .raiseSos(rideId: widget.rideId);

    if (!mounted) return;
    setState(() {
      _raising = false;
      switch (result) {
        case Ok():
          _message = 'Alert raised. Our safety team has been notified.';
          _messageIsError = false;
        case Err(:final error):
          // Never a silent failure. Telling someone help is coming when it is
          // not is the worst outcome this screen has.
          _message = RiderErrorCopy.messageFor(error);
          _messageIsError = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contacts = ref.watch(emergencyContactsProvider);
    final platform = ref.watch(platformContactsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SosButton(busy: _raising, onPressed: _confirmAndRaise),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _messageIsError
                    ? AppColors.negative
                    : AppColors.positive,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Emergency contacts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _Contacts(contacts: contacts),
          const SizedBox(height: 28),
          Text('Get help', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _PlatformContacts(contacts: platform),
        ],
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;

  const _SosButton({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Material(
        color: AppColors.negative,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: busy ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: busy
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 40),
                      const SizedBox(height: 6),
                      Text('SOS',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Contacts extends StatelessWidget {
  final AsyncValue<List<EmergencyContact>> contacts;
  const _Contacts({required this.contacts});

  @override
  Widget build(BuildContext context) {
    return contacts.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(
        e is ApiException
            ? RiderErrorCopy.messageFor(e)
            : 'Could not load your contacts.',
        style: const TextStyle(color: AppColors.negative),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            'No emergency contacts yet. Add someone we can reach if you '
            'need help.',
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }
        return Column(
          children: [
            // Every contact rendered here has a name AND a number - the
            // repository drops any that could not actually be rung, because a
            // contact whose call button does nothing is worse than none.
            for (final c in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(c.name),
                  subtitle: Text(c.relationship == null
                      ? c.phone
                      : '${c.relationship} · ${c.phone}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlatformContacts extends StatelessWidget {
  final AsyncValue<PlatformContacts> contacts;
  const _PlatformContacts({required this.contacts});

  @override
  Widget build(BuildContext context) {
    return contacts.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (c) => Column(
        children: [
          // Each row appears only when its number exists. The server returns
          // blanks rather than a 404 when nothing is configured, so a missing
          // number must not render as an empty, tappable row.
          if (c.emergencyPhone != null)
            _Row(
                icon: Icons.local_police_outlined,
                label: 'Emergency services',
                value: c.emergencyPhone!),
          if (c.supportPhone != null)
            _Row(
                icon: Icons.support_agent_outlined,
                label: 'Hoppin support',
                value: c.supportPhone!),
          if (c.supportEmail != null)
            _Row(
                icon: Icons.mail_outline,
                label: 'Email support',
                value: c.supportEmail!),
          if (c.whatsappNumber != null)
            _Row(
                icon: Icons.chat_outlined,
                label: 'WhatsApp',
                value: c.whatsappNumber!),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
