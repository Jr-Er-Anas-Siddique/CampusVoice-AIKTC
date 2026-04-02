// lib/features/auth/presentation/pages/login_page.dart
//
// PLACEMENT: lib/features/auth/presentation/pages/login_page.dart

import 'package:flutter/material.dart';
import 'package:mobile_app/features/feed/presentation/pages/feed_page.dart';
import '../../../../services/auth_service.dart';
import 'signup_page.dart';
// import 'verify_email_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isResettingPassword = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Manual navigation fallback — don't rely solely on stream
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const FeedPage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();

    if (!email.toLowerCase().endsWith('@aiktc.ac.in')) {
      setState(() {
        _errorMessage = 'Enter your AIKTC email above first.';
      });
      return;
    }

    setState(() {
      _isResettingPassword = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await AuthService.instance.sendPasswordReset(email);
      setState(() {
        _successMessage = 'Password reset email sent to $email';
      });
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isResettingPassword = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme),
              const SizedBox(height: 36),
              _buildForm(theme),
              const SizedBox(height: 24),
              _buildSignupLink(theme),
            ],
          ),
        ),
      ),
      ), // closes GestureDetector
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo block
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF283593)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CampusVoice',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A237E),
                  ),
                ),
                Text(
                  'AIKTC',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Welcome back 👋',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in with your institute email',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error banner
            if (_errorMessage != null) ...[
              _StatusBanner(message: _errorMessage!, isError: true),
              const SizedBox(height: 16),
            ],

            // Success banner
            if (_successMessage != null) ...[
              _StatusBanner(message: _successMessage!, isError: false),
              const SizedBox(height: 16),
            ],

            // Email
            _FormLabel(label: 'Institute Email'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(
                hint: 'e.g. 22bit@aiktc.ac.in',
                icon: Icons.alternate_email_rounded,
              ),
              validator: (v) {
                final email = (v ?? '').trim().toLowerCase();
                if (email.isEmpty) return 'Email is required.';
                if (!email.endsWith('@aiktc.ac.in')) {
                  return 'Use your AIKTC email (e.g. 22bit@aiktc.ac.in).';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            _FormLabel(label: 'Password'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _inputDecoration(
                hint: 'Your password',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required.';
                return null;
              },
            ),
            const SizedBox(height: 8),

            // Forgot password
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isResettingPassword ? null : _handleForgotPassword,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _isResettingPassword
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Forgot password?',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1A237E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 28),

            // Login button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupLink(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?  ",
          style: TextStyle(color: Colors.grey.shade600),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SignupPage()),
          ),
          child: const Text(
            'Sign up',
            style: TextStyle(
              color: Color(0xFF1A237E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F9FF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1A237E), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String label;
  const _FormLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF37474F),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  const _StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red : Colors.green;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
