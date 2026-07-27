import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../legal/consent_notice.dart';
import '../legal/marketing_consent_toggle.dart';
import 'signup_eligibility_notice.dart';
import 'verify_banner.dart';

/// Rider registration (AUTH-01, Figma "Sign Up #3").
///
/// Collects name + email + password + date-of-birth + an explicit 18+
/// declaration. The 18+ box gates submit: no service call fires until it is
/// checked. On success the soft [VerifyBanner] nag begins (the hard verify wall
/// at Book lands in 09-05).
///
/// ## Seam note for 09-05
/// The 18+ flag and DOB are cached CLIENT-SIDE only ([SignupEligibility]).
/// There is no rider-profile PATCH to persist them yet — this is the SL-5
/// MISSING-BE seam (ties to gap #55, signup-eligibility-guard). 09-05 must
/// register it in `kSeamRegistry` and relay SL-5. Do NOT let the collected
/// eligibility silently drop.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

/// The client-side eligibility holder — the SL-5 seam's in-memory home until a
/// rider-profile PATCH exists to persist it (relayed in 09-05).
class SignupEligibility {
  const SignupEligibility({required this.over18, required this.dateOfBirth});

  final bool over18;
  final DateTime? dateOfBirth;
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _over18 = false;
  DateTime? _dob;

  /// The SL-5 / #55 seam's REAL degrade branch.
  ///
  /// Non-null once the rider has made the 18+ declaration — the eligibility is
  /// captured into this client-side holder and it goes NOWHERE ELSE: there is
  /// no rider-profile PATCH to persist it (MISSING-BE, gap #55). It used to be
  /// constructed into `final _ =` and thrown away, so the rider was never told
  /// their declaration lives only on this device. [SignupEligibilityNotice] is
  /// mounted on exactly this non-null branch, which is the honest disclosure.
  /// No persistence is invented here and no server write is faked — the
  /// declaration's on-device home IS the truth we now say out loud.
  SignupEligibility? _eligibility;

