// lib/features/auth/presentation/pages/signup_page.dart

import 'package:flutter/material.dart';
// import 'package:mobile_app/features/auth/presentation/pages/verify_email_page.dart';
import '../../../../services/auth_service.dart';
import 'login_page.dart';
import '../../../../main.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  String? _emailPreview;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onEmailChanged(String value) {
    final info = AuthService.instance.parseAiktcEmail(value);
    setState(() {
      _emailPreview = info == null
          ? null
          : '${info.departmentTag.toUpperCase()} • 20${info.admissionYear}${info.isDirect ? " (Direct)" : ""}';
    });
  }

  Future<void> _handleSignup() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signUp(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      // ✅ No dialog, no Navigator.push needed.
      // AuthGate is watching authStateChanges stream.
      // After signUp(), Firebase creates the user → stream fires →
      // AuthGate sees user.emailVerified = false → shows VerifyEmailPage.
      // Everything is automatic.

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme),
              const SizedBox(height: 32),
              _buildForm(theme),
              const SizedBox(height: 24),
              _buildLoginLink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF283593)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          'Create Account',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A237E),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'CampusVoice AIKTC — Student Portal',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: Colors.grey.shade600),
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
            color: Colors.indigo.withOpacity(0.08),
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
            if (_errorMessage != null) ...[
              _ErrorBanner(message: _errorMessage!),
              const SizedBox(height: 16),
            ],

            // Full Name
            _FormLabel(label: 'Full Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration(
                  hint: 'e.g. Aisha Khan',
                  icon: Icons.person_outline_rounded),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Enter your full name (min 3 characters).'
                  : null,
            ),
            const SizedBox(height: 16),

            // Email
            _FormLabel(label: 'Institute Email'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: _onEmailChanged,
              decoration: _inputDecoration(
                hint: 'e.g. 22bit@aiktc.ac.in',
                icon: Icons.alternate_email_rounded,
                suffix: _emailPreview != null
                    ? _DeptChip(label: _emailPreview!)
                    : null,
              ),
              validator: (v) =>
                  AuthService.instance.validateAiktcEmail(v ?? ''),
            ),
            const SizedBox(height: 4),
            Text(
              'Format: [year][dept]@aiktc.ac.in',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),

            // Password
            _FormLabel(label: 'Password'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: _inputDecoration(
                hint: 'Min 6 characters',
                icon: Icons.lock_outline_rounded,
                suffix: _ToggleVisibilityButton(
                  obscure: _obscurePassword,
                  onToggle: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? 'Password must be at least 6 characters.'
                  : null,
            ),
            const SizedBox(height: 16),

            // Confirm Password
            _FormLabel(label: 'Confirm Password'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: _inputDecoration(
                hint: 'Re-enter password',
                icon: Icons.lock_outline_rounded,
                suffix: _ToggleVisibilityButton(
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) => (v != _passwordController.text)
                  ? 'Passwords do not match.'
                  : null,
            ),
            const SizedBox(height: 28),

            // Submit
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Create Account',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account?  ',
            style: TextStyle(color: Colors.grey.shade600)),
        GestureDetector(
          onTap: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginPage())),
          child: const Text('Log in',
              style: TextStyle(
                  color: Color(0xFF1A237E), fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(
      {required String hint, required IconData icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade500),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8F9FF),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1A237E), width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String label;
  const _FormLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF37474F)));
}

class _DeptChip extends StatelessWidget {
  final String label;
  const _DeptChip({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Chip(
          label: Text(label, style: const TextStyle(fontSize: 10)),
          backgroundColor: const Color(0xFFE8EAF6),
          labelPadding: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        ),
      );
}

class _ToggleVisibilityButton extends StatelessWidget {
  final bool obscure;
  final VoidCallback onToggle;
  const _ToggleVisibilityButton(
      {required this.obscure, required this.onToggle});
  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: Colors.grey.shade500),
        onPressed: onToggle,
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message,
                    style: TextStyle(
                        color: Colors.red.shade700, fontSize: 13))),
          ],
        ),
      );
}
