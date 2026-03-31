// lib/features/auth/presentation/pages/verify_email_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_app/features/feed/presentation/pages/feed_page.dart';
import '../../../../services/auth_service.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  Timer? _timer;
  bool _isResending = false;
  bool _resendSuccess = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  /// Every 3 seconds, ask Firebase to reload the user's data from the server.
  /// Once emailVerified becomes true, AuthGate stream fires and routes to HomePage.
  // REPLACE with:
void _startPolling() {
  _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      
      // Check AFTER reload — don't rely only on stream
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified && mounted) {
        _timer?.cancel();
        // Navigate directly — don't wait for stream
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const FeedPage()),
          (route) => false,
        );
      }
    } catch (_) {
      // Silently ignore reload errors
    }
  });
}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isResending = true;
      _resendSuccess = false;
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() => _resendSuccess = true);
    } catch (_) {
      // Ignore — too-many-requests handled silently
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EAF6),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  size: 64,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                'Check your inbox',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'We sent a verification link to:',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 16),

              // Auto-redirect notice
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.green.shade600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for verification...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This page will redirect automatically\nonce you click the link.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 36),

              // Resend success banner
              if (_resendSuccess) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Verification email resent!',
                        style: TextStyle(
                            color: Colors.blue.shade700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Resend button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isResending ? null : _resendEmail,
                  icon: _isResending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Resend verification email'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A237E),
                    side: const BorderSide(color: Color(0xFF1A237E)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Sign out
              TextButton(
                onPressed: () => AuthService.instance.signOut(),
                child: Text(
                  'Use a different account',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
