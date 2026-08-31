import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../../../shared/widgets/hoppin_button.dart';
import '../../../shared/widgets/hoppin_text_field.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_scaffold.dart';

/// Email and password only.
///
/// The design says "Email or Phone Number", but Supabase can only authenticate
/// a phone it verified by SMS and there is no SMS provider. A phone field here
/// would be a path that cannot work.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final error = state.error;
    final theme = Theme.of(context);

    return AuthScaffold(
      title: 'Login',
      subtitle: 'Welcome back',
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoppinTextField(
            label: 'Email',
            controller: _email,
            hint: 'example@gmail.com',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline),
          ),
          const SizedBox(height: 20),
          HoppinTextField(
            label: 'Password',
            controller: _password,
            obscure: _obscure,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              child: Text(_obscure ? 'Show password' : 'Hide password'),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              RiderErrorCopy.messageFor(error),
              style: const TextStyle(color: AppColors.negative),
            ),
          ],
          const SizedBox(height: 16),
          HoppinButton(
            label: 'Login',
            isLoading: state.isBusy,
            onPressed: () => ref
                .read(authControllerProvider.notifier)
                .signIn(_email.text, _password.text),
          ),
          const SizedBox(height: 8),
          // Without this the sign-up screen is unreachable: the app opens on
          // login and the redirect keeps a signed-out rider on an auth route,
          // so a new rider had nowhere to go.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Don't have an account?",
                  style: theme.textTheme.bodyMedium),
              TextButton(
                onPressed: () => context.go(AppRoutes.signup),
                child: const Text('Sign up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
