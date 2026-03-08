import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PostStatus { pending, under_review, in_progress, resolved }

enum PostVisibility { public, private }

enum AssignedCommittee { GARC, IPDC, KRRC }

enum ComplaintCategory { infrastructure, academic, administrative, safety, other }

// ---------------------------------------------------------------------------
// Supporting model: GPS location (for infrastructure complaints)
// ---------------------------------------------------------------------------

class GpsLocation {
  final double latitude;
  final double longitude;
  final double? accuracy; // metres

  const GpsLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
      };

  factory GpsLocation.fromMap(Map<String, dynamic> map) => GpsLocation(
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: map['accuracy'] != null
            ? (map['accuracy'] as num).toDouble()
            : null,
      );
}

// ---------------------------------------------------------------------------
// PostModel
// ---------------------------------------------------------------------------

class PostModel {
  // ── Identity ────────────────────────────────────────────────────────────
  /// Firestore document ID — empty string before the document is persisted.
  final String id;

  // ── Author ───────────────────────────────────────────────────────────────
  final String authorId; // Firebase Auth UID
  final String authorName; // display name at time of posting
  final String? authorAvatarUrl;

  // ── Content ──────────────────────────────────────────────────────────────
  final String title;
  final String description;
  final ComplaintCategory category;

  /// Cloud Storage download URLs for attached evidence images.
  final List<String> imageUrls;

  // ── Location ─────────────────────────────────────────────────────────────
  final String building; // e.g. "Main Block", "Library"
  final String floor; // e.g. "Ground", "1st", "Terrace"

  /// Required and verified when [category] == ComplaintCategory.infrastructure.
  final GpsLocation? gpsLocation;

  /// True once the GPS co-ordinates have been server-side verified.
  final bool isGpsVerified;

  // ── Visibility & Assignment ───────────────────────────────────────────────
  final PostVisibility visibility;

  /// Auto-assigned by a Cloud Function / service layer based on [category].
  final AssignedCommittee assignedCommittee;

  // ── Status ───────────────────────────────────────────────────────────────
  final PostStatus status;

  /// UID of the committee member who last updated the status.
  final String? resolvedById;

  /// Optional note left by the resolver / reviewer.
  final String? statusNote;

  // ── Social counters ───────────────────────────────────────────────────────
  /// Number of users who have "supported" (up-voted) this post.
  final int supportCount;

  /// Denormalised count kept in sync with the sub-collection.
  final int commentCount;

  // ── Timestamps ───────────────────────────────────────────────────────────
  /// Set by the server via FieldValue.serverTimestamp() on first write.
  final DateTime? createdAt;

  /// Updated every time any field changes.
  final DateTime? updatedAt;

