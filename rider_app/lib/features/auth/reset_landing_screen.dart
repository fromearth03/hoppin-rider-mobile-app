import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The password-reset deep-link landing (AUTH-04).
///
/// The rider arrives here from the emailed reset link (Supabase redirect URL
/// `/reset`), which the SDK turns into a temporary RECOVERY session. This screen
/// collects a new password and writes it onto that session via
/// [AuthService.updatePassword], then drops the rider into the app. When there
/// is no recovery session (link expired or opened directly), the update fails
/// and we show an honest "request a new link" message instead of a dead form.
class ResetLandingScreen extends ConsumerStatefulWidget {
  const ResetLandingScreen({this.onBackToSignIn, super.key});

  /// "Back to sign in" action (wired to the router).
  final VoidCallback? onBackToSignIn;

  @override
  ConsumerState<ResetLandingScreen> createState() =>
      _ResetLandingScreenState();
}

class _ResetLandingScreenState extends ConsumerState<ResetLandingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authServiceProvider);
      await hoppinEstablishResetSession(alreadySignedIn: auth.isSignedIn);
      await auth.updatePassword(_passwordCtrl.text);
      if (!mounted) return;
      // The recovery session is now a full session — drop them into the app.
      context.go('/book');
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _error =
            'This reset link has expired or is invalid. Request a new one '
            'from the sign-in screen.');
      }
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
      backgroundColor: colors.canvas,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Set a new password',
                        textAlign: TextAlign.center, style: type.headline),
                    SizedBox(height: hoppin.spacing.sm),
                    Text('Choose a new password for your Hoppin account.',
                        textAlign: TextAlign.center,
                        style: type.body.copyWith(color: colors.textMid)),
                    SizedBox(height: hoppin.spacing.xl),
                    if (_error != null) ...[
                      HopBanner.error(message: _error!),
                      SizedBox(height: hoppin.spacing.md),
                    ],
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !_busy,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.length < 8) ? 'At least 8 characters' : null,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmCtrl,
                      enabled: !_busy,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) =>
                          (v != _passwordCtrl.text) ? 'Passwords do not match' : null,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscureConfirm
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    SizedBox(height: hoppin.spacing.gutter),
                    HopButton.primary(
                      label: 'Set new password',
                      onPressed: _busy ? null : _submit,
                      busy: _busy,
                    ),
                    if (widget.onBackToSignIn != null) ...[
                      SizedBox(height: hoppin.spacing.sm),
                      TextButton(
                        onPressed: _busy ? null : widget.onBackToSignIn,
                        child: const Text('Back to sign in'),
                      ),
                    ],
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
