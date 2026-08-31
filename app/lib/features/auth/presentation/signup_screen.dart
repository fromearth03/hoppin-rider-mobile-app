import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/hoppin_text_field.dart';
import '../application/auth_controller.dart';
import '../domain/auth_state.dart';
import '../domain/dob_validator.dart';
import 'widgets/auth_scaffold.dart';

/// Create an account.
///
/// Diverges from the design in three places: one full-name field rather than
/// first and last (the backend stores one `full_name`, and a joined name
/// cannot be reliably split back); a date picker rather than an "I am 18 or
/// older" checkbox (self-certification enforces nothing, and the real
/// threshold is 13); and a button labelled "Create account" rather than
/// "Login".
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  DateTime? _dob;
  String? _dobError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Opens on a plausible adult year rather than today, so reaching a real
      // birth date is a short scroll rather than a long one.
      initialDate: _dob ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobError = DobValidator.validate(picked);
      });
    }
  }

  void _submit() {
    final invalid = DobValidator.validate(_dob);
    if (invalid != null) {
      setState(() => _dobError = invalid);
      return;
    }
    ref.read(authControllerProvider.notifier).signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          dateOfBirth: _dob,
          phone: _phone.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final incomplete = state.status == AuthStatus.profileIncomplete;

    return AuthScaffold(
      title: 'Sign up',
      subtitle: 'Create an account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoppinTextField(label: 'Full name', controller: _name),
          const SizedBox(height: 18),
          HoppinTextField(
            label: 'Email',
            controller: _email,
            hint: 'example@gmail.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline),
          ),
          const SizedBox(height: 18),
          HoppinTextField(
            label: 'Phone number (optional)',
            controller: _phone,
            hint: '+44 123 456 7890',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 18),
          HoppinTextField(
            label: 'Password',
            controller: _password,
            obscure: true,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child:
                    Text('Date of birth', style: theme.textTheme.bodyMedium),
              ),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    errorText: _dobError,
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _dob == null ? 'Select date' : DobValidator.format(_dob!),
                    style: _dob == null
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodyLarge,
                  ),
                ),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              RiderErrorCopy.messageFor(state.error!),
              style: const TextStyle(color: AppColors.negative),
            ),
          ],
          if (incomplete) ...[
            const SizedBox(height: 12),
            Text(
              'Your account was created but we could not finish setting it '
              'up. Tap below to finish.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 24),
          HoppinButton(
            label: incomplete ? 'Finish setting up' : 'Create account',
            isLoading: state.isBusy,
            onPressed: incomplete
                ? () => ref
                    .read(authControllerProvider.notifier)
                    .completeProfile(_dob ?? DateTime(1990))
                : _submit,
          ),
        ],
      ),
    );
  }
}
