// lib/services/committee_auth_service.dart
//
// Handles committee member role detection.
// On login, checks if the email exists in Firestore committee_members collection.
// If found → committee role with their committee type.
// If not found and not student pattern → blocked.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/committee_member_model.dart';

enum UserRole { student, committee, blocked }

class UserRoleResult {
  final UserRole role;
  final CommitteeMember? member; // non-null if role == committee

  const UserRoleResult.student()
      : role = UserRole.student,
        member = null;

  const UserRoleResult.blocked()
      : role = UserRole.blocked,
        member = null;

  const UserRoleResult({required this.role, this.member});
}

class CommitteeAuthService {
  CommitteeAuthService._();
  static final CommitteeAuthService instance = CommitteeAuthService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Faculty email pattern: firstname.lastname@aiktc.ac.in
  // Also handles shared accounts: ipdc@aiktc.ac.in etc.
  static final RegExp _facultyEmailRegex = RegExp(
    r'^[a-z][a-z0-9._-]+@aiktc\.ac\.in$',
    caseSensitive: false,
  );

  // Student email pattern: 22dco06@aiktc.ac.in
  static final RegExp _studentEmailRegex = RegExp(
    r'^\d{2}d?[a-z]{2,4}\d*@aiktc\.ac\.in$',
    caseSensitive: false,
  );

  bool isStudentEmail(String email) =>
      _studentEmailRegex.hasMatch(email.trim().toLowerCase());

  bool isFacultyEmail(String email) =>
      _facultyEmailRegex.hasMatch(email.trim().toLowerCase());

  /// Determines the role of the logged-in user.
  /// Call this after Firebase Auth sign-in succeeds.
  Future<UserRoleResult> resolveRole(String email) async {
    final normalised = email.trim().toLowerCase();

    // 1. Student pattern → student role immediately, no Firestore needed
    if (isStudentEmail(normalised)) {
      return const UserRoleResult.student();
    }

    // 2. Faculty/committee pattern → check whitelist in Firestore
    if (isFacultyEmail(normalised)) {
      final doc = await _db
          .collection('committee_members')
          .doc(normalised)
          .get();

      if (doc.exists && doc.data() != null) {
        final member = CommitteeMember.fromFirestore(doc.data()!);
        return UserRoleResult(role: UserRole.committee, member: member);
      }

      // Faculty email but not in whitelist → blocked
      return const UserRoleResult.blocked();
    }

    // 3. Neither pattern → blocked
    return const UserRoleResult.blocked();
  }

  /// Fetches committee member details for currently logged-in user.
  Future<CommitteeMember?> getCurrentMember(String email) async {
    try {
      final doc = await _db
          .collection('committee_members')
          .doc(email.trim().toLowerCase())
          .get();
      if (doc.exists && doc.data() != null) {
        return CommitteeMember.fromFirestore(doc.data()!);
      }
    } catch (_) {}
    return null;
  }
}
