// lib/services/storage_service.dart
//
// All media uploaded to Cloudinary (free tier).
// Returns public HTTPS URLs stored in Firestore.
// Anyone can view media — no authentication required to read.

import 'dart:io';
import 'cloudinary_service.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  /// Uploads complaint images to Cloudinary.
  /// Returns list of public HTTPS URLs.
  Future<List<String>> uploadComplaintImages({
    required String userId,
    required String complaintId,
    required List<File> files,
  }) async {
    if (files.isEmpty) return [];
    return await CloudinaryService.instance.uploadImages(
      userId: userId,
      complaintId: complaintId,
      files: files,
    );
  }

  /// Uploads complaint video to Cloudinary.
  /// Returns public HTTPS URL.
  Future<String> saveVideoLocally({
    required String userId,
    required String complaintId,
    required File videoFile,
  }) async {
    return await CloudinaryService.instance.uploadVideo(
      userId: userId,
      complaintId: complaintId,
      file: videoFile,
    );
  }

  /// No-op — Cloudinary manages deletion via dashboard.
  Future<void> deleteComplaintMedia({
    required String userId,
    required String complaintId,
  }) async {}
}
