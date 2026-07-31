import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'personal_facts.dart';

/// ACCT-02 - Personal Information (seam 70 / SL-5) - now EDITABLE.
///
/// GET /me/profile loads the canonical name + phone (email read-only); the rider
/// edits name and phone and Saves, which PATCHes public.users AND mirrors the
/// name into Supabase user_metadata (so the session greeting refreshes). Phone is
/// globally unique - a duplicate returns PHONE_TAKEN, shown inline.
class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _email = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final facts = ref.read(personalFactsProvider);
    _name.text = facts.fullName?.trim() ?? '';
    _phone.text = facts.phone?.trim() ?? '';
    _email = facts.email?.trim() ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(profileRepositoryProvider).getProfile();
      if (!mounted) return;
      _name.text = p.fullName;
      _phone.text = p.phone;
      if (p.email.isNotEmpty) _email = p.email;
    } catch (_) {
      // keep the session-seeded values
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final name = _name.text.trim();
      final phone = _phone.text.trim();
      await ref.read(profileRepositoryProvider).updateProfile(
            fullName: name,
            phoneNumber: phone.isEmpty ? null : phone,
          );
      try {
        await ref.read(authServiceProvider).updateFullName(name);
      } catch (_) {/* metadata mirror is non-fatal */}
      if (mounted) setState(() => _notice = 'Saved.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'PHONE_TAKEN'
            ? 'That phone number is already in use.'
            : 'Could not save. Check your details and try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final memberSince =
        _formatMemberSince(ref.watch(personalFactsProvider).memberSince);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HopTopBar(
            title: 'Personal Information',
            onBack: () =>
                context.canPop() ? context.pop() : context.go('/profile'),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: hoppin.spacing.gutter,
                        vertical: hoppin.spacing.lg,
                      ),
                      children: [
                        if (_error != null) ...[
                          HopBanner.error(message: _error!),
                          SizedBox(height: hoppin.spacing.md),
                        ],
                        if (_notice != null) ...[
                          HopBanner.notice(message: _notice!),
                          SizedBox(height: hoppin.spacing.md),
                        ],
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        SizedBox(height: hoppin.spacing.md),
                        TextFormField(
                          controller: _phone,
                          enabled: !_busy,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            return t.length < 7
                                ? 'Enter a valid phone number'
                                : null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Contact number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        if (_email.isNotEmpty) ...[
                          SizedBox(height: hoppin.spacing.lg),
                          _readOnly(context, 'Email', _email),
                        ],
                        if (memberSince != null) ...[
                          SizedBox(height: hoppin.spacing.md),
                          _readOnly(context, 'Member Since', memberSince),
                        ],
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              hoppin.spacing.gutter,
              hoppin.spacing.sm,
              hoppin.spacing.gutter,
              hoppin.spacing.lg,
            ),
            child: HopButton.primary(
              key: const Key('personal.save'),
              label: 'Save Changes',
              onPressed: (_busy || _loading) ? null : _save,
              busy: _busy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnly(BuildContext context, String label, String value) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: hoppin.type.meta.copyWith(color: colors.textMid)),
        SizedBox(height: hoppin.spacing.xs),
        Text(value, style: hoppin.type.bodyLarge),
      ],
    );
  }
}

const _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Renders the account-creation timestamp as "August 2025", or null when
/// missing/unparseable.
String? _formatMemberSince(String? iso) {
  final raw = iso?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return '${_months[parsed.month - 1]} ${parsed.year}';
}
