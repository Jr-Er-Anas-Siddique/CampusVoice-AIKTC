// lib/services/post_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/post_model.dart';
import 'moderation_service.dart';

class PostService {
  PostService._();
  static final PostService instance = PostService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _draftsKey = 'campusvoice_drafts';

  // ── Submit ───────────────────────────────────────────────────────────────

  /// Submits a complaint. Runs system moderation immediately after saving.
  /// If approved       → status: approved, appears in public feed
  /// If autoPrivate    → status: approved, isPublic: false, committee only
  /// If flagged        → status: flagged, hidden from feed + committee
  Future<ModerationResult> submitComplaint({
    required PostModel post,
    required List<File> imageFiles,
  }) async {
    final docId = post.id ?? _db.collection('complaints').doc().id;
    final now = DateTime.now();

    // Step 1 — Save as pendingReview
    // Use statusHistory already built by caller (preserves flagged history on resubmit)
    final pending = post.copyWith(
      id: docId,
      status: ComplaintStatus.pendingReview,
      updatedAt: now,
    );
    await _db.collection('complaints').doc(docId).set(pending.toFirestore());

    // Step 2 — Run system moderation
    final result = await ModerationService.instance.moderate(pending);

    // Step 3 — Update based on result
    final finalStatus =
        result.approved ? ComplaintStatus.approved : ComplaintStatus.flagged;

    final historyNote = result.autoPrivate
        ? 'Auto-switched to Private due to sensitive content'
        : result.approved
            ? 'Automatically approved by system moderator'
            : result.reason ?? 'Flagged by system moderator';

    final updatedHistory = [
      ...pending.statusHistory,
      StatusHistoryEntry(
        status: finalStatus,
        changedAt: DateTime.now(),
        changedBy: 'System Moderator',
        note: historyNote,
      ),
    ];

    await _db.collection('complaints').doc(docId).update({
      'status': finalStatus.name,
      'updatedAt': DateTime.now().toIso8601String(),
      // Auto-private: force isPublic false
      if (result.autoPrivate) 'isPublic': false,
      if (result.autoPrivate) 'moderationNote': result.reason,
      // Flagged: store rejection reason
      if (!result.approved) 'moderationNote': result.reason,
      if (!result.approved) 'rejectionCategory': result.category?.label,
      'statusHistory': updatedHistory.map((e) => e.toMap()).toList(),
      'assignedCommittee': _assignCommittee(post.category),
    });

    // Step 4 — Clean up draft
    if (post.id != null && post.id!.startsWith('draft_')) {
      try { await _deleteDraft(post.id!); } catch (_) {}
    }

    return result;
  }

  // ── Auto Committee Assignment ─────────────────────────────────────────────

  String _assignCommittee(ComplaintCategory category) {
    switch (category) {
      case ComplaintCategory.infrastructure: return 'IPDC';
      case ComplaintCategory.academic:       return 'GARC';
      case ComplaintCategory.library:        return 'KRRC';
      default:                               return 'GARC';
    }
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

  // ── Delete submitted complaint ────────────────────────────────────────────

  /// Permanently deletes a complaint from Firestore.
  /// Only the complaint owner can call this (enforced by security rules).
  Future<void> deleteComplaint(String complaintId) async {
    await _db.collection('complaints').doc(complaintId).delete();
  }

  // ── Feed query ────────────────────────────────────────────────────────────

  /// Returns a stream of approved public complaints ordered by newest first.
  /// Only approved complaints (passed moderation) appear in the public feed.
  Stream<List<PostModel>> feedStream({ComplaintCategory? category}) {
    Query<Map<String, dynamic>> query = _db
        .collection('complaints')
        .where('status', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true);

    if (category != null) {
      query = query.where('category', isEqualTo: category.name);
    }

    return query.snapshots().map((snap) => snap.docs
        .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
        .where((post) => post.isPublic)
        .toList());
  }

  // ── My Complaints ─────────────────────────────────────────────────────────

  /// Returns real-time stream of all complaints submitted by [userId],
  /// newest first, regardless of public/private or status.
  Stream<List<PostModel>> myComplaintsStream(String userId) {
    return _db
        .collection('complaints')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
            .toList());
  }
}
