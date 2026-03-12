// lib/services/post_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';

class PostService {
  PostService._();
  static final PostService instance = PostService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _draftsKey = 'campusvoice_drafts';

  // ── Submit ───────────────────────────────────────────────────────────────

  /// Submits a complaint to Firestore.
  /// Images and videos are already uploaded by report_issue_page before calling this.
  /// post.imageUrls and post.videoPaths already contain Cloudinary URLs.
  Future<String> submitComplaint({
    required PostModel post,
    required List<File> imageFiles, // ignored — already uploaded by caller
  }) async {
    // Use docId already set in report_issue_page, or generate new one
    final docId = post.id ?? _db.collection('complaints').doc().id;

    final submitted = post.copyWith(
      id: docId,
      status: ComplaintStatus.submitted,
      updatedAt: DateTime.now(),
    );

    await _db.collection('complaints').doc(docId).set(submitted.toFirestore());

    // Clean up draft if this was one
    if (post.id != null) {
      try { await _deleteDraft(post.id!); } catch (_) {}
    }

    return docId;
  }

  // ── Drafts (SharedPreferences) ───────────────────────────────────────────

  Future<List<PostModel>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftsKey);
    if (raw == null) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list
          .map((e) => PostModel.fromDraftMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDraft(PostModel draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();

    final id = draft.id ?? 'draft_${DateTime.now().millisecondsSinceEpoch}';
    final updated = draft.copyWith(
      id: id,
      status: ComplaintStatus.draft,
      updatedAt: DateTime.now(),
    );

    final idx = drafts.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      drafts[idx] = updated;
    } else {
      drafts.add(updated);
    }

    await prefs.setString(
      _draftsKey,
      jsonEncode(drafts.map((d) => d.toDraftMap()).toList()),
    );
  }

  Future<void> _deleteDraft(String draftId) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == draftId);
    await prefs.setString(
      _draftsKey,
      jsonEncode(drafts.map((d) => d.toDraftMap()).toList()),
    );
  }

  Future<void> deleteDraft(String draftId) => _deleteDraft(draftId);

  // ── Feed query ────────────────────────────────────────────────────────────

  /// Returns a stream of submitted public complaints ordered by newest first.
  Stream<List<PostModel>> feedStream({ComplaintCategory? category}) {
    Query<Map<String, dynamic>> query = _db
        .collection('complaints')
        .where('status', isEqualTo: 'submitted')
        .orderBy('createdAt', descending: true);

    if (category != null) {
      query = query.where('category', isEqualTo: category.name);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
        .where((post) => post.isPublic)
        .toList());
  }
}
