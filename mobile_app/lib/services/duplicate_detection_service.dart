// lib/services/duplicate_detection_service.dart
//
// Checks for duplicate complaints before submission.
// Matches by: same building + same category within last 30 days
// that are approved/underReview/inProgress (active complaints).
//
// Returns the most supported matching complaint if found, null otherwise.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

class DuplicateDetectionService {
  DuplicateDetectionService._();
  static final DuplicateDetectionService instance =
      DuplicateDetectionService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Only check against active complaints (not resolved/rejected/flagged)
  static const List<String> _activeStatuses = [
    'approved',
    'underReview',
    'inProgress',
  ];

  static const int _lookbackDays = 30;

  /// Returns the most relevant similar complaint if one exists, null otherwise.
  Future<PostModel?> findSimilar({
    required String building,
    required ComplaintCategory category,
    required String currentUserId,
  }) async {
    if (building.isEmpty) return null;

    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: _lookbackDays))
          .toIso8601String();

      // Query by building + category — most supported first
      final snap = await _db
          .collection('complaints')
          .where('building', isEqualTo: building)
          .where('category', isEqualTo: category.name)
          .where('isPublic', isEqualTo: true)
          .where('createdAt', isGreaterThanOrEqualTo: cutoff)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      if (snap.docs.isEmpty) return null;

      // Filter to active statuses only
      final active = snap.docs
          .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
          .where((p) => _activeStatuses.contains(p.status.name))
          // Don't show student their own complaint as a duplicate
          .where((p) => p.userId != currentUserId)
          .toList();

      if (active.isEmpty) return null;

      // Return the one with most supports
      active.sort((a, b) => b.supportCount.compareTo(a.supportCount));
      return active.first;
    } catch (_) {
      // If query fails, allow submission to proceed
      return null;
    }
  }
}
