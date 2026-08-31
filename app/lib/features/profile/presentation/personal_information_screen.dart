import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/hoppin_text_field.dart';
import '../../auth/data/profile_repository.dart';
import '../application/personal_information_controller.dart';
import '../domain/personal_information_state.dart';

/// View and edit the rider's own profile.
///
/// Diverges from `Personal Information.png` in ways recorded in
/// `docs/SCREEN-DECISIONS.md`'s Auth section (the same reasoning applies
/// here, this screen simply postdates that log):
///
/// - **One "Full name" field, not First/Last.** The backend stores a single
///   `full_name`. Splitting it on display and rejoining on save could never
///   reliably round-trip a compound name.
/// - **Email is read-only.** `ProfileRepository.patch` has no email
///   parameter — the API cannot change it, so an editable field here would
///   be a control that always fails.
/// - **No "verified, contact support" lock on name/photo.** Nothing in the
///   API marks name or avatar as locked; `full_name` is a plain patchable
///   field like any other, so presenting it as immutable would misrepresent
///   what the backend actually allows.
/// The avatar bytes, fetched with auth. The image routes 401 a plain
/// `NetworkImage` — on web an `<img>` tag cannot carry the bearer token —
/// so the bytes come through the authenticated client and render from
/// memory. Null (initials fallback) on any failure.
final avatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, url) async {
  final result = await ref.watch(apiClientProvider).getBytes(url);
  return switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
});

class PersonalInformationScreen extends ConsumerStatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  ConsumerState<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState
    extends ConsumerState<PersonalInformationScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  RiderProfile? _loadedProfile;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Seeds the editable fields the first time the profile arrives, and again
  /// whenever a fresh profile replaces the one currently loaded (e.g. after a
  /// successful save returns the server's own copy). Only running this on
  /// object identity/content change — not on every build — keeps it from
  /// stomping over text the rider is mid-edit on unrelated rebuilds (a
  /// `isSaving` flip, for instance).
  void _syncControllers(RiderProfile profile) {
    if (identical(_loadedProfile, profile)) return;
    _loadedProfile = profile;
    _name.text = profile.fullName;
    _phone.text = profile.phoneNumber ?? '';
    _email.text = profile.email;
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter your name');
      return;
    }
    setState(() => _nameError = null);

    final phone = _phone.text.trim();
    ref.read(personalInformationControllerProvider.notifier).save(
          fullName: name,
          phoneNumber: phone.isEmpty ? null : phone,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(personalInformationControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        centerTitle: true,
      ),
      body: switch (state.status) {
        PersonalInformationStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        PersonalInformationStatus.error => _ErrorView(
            message: state.loadError?.message ??
                'Something went wrong. Try again.',
            onRetry: () =>
                ref.read(personalInformationControllerProvider.notifier).load(),
          ),
        PersonalInformationStatus.ready => _buildForm(context, theme, state),
      },
    );
  }

  Widget _buildForm(
      BuildContext context, ThemeData theme, PersonalInformationState state) {
    final profile = state.profile;
    if (profile == null) {
      // Unreachable in practice -- `ready` is only ever set alongside a
      // profile -- but keeps the switch total without a null-check crash.
      return const SizedBox.shrink();
    }
    _syncControllers(profile);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  Builder(builder: (context) {
                    final bytes = profile.avatarUrl == null
                        ? null
                        : ref
                            .watch(avatarBytesProvider(profile.avatarUrl!))
                            .valueOrNull;
                    return CircleAvatar(
                      radius: 56,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      backgroundImage:
                          bytes != null ? MemoryImage(bytes) : null,
                      child: bytes == null
                          ? Text(
                              _initials(profile.fullName),
                              style: theme.textTheme.headlineLarge,
                            )
                          : null,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 28),
            HoppinTextField(
              label: 'Full name',
              controller: _name,
              errorText: _nameError,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 18),
            HoppinTextField(
              label: 'Email',
              controller: _email,
              enabled: false,
              prefixIcon: const Icon(Icons.mail_outline),
            ),
            const SizedBox(height: 18),
            HoppinTextField(
              label: 'Phone Number',
              controller: _phone,
              hint: '+44 123 456 7890',
              keyboardType: TextInputType.phone,
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.textTheme.bodyMedium?.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A phone number cannot be removed once saved, and one '
                    'already used on another account cannot be reused here.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (state.saveError != null) ...[
              const SizedBox(height: 16),
              Text(
                state.saveError!.message,
                style: const TextStyle(color: AppColors.negative),
              ),
            ],
            const SizedBox(height: 28),
            HoppinButton(
              label: 'Save',
              isLoading: state.isSaving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String fullName) {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            HoppinButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
