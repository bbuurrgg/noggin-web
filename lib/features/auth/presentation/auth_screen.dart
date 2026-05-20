import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/friendly_error_message.dart';
import '../data/auth_providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _passwordVisible = false;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final identity = _emailController.text.trim();
    final password = _passwordController.text;
    if (identity.isEmpty || password.isEmpty || _submitting) {
      return;
    }
    if (_isSignUp && !_isValidUsername(username)) {
      _showMessage(
        'Choose a username with 3-24 letters, numbers, or underscores.',
        isError: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final auth = client.auth;
      if (_isSignUp) {
        await auth.signUp(
          email: identity,
          password: password,
          data: {'username': username.toLowerCase(), 'display_name': username},
        );
      } else {
        final email = await _emailForSignInIdentity(client, identity);
        if (email == null || email.isEmpty) {
          _showMessage('Invalid username/email or password.', isError: true);
          return;
        }
        await auth.signInWithPassword(email: email, password: password);
      }

      if (!mounted) {
        return;
      }

      if (_isSignUp && auth.currentUser == null) {
        _showMessage('Check your email to confirm your account.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        _isSignUp
            ? friendlyErrorMessage(error)
            : 'Invalid username/email or password.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<String?> _emailForSignInIdentity(
    SupabaseClient client,
    String identity,
  ) async {
    if (identity.contains('@')) {
      return identity;
    }

    final email = await client.rpc<dynamic>(
      'login_email_for_username',
      params: {'target_username': identity},
    );
    return email as String?;
  }

  bool _isValidUsername(String username) {
    return RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(username);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('images/logo_256.png', width: 128, height: 128),
                  const SizedBox(height: 16),
                  Text(
                    _isSignUp
                        ? 'Create your account to start syncing boards.'
                        : 'Sign in to your workspace.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  if (_isSignUp) ...[
                    TextField(
                      controller: _usernameController,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: 'Username',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType:
                        _isSignUp
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                    textInputAction: TextInputAction.next,
                    autofillHints:
                        _isSignUp
                            ? const [AutofillHints.email]
                            : const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                    decoration: InputDecoration(
                      labelText: _isSignUp ? 'Email' : 'Email or username',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip:
                            _passwordVisible
                                ? 'Hide password'
                                : 'Show password',
                        icon: Icon(
                          _passwordVisible
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        onPressed:
                            () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                      ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child:
                          _submitting
                              ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Text(_isSignUp ? 'Create Account' : 'Sign In'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed:
                        _submitting
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'Need an account? Create one',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
