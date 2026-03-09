import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _postsRef =>
      _firestore.collection('posts');

  Future<String> createPost(PostModel post) async {
    final doc = _postsRef.doc();

    final newPost = post.copyWith(id: doc.id);

    await doc.set(newPost.toMap(isNew: true));

    return doc.id;
  }

  Stream<List<PostModel>> fetchPosts() {
    return _postsRef.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) => PostModel.fromSnapshot(doc)).toList();
    });
  }

  Future<void> updatePostStatus({
    required String postId,
    required PostStatus status,
    String? statusNote,
    String? resolvedById,
  }) async {
    await _postsRef.doc(postId).update({
      'status': status.name,
      if (statusNote != null) 'statusNote': statusNote,
      if (resolvedById != null) 'resolvedById': resolvedById,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> supportPost(String postId) async {
    await _postsRef.doc(postId).update({
      'supportCount': FieldValue.increment(1),
    });
  }

  Future<PostModel?> getPost(String postId) async {
    final doc = await _postsRef.doc(postId).get();

    if (!doc.exists) return null;

    return PostModel.fromSnapshot(doc);
  }
}