  bool _busy = false;
  bool _submitted = false;
  bool _obscurePassword = true;
  bool _created = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = clock.now();
    final initial = _dob ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _captureEligibility();
      });
    }
  }

  /// Captures the 18+ declaration + DOB into the client-side holder. Held
  /// on-device ONLY — no PATCH exists (#55). Cleared when the rider un-checks,
  /// so the disclosure never outlives the declaration it discloses.
  void _captureEligibility() {
    _eligibility = _over18
        ? SignupEligibility(over18: _over18, dateOfBirth: _dob)
        : null;
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    // The 18+ declaration gates the whole submit — nothing fires unchecked.
    if (!_over18) return;
    if (!_formKey.currentState!.validate()) return;

    // SL-5 seam: eligibility captured client-side and DISCLOSED as such (the
    // SignupEligibilityNotice below _Over18Check). It is not sent anywhere —
    // no rider-profile PATCH exists (#55). The booking eligibility guard on
    // the server stays the enforcement authority.
    _captureEligibility();

    setState(() => _busy = true);
    try {
      final name = _nameCtrl.text.trim();
      await ref.read(authServiceProvider).signUpRider(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: name.isEmpty ? null : name,
          );
      if (mounted) setState(() => _created = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: hoppin.spacing.gutter,
              vertical: hoppin.spacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: _submitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Create your account',
                      textAlign: TextAlign.center,
                      style: type.display.copyWith(color: colors.accent),
                    ),
                    SizedBox(height: hoppin.spacing.sm),
                    Text(
                      'Register to book your first ride',
                      textAlign: TextAlign.center,
                      style: type.body.copyWith(color: colors.textMid),
                    ),
                    SizedBox(height: hoppin.spacing.xl),
                    if (_created) ...[
                      const VerifyBanner(),
                      SizedBox(height: hoppin.spacing.md),
                    ],
                    if (_error != null) ...[
                      HopBanner.error(message: _error!),
                      SizedBox(height: hoppin.spacing.md),
                    ],
                    TextFormField(
                      key: const Key('signup_name'),
                      controller: _nameCtrl,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                    ),
                    SizedBox(height: hoppin.spacing.lg),
                    TextFormField(
                      key: const Key('signup_email'),
                      controller: _emailCtrl,
                      enabled: !_busy,
                      validator: validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    SizedBox(height: hoppin.spacing.lg),
                    TextFormField(
                      key: const Key('signup_password'),
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      validator: (v) => validatePassword(v, forSignUp: true),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip:
                              _obscurePassword ? 'Show password' : 'Hide password',
                        ),
                      ),
                    ),
                    SizedBox(height: hoppin.spacing.lg),
                    _DobField(
                      dob: _dob,
                      enabled: !_busy,
                      onTap: _pickDob,
                    ),
                    SizedBox(height: hoppin.spacing.md),
                    _Over18Check(
                      value: _over18,
                      enabled: !_busy,
                      showError: _submitted && !_over18,
                      onChanged: (v) => setState(() {
                        _over18 = v ?? false;
                        _captureEligibility();
                      }),
                    ),
                    // SL-5 / #55 — the declaration has been made, and there is
                    // nowhere on the server to put it. The designed notice is
                    // mounted on that real branch (a captured, unpersistable
                    // eligibility), so the rider is told their age confirmation
                    // is held on this device. The 18+ box still gates submit
                    // exactly as before; this only makes the truth reachable.
                    if (_eligibility != null) ...[
                      SizedBox(height: hoppin.spacing.sm),
                      const SignupEligibilityNotice(),
                    ],
                    // ── COMPLY-01 consent block (Phase 12) ───────────────────
                    // Transparency (Arts. 13/14) is what MAKES the contract
                    // basis lawful, so the notice belongs HERE — at the point of
                    // collection, before the account exists. Its privacy link
                    // resolves pre-login (the router allowlists `/legal/*`).
                    //
                    // 🔴 NEITHER OF THESE GATES SUBMIT. The 18+ box above gates,
                    // and it stays the ONLY gate. A signup you cannot complete
                    // without a marketing opt-in makes that consent a condition
                    // of service — not freely given, therefore INVALID (ICO) —
                    // and it is the wrong lawful basis for the ride anyway.
                    // `_submit()` must never learn this toggle exists.
                    SizedBox(height: hoppin.spacing.lg),
                    const ConsentNotice(),
                    SizedBox(height: hoppin.spacing.lg),
                    const MarketingConsentToggle(),
                    // ─────────────────────────────────────────────────────────
                    SizedBox(height: hoppin.spacing.gutter),
                    HopButton.primary(
                      key: const Key('signup_submit'),
                      label: 'Create account',
                      onPressed: _busy ? null : _submit,
                      busy: _busy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The date-of-birth field — a tappable, read-only surface that opens the OS
/// date picker. Framed as a form field so its label matches the kit.
class _DobField extends StatelessWidget {
  const _DobField({required this.dob, required this.enabled, required this.onTap});

  final DateTime? dob;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = dob == null
        ? null
        : '${dob!.day.toString().padLeft(2, '0')}/'
            '${dob!.month.toString().padLeft(2, '0')}/${dob!.year}';
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date of birth',
          prefixIcon: Icon(Icons.cake_outlined),
        ),
        child: Text(
          label ?? 'Tap to select',
          style: context.hoppin.type.body.copyWith(
            color: label == null
                ? context.hoppin.colors.textMid
                : context.hoppin.colors.textHi,
          ),
        ),
      ),
    );
  }
}

/// The 18+ declaration — the eligibility gate on submit.
class _Over18Check extends StatelessWidget {
  const _Over18Check({
    required this.value,
    required this.enabled,
    required this.showError,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final bool showError;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: hoppin.spacing.md),
                child: Text(
                  'I confirm I am 18 or over',
                  style: hoppin.type.body.copyWith(color: colors.textHi),
                ),
              ),
            ),
          ],
        ),
        if (showError)
          Padding(
            padding: EdgeInsets.only(left: hoppin.spacing.md),
            child: Text(
              'You must confirm you are 18 or over to register',
              style: hoppin.type.bodySmall.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}
