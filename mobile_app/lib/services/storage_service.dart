// lib/services/storage_service.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  /// Copies image files to app's permanent local storage.
  /// Returns list of permanent local file paths.
  Future<List<String>> uploadComplaintImages({
    required String userId,
    required String complaintId,
    required List<File> files,
  }) async {
    if (files.isEmpty) return [];

    final appDir = await getApplicationDocumentsDirectory();
    final complaintDir = Directory(
      p.join(appDir.path, 'complaints', userId, complaintId),
    );
    await complaintDir.create(recursive: true);

    final List<String> savedPaths = [];

    for (int i = 0; i < files.length; i++) {
      final ext = p.extension(files[i].path);
      final fileName = 'image_$i$ext';
      final destPath = p.join(complaintDir.path, fileName);
      await files[i].copy(destPath);
      savedPaths.add(destPath);
    }

    return savedPaths;
  }

  /// Deletes locally stored images for a complaint.
  Future<void> deleteComplaintImages({
    required String userId,
    required String complaintId,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final complaintDir = Directory(
        p.join(appDir.path, 'complaints', userId, complaintId),
      );
      if (await complaintDir.exists()) {
        await complaintDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}