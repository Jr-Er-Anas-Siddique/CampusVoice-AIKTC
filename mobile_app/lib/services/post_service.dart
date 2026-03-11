// lib/services/post_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import 'storage_service.dart';

class PostException implements Exception {
  final String message;
  const PostException(this.message);
  @override
  String toString() => message;
}

class PostService {
  PostService._();
  static final PostService instance = PostService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _draftsKey = 'complaint_drafts';

  // ─────────────────────────────────────────────
  // FIRESTORE — Submit complaint
  // ─────────────────────────────────────────────

  /// Uploads images then submits complaint to Firestore.
  /// Returns the saved [PostModel] with Firestore ID and image URLs.
  // lib/services/post_service.dart

Future<PostModel> submitComplaint({
  required PostModel post,
  required List<File> imageFiles,
}) async {
  try {
    final docRef = _firestore.collection('complaints').doc();
    final complaintId = docRef.id;

    // In lib/services/post_service.dart
    List<String> imageUrls = [];
    if (imageFiles.isNotEmpty) {
      imageUrls = await StorageService.instance.uploadComplaintImages(
        userId: post.userId,
        complaintId: complaintId,
        files: imageFiles,
      );
      
      // ADD THIS CHECK:
      if (imageUrls.isEmpty) {
         throw PostException('Images selected but failed to upload. Check terminal for errors.');
      }
    }

    final submitted = post.copyWith(
      id: complaintId,
      imageUrls: imageUrls,
      status: ComplaintStatus.submitted,
      updatedAt: DateTime.now(),
    );

    await docRef.set(submitted.toFirestore());
    return submitted;
  } catch (e) {
    print('DEBUG: Submission Error: $e');
    throw PostException('Failed to submit: $e');
  }
}

  /// Fetches all complaints for a user ordered by newest first.
  Stream<List<PostModel>> getUserComplaints(String userId) {
    return _firestore
        .collection('complaints')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  // ─────────────────────────────────────────────
  // LOCAL DRAFTS — SharedPreferences
  // ─────────────────────────────────────────────

  /// Saves or updates a draft locally.
  Future<void> saveDraft(PostModel draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await _loadAllDraftMaps(prefs);

      // Generate a local ID if none exists
      final id = draft.id ?? 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final updated = draft.copyWith(
        id: id,
        status: ComplaintStatus.draft,
        updatedAt: DateTime.now(),
      );

      drafts[id] = jsonEncode(updated.toDraftMap());
      await prefs.setString(_draftsKey, jsonEncode(drafts));
    } catch (e) {
      throw PostException('Failed to save draft: $e');
    }
  }

  /// Returns all locally saved drafts for a user.
  Future<List<PostModel>> getUserDrafts(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await _loadAllDraftMaps(prefs);

      return drafts.values
          .map((jsonStr) =>
              PostModel.fromDraftMap(jsonDecode(jsonStr) as Map<String, dynamic>))
          .where((d) => d.userId == userId)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return [];
    }
  }

  /// Deletes a draft by ID.
  Future<void> deleteDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = await _loadAllDraftMaps(prefs);
      drafts.remove(draftId);
      await prefs.setString(_draftsKey, jsonEncode(drafts));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _loadAllDraftMaps(
      SharedPreferences prefs) async {
    final raw = prefs.getString(_draftsKey);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
}
