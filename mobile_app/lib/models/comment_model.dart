// lib/models/comment_model.dart

class CommentModel {
  final String id;
  final String userId;
  final String userName;
  final String text;
  final DateTime createdAt;
  final bool isEdited;

  const CommentModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
    this.isEdited = false,
  });

  factory CommentModel.fromFirestore(Map<String, dynamic> map, String docId) {
    return CommentModel(
      id: docId,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      text: map['text'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      isEdited: map['isEdited'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'isEdited': isEdited,
      };
}
