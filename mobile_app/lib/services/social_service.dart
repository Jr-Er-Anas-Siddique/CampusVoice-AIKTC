// lib/services/social_service.dart
//
// Handles support (upvote) and comments for complaints.
// Uses Firestore transactions to keep supportCount and commentCount in sync.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment_model.dart';

class SocialService {
  SocialService._();
  static final SocialService instance = SocialService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Support / Upvote ─────────────────────────────────────────────────────

  /// Toggles support for a complaint.
  /// Returns true if user now supports, false if support was removed.
  Future<bool> toggleSupport({
    required String complaintId,
    required String userId,
  }) async {
    final supporterRef = _db
        .collection('complaints')
        .doc(complaintId)
        .collection('supporters')
        .doc(userId);

    final complaintRef = _db.collection('complaints').doc(complaintId);

    return await _db.runTransaction<bool>((transaction) async {
      final supporterSnap = await transaction.get(supporterRef);

      if (supporterSnap.exists) {
        transaction.delete(supporterRef);
        transaction.update(complaintRef, {
          'supportCount': FieldValue.increment(-1),
        });
        return false;
      } else {
        transaction.set(supporterRef, {
          'userId': userId,
          'createdAt': DateTime.now().toIso8601String(),
        });
        transaction.update(complaintRef, {
          'supportCount': FieldValue.increment(1),
        });
        return true;
      }
    });
  }

  /// Stream of whether user has supported — for real-time UI updates.
  Stream<bool> supportStream({
    required String complaintId,
    required String userId,
  }) {
    return _db
        .collection('complaints')
        .doc(complaintId)
        .collection('supporters')
        .doc(userId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  // ── Comments ─────────────────────────────────────────────────────────────

  /// Adds a comment and increments commentCount atomically.
  Future<void> addComment({
    required String complaintId,
    required String userId,
    required String userName,
    required String text,
  }) async {
    final commentRef = _db
        .collection('complaints')
        .doc(complaintId)
        .collection('comments')
        .doc();

    final complaintRef = _db.collection('complaints').doc(complaintId);

    final comment = CommentModel(
      id: commentRef.id,
      userId: userId,
      userName: userName,
      text: text.trim(),
      createdAt: DateTime.now(),
    );

    await _db.runTransaction((transaction) async {
      transaction.set(commentRef, comment.toFirestore());
      transaction.update(complaintRef, {
        'commentCount': FieldValue.increment(1),
      });
    });
  }

  /// Deletes a comment and decrements commentCount atomically.
  Future<void> deleteComment({
    required String complaintId,
    required String commentId,
  }) async {
    final commentRef = _db
        .collection('complaints')
        .doc(complaintId)
        .collection('comments')
        .doc(commentId);

    final complaintRef = _db.collection('complaints').doc(complaintId);

    await _db.runTransaction((transaction) async {
      transaction.delete(commentRef);
      transaction.update(complaintRef, {
        'commentCount': FieldValue.increment(-1),
      });
    });
  }

  /// Real-time stream of comments, oldest first.
  Stream<List<CommentModel>> commentsStream(String complaintId) {
    return _db
        .collection('complaints')
        .doc(complaintId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => CommentModel.fromFirestore(doc.data(), doc.id))
            .toList());
  }
}
