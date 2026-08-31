import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/hoppin_text_field.dart';
import 'widgets/auth_scaffold.dart';

/// Set a new password — `Reset Password.png`.
///
/// **`AuthRepository` has no method to complete a password reset.** Supabase
/// completes recovery through `GoTrueClient.updateUser` against the recovery
/// session the emailed link creates, but that call does not exist anywhere in
/// this codebase (`auth_repository.dart` only has `signIn`, `signUp`,
/// `requestPasswordReset` and `signOut`), and `data/` is out of scope for this
/// change. Rather than invent that endpoint here, [onSubmit] defaults to
/// null, and submitting with no callback supplied surfaces a plain message
/// that the reset path is not wired up yet — never a fake success. A caller
/// that does have a way to complete the reset (once the repository grows one)
/// can pass [onSubmit] and this screen will use it.
///
/// Design says the minimum is 8 characters. Supabase's own floor is 6, so
/// enforcing 8 here is stricter, not looser, than the backend — it can never
/// reject a password the server would have accepted.
class ResetPasswordScreen extends StatefulWidget {
  static const minLength = 8;

  /// Called with the new password once both fields are valid and matching.
  /// Return true on success. Null means no completion path exists yet.
  final Future<bool> Function(String password)? onSubmit;

  const ResetPasswordScreen({super.key, this.onSubmit});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    _password.addListener(_onChanged);
    _confirm.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _password.removeListener(_onChanged);
    _confirm.removeListener(_onChanged);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Null when valid, otherwise the message to show under the confirm field.
  String? get _validationError {
    if (_password.text.isEmpty || _confirm.text.isEmpty) return null;
    if (_password.text.length < ResetPasswordScreen.minLength) {
      return 'Password must be at least ${ResetPasswordScreen.minLength} '
          'characters';
    }
    if (_password.text != _confirm.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool get _canSubmit =>
      _password.text.isNotEmpty &&
      _confirm.text.isNotEmpty &&
      _password.text.length >= ResetPasswordScreen.minLength &&
      _password.text == _confirm.text;

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      setState(() => _unavailable =
          'Completing a password reset from inside the app is not yet '
          'available. Please use the link from your email on a browser, or '
          'try again shortly.');
      return;
    }

    setState(() {
      _submitting = true;
      _unavailable = null;
    });
    final ok = await onSubmit(_password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      setState(() => _unavailable = 'That did not work. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _validationError;

    return AuthScaffold(
      title: 'Reset Password',
      subtitle: 'Enter your new password (must be atleast '
          '${ResetPasswordScreen.minLength} characters)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoppinTextField(
            label: 'Set New Password',
            controller: _password,
            hint: 'Enter your New Password',
            obscurable: true,
            prefixIcon: const Icon(Icons.lock_outline),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          HoppinTextField(
            label: 'Confirm New Password',
            controller: _confirm,
            hint: 'Confirm your New Password',
            obscurable: true,
            prefixIcon: const Icon(Icons.lock_outline),
            errorText: error,
            textInputAction: TextInputAction.done,
          ),
          if (_unavailable != null) ...[
            const SizedBox(height: 12),
            Text(
              _unavailable!,
              style: const TextStyle(color: AppColors.negative),
            ),
          ],
          const SizedBox(height: 20),
          HoppinButton(
            label: 'Reset Password',
            isLoading: _submitting,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }
}
