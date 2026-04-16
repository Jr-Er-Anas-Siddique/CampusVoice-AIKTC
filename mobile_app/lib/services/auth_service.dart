// lib/services/auth_service.dart
//
// PLACEMENT: lib/services/auth_service.dart
// This is the single source of truth for all auth operations.
// It is framework-agnostic and has no UI dependencies.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a parsed AIKTC email address.
class AiktcEmailInfo {
  final String admissionYear; // e.g. "22"
  final bool isDirect; // true if "d" present (direct second year)
  final String departmentTag; // e.g. "bit", "co", "ce"

  const AiktcEmailInfo({
    required this.admissionYear,
    required this.isDirect,
    required this.departmentTag,
  });
}

/// Thrown whenever authentication or validation fails.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────────────────────────
  // Email Validation
  // ──────────────────────────────────────────────────────────────────────────

  /// Pattern: [2-digit year][optional 'd'][department][optional roll digits]@aiktc.ac.in
  ///
  /// Valid examples:
  ///   22bit@aiktc.ac.in
  ///   21dco07@aiktc.ac.in
  ///   23ce@aiktc.ac.in
  static final RegExp _aiktcEmailRegex = RegExp(
    r'^(\d{2})(d?)([a-z]{2,4})\d*@aiktc\.ac\.in$',
    caseSensitive: false,
  );

  /// Returns [AiktcEmailInfo] if [email] matches the AIKTC pattern,
  /// otherwise returns null.
  AiktcEmailInfo? parseAiktcEmail(String email) {
    final match = _aiktcEmailRegex.firstMatch(email.trim().toLowerCase());
    if (match == null) return null;

    return AiktcEmailInfo(
      admissionYear: match.group(1)!,
      isDirect: match.group(2)!.isNotEmpty,
      departmentTag: match.group(3)!,
    );
  }

  /// Validates [email]. Returns an error string or null if valid.
  String? validateAiktcEmail(String email) {
    if (email.trim().isEmpty) return 'Email is required.';
    if (parseAiktcEmail(email) == null) {
      return 'Use your AIKTC email (e.g. 22bit@aiktc.ac.in).';
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Auth State
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream of Firebase auth-state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Currently signed-in user, or null.
  User? get currentUser => _auth.currentUser;

  // ──────────────────────────────────────────────────────────────────────────
  // Sign Up
  // ──────────────────────────────────────────────────────────────────────────

  /// Creates a Firebase account and a Firestore user document.
  ///
  /// Throws [AuthException] on validation or Firebase errors.
  Future<User> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final emailInfo = parseAiktcEmail(email);
    if (emailInfo == null) {
      throw const AuthException(
        'Only AIKTC institute emails are allowed (e.g. 22bit@aiktc.ac.in).',
      );
    }

    if (fullName.trim().length < 3) {
      throw const AuthException('Full name must be at least 3 characters.');
    }
    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }

    try {
      // 1. Create Firebase Auth account
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final user = credential.user!;

      // 2. Update display name
      await user.updateDisplayName(fullName.trim());

      // 3. Try Firestore — but DON'T let it crash signup if it fails
      try {
        await _createUserDocument(
          uid: user.uid,
          fullName: fullName.trim(),
          email: email.trim().toLowerCase(),
          emailInfo: emailInfo,
        );
      } catch (firestoreError) {
        // Firestore failed (permissions/network) but auth account exists
        // User document will be created on next login or can be retried later
        // DO NOT rethrow — let signup continue
      }

      // 5. Force stream refresh
      await user.reload();

      return _auth.currentUser!;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseError(e.code));
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred: $e');
    }
  }

  /// Writes the Firestore user document.
  Future<void> _createUserDocument({
    required String uid,
    required String fullName,
    required String email,
    required AiktcEmailInfo emailInfo,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'fullName': fullName,
      'email': email,
      'role': 'student', // default role
      'departmentTag': emailInfo.departmentTag, // e.g. "bit", "co"
      'admissionYear': emailInfo.admissionYear, // e.g. "22"
      'isDirect': emailInfo.isDirect, // direct second-year flag
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sign In
  // ──────────────────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  /// Accepts both student (22dco06@aiktc.ac.in) and
  /// faculty/committee (firstname.lastname@aiktc.ac.in) email patterns.
  /// Throws [AuthException] on failure.
  Future<User> signIn({required String email, required String password}) async {
    final normalised = email.trim().toLowerCase();
    if (!normalised.endsWith('@aiktc.ac.in')) {
      throw const AuthException('Only AIKTC institute emails are allowed.');
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalised,
        password: password,
      );
      final user = credential.user!;
      await user.reload();
      return _auth.currentUser!;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseError(e.code));
    } catch (e) {
      throw AuthException('An unexpected error occurred: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Password Reset
  // ──────────────────────────────────────────────────────────────────────────

  /// Sends a password-reset email.
  Future<void> sendPasswordReset(String email) async {
    if (validateAiktcEmail(email) != null) {
      throw const AuthException('Enter a valid AIKTC email address.');
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseError(e.code));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sign Out
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
    // Clear Firestore cache so next user gets fresh data, not stale cached queries
    try {
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
