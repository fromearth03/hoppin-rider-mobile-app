import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Rider sign-in / sign-up.
///
/// Riders self-sign-up (role defaults to `rider`; DB triggers provision the
/// users row + rider_profile — docs/04 · Authentication). On success the
/// router's refreshListenable sees the Supabase auth event and redirects home —
/// this screen never navigates manually.
// Demo-only auto-fill. This block renders and fills only when DEMO_MODE is
// explicitly enabled at build time. Production builds must never pass
// --dart-define=DEMO_MODE=true, so the button and baked credentials are absent.
const _demoModeEnabled = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
const _demoRiderEmail = String.fromEnvironment('DEMO_RIDER_EMAIL', defaultValue: '');
const _demoRiderPassword = String.fromEnvironment('DEMO_RIDER_PASSWORD', defaultValue: '');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _submitted = false;
  bool _prefilled = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final prefill = ref.read(loginPrefillProvider);
    if (prefill != null) {
      _emailCtrl.text = prefill.email;
      _passwordCtrl.text = prefill.password;
      _prefilled = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
      _notice = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    try {
      if (_signUp) {
        final name = _nameCtrl.text.trim();
        final res = await auth.signUpRider(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          fullName: name.isEmpty ? null : name,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        );
        // With email confirmation enabled there is no session yet — the user
        // must confirm before signing in. With it disabled a session exists
        // and the router redirect takes over.
        if (res.session == null && mounted) {
          setState(
            () => _notice = 'Account created — confirm your email, then sign in.',
          );
        }
      } else {
        await auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
        // Role gate — this is the RIDER app. A driver or admin account must NOT
        // get in: it is the wrong app and its token is not a rider. Sign it
        // straight back out with a clear message instead of exposing rider
        // features to it.
        final role = auth.role;
        if (role == AppRole.driver || role == AppRole.admin) {
          await auth.signOut();
          if (mounted) {
            setState(() => _error = role == AppRole.driver
                ? 'This is a driver account — please use the Hoppin Driver app.'
                : 'Admin accounts cannot sign in to the rider app.');
          }
          return;
        }
        // Router redirect handles navigation via onAuthStateChange.
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    final email = _emailCtrl.text.trim();
    if (validateEmail(email) != null) {
      setState(
        () => _error =
            'Enter your email above first, then tap "Forgot password".',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // NOTE: completing the reset opens a link — the in-app deep-link handler
      // arrives with platform config (M1.5). Until then the link lands on the
      // Supabase project's configured site URL.
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        setState(() => _notice = 'Password reset email sent to $email.');
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _signUp = !_signUp;
      _error = null;
      _notice = null;
      _submitted = false;
    });
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
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The wordmark: Geist display, tight-tracked, racing
                      // green — the first branded surface of the demo.
                      Text(
                        'Hoppin',
                        textAlign: TextAlign.center,
                        style: type.display.copyWith(color: colors.accent),
                      ),
                      SizedBox(height: hoppin.spacing.sm),
                      Text(
                        _signUp
                            ? 'Create your account'
                            : 'Sign in to book a ride',
                        textAlign: TextAlign.center,
                        style: type.body.copyWith(color: colors.textMid),
                      ),
                      SizedBox(height: hoppin.spacing.xl),
                      if (_error != null) ...[
                        HopBanner.error(message: _error!),
                        SizedBox(height: hoppin.spacing.md),
                      ],
                      if (_notice != null) ...[
                        HopBanner.notice(message: _notice!),
                        SizedBox(height: hoppin.spacing.md),
                      ],
                      if (_signUp) ...[
                        TextFormField(
                          controller: _nameCtrl,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full name (optional)',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneCtrl,
                          enabled: !_busy,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().length < 7)
                              ? 'Enter your phone number'
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        enabled: !_busy,
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        validator: (v) =>
                            validatePassword(v, forSignUp: _signUp),
                        obscureText: _obscurePassword,
                        autofillHints: _signUp
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _signUp ? 'At least 8 characters' : null,
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
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                          ),
                        ),
                      ),
                      SizedBox(height: hoppin.spacing.gutter),
                      HopButton.primary(
                        label: _signUp ? 'Create account' : 'Sign in',
                        onPressed: _busy ? null : _submit,
                        busy: _busy,
                      ),
                      if (_demoModeEnabled &&
                          _demoRiderEmail.isNotEmpty &&
                          !_signUp) ...[
                        SizedBox(height: hoppin.spacing.sm),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _emailCtrl.text = _demoRiderEmail;
                                  _passwordCtrl.text = _demoRiderPassword;
                                  setState(() {});
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: colors.textMid,
                            textStyle: hoppin.type.labelSmall,
                          ),
                          child: const Text('Auto-fill (demo)'),
                        ),
                      ],
                      if (_prefilled && !_signUp) ...[
                        SizedBox(height: hoppin.spacing.sm),
                        // Demo seam (DEMO-05): quiet, never a banner.
                        Text(
                          'Demo credentials are ready — just tap Sign in.',
                          textAlign: TextAlign.center,
                          style:
                              type.bodySmall.copyWith(color: colors.textMid),
                        ),
                      ],
                      SizedBox(height: hoppin.spacing.sm),
                      TextButton(
                        onPressed: _busy ? null : _toggleMode,
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: Text(
                          _signUp
                              ? 'Already have an account? Sign in'
                              : 'New to Hoppin? Create an account',
                        ),
                      ),
                      if (!_signUp)
                        TextButton(
                          onPressed: _busy ? null : _forgotPassword,
                          style: TextButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          child: const Text('Forgot password?'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