  // ── Constructor ───────────────────────────────────────────────────────────
  const PostModel({
    this.id = '',
    required this.authorId,
    required this.authorName,
    this.authorAvatarUrl,
    required this.title,
    required this.description,
    required this.category,
    this.imageUrls = const [],
    required this.building,
    required this.floor,
    this.gpsLocation,
    this.isGpsVerified = false,
    this.visibility = PostVisibility.public,
    required this.assignedCommittee,
    this.status = PostStatus.pending,
    this.resolvedById,
    this.statusNote,
    this.supportCount = 0,
    this.commentCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  // ── toMap ─────────────────────────────────────────────────────────────────
  /// Converts the model to a Firestore-compatible map.
  ///
  /// Pass [isNew] = true on initial creation so that [createdAt] is written
  /// with a server timestamp; subsequent updates only touch [updatedAt].
  Map<String, dynamic> toMap({bool isNew = false}) {
    return {
      // Identity — 'id' is stored in the document path, not the body.
      'authorId': authorId,
      'authorName': authorName,
      if (authorAvatarUrl != null) 'authorAvatarUrl': authorAvatarUrl,

      // Content
      'title': title,
      'description': description,
      'category': category.name,
      'imageUrls': imageUrls,

      // Location
      'building': building,
      'floor': floor,
      if (gpsLocation != null) 'gpsLocation': gpsLocation!.toMap(),
      'isGpsVerified': isGpsVerified,

      // Visibility & assignment
      'visibility': visibility.name,
      'assignedCommittee': assignedCommittee.name,

      // Status
      'status': status.name,
      if (resolvedById != null) 'resolvedById': resolvedById,
      if (statusNote != null) 'statusNote': statusNote,

      // Counters
      'supportCount': supportCount,
      'commentCount': commentCount,

      // Timestamps — always use server timestamps for accuracy.
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // ── fromMap factory ───────────────────────────────────────────────────────
  /// Reconstructs a [PostModel] from a Firestore document snapshot.
  factory PostModel.fromMap(Map<String, dynamic> map, {String id = ''}) {
    return PostModel(
      id: id,

      authorId: map['authorId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorAvatarUrl: map['authorAvatarUrl'] as String?,

      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: ComplaintCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => ComplaintCategory.other,
      ),
      imageUrls: List<String>.from(map['imageUrls'] as List? ?? []),

      building: map['building'] as String? ?? '',
      floor: map['floor'] as String? ?? '',
      gpsLocation: map['gpsLocation'] != null
          ? GpsLocation.fromMap(
              Map<String, dynamic>.from(map['gpsLocation'] as Map))
          : null,
      isGpsVerified: map['isGpsVerified'] as bool? ?? false,

      visibility: PostVisibility.values.firstWhere(
        (e) => e.name == map['visibility'],
        orElse: () => PostVisibility.public,
      ),
      assignedCommittee: AssignedCommittee.values.firstWhere(
        (e) => e.name == map['assignedCommittee'],
        orElse: () => AssignedCommittee.GARC,
      ),

      status: PostStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PostStatus.pending,
      ),
      resolvedById: map['resolvedById'] as String?,
      statusNote: map['statusNote'] as String?,

      supportCount: (map['supportCount'] as num?)?.toInt() ?? 0,
      commentCount: (map['commentCount'] as num?)?.toInt() ?? 0,

      // Firestore returns Timestamps; handle both Timestamp and DateTime.
      createdAt: _toDateTime(map['createdAt']),
      updatedAt: _toDateTime(map['updatedAt']),
    );
  }

  // ── fromSnapshot convenience ──────────────────────────────────────────────
  /// Convenience factory that pulls the document ID automatically.
  factory PostModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    return PostModel.fromMap(snap.data() ?? {}, id: snap.id);
  }

  // ── copyWith ──────────────────────────────────────────────────────────────
  PostModel copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorAvatarUrl,
    String? title,
    String? description,
    ComplaintCategory? category,
    List<String>? imageUrls,
    String? building,
    String? floor,
    GpsLocation? gpsLocation,
    bool? isGpsVerified,
    PostVisibility? visibility,
    AssignedCommittee? assignedCommittee,
    PostStatus? status,
    String? resolvedById,
    String? statusNote,
    int? supportCount,
    int? commentCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      imageUrls: imageUrls ?? this.imageUrls,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      gpsLocation: gpsLocation ?? this.gpsLocation,
      isGpsVerified: isGpsVerified ?? this.isGpsVerified,
      visibility: visibility ?? this.visibility,
      assignedCommittee: assignedCommittee ?? this.assignedCommittee,
      status: status ?? this.status,
      resolvedById: resolvedById ?? this.resolvedById,
      statusNote: statusNote ?? this.statusNote,
      supportCount: supportCount ?? this.supportCount,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  /// Whether GPS verification is required for this post.
  bool get requiresGps => category == ComplaintCategory.infrastructure;

  /// Friendly label used in the UI.
  String get statusLabel {
    switch (status) {
      case PostStatus.pending:
        return 'Pending';
      case PostStatus.under_review:
        return 'Under Review';
      case PostStatus.in_progress:
        return 'In Progress';
      case PostStatus.resolved:
        return 'Resolved';
    }
  }

  @override
  String toString() =>
      'PostModel(id: $id, title: $title, status: ${status.name}, '
      'committee: ${assignedCommittee.name})';
}

// ---------------------------------------------------------------------------
// Private helper
// ---------------------------------------------------------------------------

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
