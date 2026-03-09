import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads an image to Firebase Storage and returns the download URL
  Future<String?> uploadPostImage(File imageFile, String postId) async {
    try {
      // Storage path
      final Reference ref = _storage.ref().child('posts/$postId.jpg');

      // Upload file
      UploadTask uploadTask = ref.putFile(imageFile);

      // Wait for completion
      TaskSnapshot snapshot = await uploadTask;

      // Get download URL
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print("Image upload failed: $e");
      return null;
    }
  }
}