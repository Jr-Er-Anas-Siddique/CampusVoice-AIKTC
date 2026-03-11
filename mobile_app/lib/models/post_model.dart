// lib/models/post_model.dart

enum ComplaintStatus { draft, submitted, inProgress, resolved, rejected }

enum ComplaintCategory {
  infrastructure,
  academic,
  administrative,
  safety,
  other,
}

extension ComplaintCategoryExt on ComplaintCategory {
  String get label {
    switch (this) {
      case ComplaintCategory.infrastructure:
        return 'Infrastructure';
      case ComplaintCategory.academic:
        return 'Academic';
      case ComplaintCategory.administrative:
        return 'Administrative';
      case ComplaintCategory.safety:
        return 'Safety';
      case ComplaintCategory.other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case ComplaintCategory.infrastructure:
        return '🏗️';
      case ComplaintCategory.academic:
        return '📚';
      case ComplaintCategory.administrative:
        return '📋';
      case ComplaintCategory.safety:
        return '🛡️';
      case ComplaintCategory.other:
        return '📌';
    }
  }
}

class GpsCoordinates {
  final double latitude;
  final double longitude;
  final double? accuracy;

  const GpsCoordinates({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };
    if (accuracy != null) map['accuracy'] = accuracy;
    return map;
  }

  factory GpsCoordinates.fromMap(Map<String, dynamic> map) => GpsCoordinates(
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        accuracy: map['accuracy'] != null
            ? (map['accuracy'] as num).toDouble()
            : null,
      );
}

class PostModel {
  final String? id;
  final String userId;
  final String userEmail;
  final String userName;

  // Core fields
  final String title;
  final String description;
  final ComplaintCategory category;

  // Location
  final String building;
  final String? floor;
  final String? roomNumber;

  // Media — images
  final List<String> imageUrls;       // permanent cloud URLs (submitted)
  final List<String> localImagePaths; // temp paths (draft only)

  // Media — videos (max up to totalMediaSlots - imageCount)
  final List<String> videoPaths;      // permanent cloud URLs or local paths

  // GPS
  final GpsCoordinates? gpsCoordinates;
  final bool? isOnCampus;

  // Status
  final ComplaintStatus status;
  final bool isPublic; // true = visible in feed, false = private (moderator/committee only)
  final DateTime createdAt;
  final DateTime updatedAt;

  const PostModel({
    this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.title,
    required this.description,
    required this.category,
    required this.building,
    this.floor,
    this.roomNumber,
    this.imageUrls = const [],
    this.localImagePaths = const [],
    this.videoPaths = const [],
    this.gpsCoordinates,
    this.isOnCampus,
    this.status = ComplaintStatus.draft,
    this.isPublic = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status == ComplaintStatus.draft;
  bool get isOutdoor => _outdoorLocations.contains(building);
  bool get hasVideo => videoPaths.isNotEmpty;

  static const List<String> _outdoorLocations = [
    'Ground',
    'Parking Area',
    'Campus Roads',
    'Backyard Area',
  ];

  PostModel copyWith({
    String? id,
    String? userId,
    String? userEmail,
    String? userName,
    String? title,
    String? description,
    ComplaintCategory? category,
    String? building,
    String? floor,
    String? roomNumber,
    List<String>? imageUrls,
    List<String>? localImagePaths,
    List<String>? videoPaths,
    GpsCoordinates? gpsCoordinates,
    bool? isOnCampus,
    ComplaintStatus? status,
    bool? isPublic,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      roomNumber: roomNumber ?? this.roomNumber,
      imageUrls: imageUrls ?? this.imageUrls,
      localImagePaths: localImagePaths ?? this.localImagePaths,
      videoPaths: videoPaths ?? this.videoPaths,
      gpsCoordinates: gpsCoordinates ?? this.gpsCoordinates,
      isOnCampus: isOnCampus ?? this.isOnCampus,
      status: status ?? this.status,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Firestore serialization ─────────────────────────────────────────────

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'userId': userId,
      'userEmail': userEmail,
      'userName': userName,
      'title': title,
      'description': description,
      'category': category.name,
      'building': building,
      'status': status.name,
      'isPublic': isPublic,
      'imageUrls': imageUrls,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };

    if (floor != null) map['floor'] = floor;
    if (roomNumber != null) map['roomNumber'] = roomNumber;
    if (isOnCampus != null) map['isOnCampus'] = isOnCampus;
    if (gpsCoordinates != null) map['gpsCoordinates'] = gpsCoordinates!.toMap();
    if (videoPaths.isNotEmpty) map['videoPaths'] = videoPaths;

    return map;
  }

  factory PostModel.fromFirestore(Map<String, dynamic> map, String docId) {
    return PostModel(
      id: docId,
      userId: map['userId'] ?? '',
      userEmail: map['userEmail'] ?? '',
      userName: map['userName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: ComplaintCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => ComplaintCategory.other,
      ),
      building: map['building'] ?? '',
      floor: map['floor'],
      roomNumber: map['roomNumber'],
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      videoPaths: List<String>.from(map['videoPaths'] ?? []),
      gpsCoordinates: map['gpsCoordinates'] != null
          ? GpsCoordinates.fromMap(
              Map<String, dynamic>.from(map['gpsCoordinates']))
          : null,
      isOnCampus: map['isOnCampus'],
      status: ComplaintStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ComplaintStatus.draft,
      ),
      isPublic: map['isPublic'] ?? true,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  // ── Draft serialization (SharedPreferences) ─────────────────────────────

  Map<String, dynamic> toDraftMap() => {
        'id': id,
        'userId': userId,
        'userEmail': userEmail,
        'userName': userName,
        'title': title,
        'description': description,
        'category': category.name,
        'building': building,
        'floor': floor,
        'roomNumber': roomNumber,
        'imageUrls': imageUrls,
        'localImagePaths': localImagePaths,
        'videoPaths': videoPaths,
        'gpsCoordinates': gpsCoordinates?.toMap(),
        'isOnCampus': isOnCampus,
        'status': status.name,
        'isPublic': isPublic,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PostModel.fromDraftMap(Map<String, dynamic> map) {
    return PostModel(
      id: map['id'],
      userId: map['userId'] ?? '',
      userEmail: map['userEmail'] ?? '',
      userName: map['userName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: ComplaintCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => ComplaintCategory.other,
      ),
      building: map['building'] ?? '',
      floor: map['floor'],
      roomNumber: map['roomNumber'],
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      localImagePaths: List<String>.from(map['localImagePaths'] ?? []),
      videoPaths: List<String>.from(map['videoPaths'] ?? []),
      gpsCoordinates: map['gpsCoordinates'] != null
          ? GpsCoordinates.fromMap(
              Map<String, dynamic>.from(map['gpsCoordinates']))
          : null,
      isOnCampus: map['isOnCampus'],
      status: ComplaintStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ComplaintStatus.draft,
      ),
      isPublic: map['isPublic'] ?? true,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}
