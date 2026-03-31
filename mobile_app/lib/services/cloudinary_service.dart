// lib/services/cloudinary_service.dart
//
// Uploads media to Cloudinary using unsigned upload preset.
// FREE tier: 25GB storage, 25GB bandwidth/month — no credit card needed.
//
// SETUP:
// 1. Create account at https://cloudinary.com (free)
// 2. Go to Settings → Upload → Upload Presets → Add upload preset
// 3. Set Signing Mode = Unsigned, Preset name = campusvoice
// 4. Replace YOUR_CLOUD_NAME below with your actual cloud name from dashboard

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

class CloudinaryException implements Exception {
  final String message;
  const CloudinaryException(this.message);
  @override
  String toString() => message;
}

class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  // ── REPLACE THIS with your Cloudinary cloud name ──────────────────────────
  static const String _cloudName = 'dztcggsov';
  static const String _uploadPreset = 'campusvoice'; // unsigned preset name
  // ─────────────────────────────────────────────────────────────────────────

  String get _imageUploadUrl =>
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';
  String get _videoUploadUrl =>
      'https://api.cloudinary.com/v1_1/$_cloudName/video/upload';

  /// Uploads multiple image files to Cloudinary.
  /// Returns list of public HTTPS URLs.
  /// Uploads multiple image files to Cloudinary.
  Future<List<String>> uploadImages({
    required String userId,
    required String complaintId,
    required List<File> files,
  }) async {
    if (files.isEmpty) return [];
    final List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      try {
        debugPrint('DEBUG: Uploading image ${i + 1}/${files.length}...');
        final url = await _uploadFile(
          file: files[i],
          uploadUrl: _imageUploadUrl,
          folder: 'campusvoice/complaints/$userId/$complaintId/images',
          resourceType: 'image',
        );
        urls.add(url);
      } catch (e) {
        // THIS WILL FINALLY SHOW YOU THE ERROR IN THE TERMINAL
        debugPrint('❌ CLOUDINARY UPLOAD FAILED: $e');
        rethrow; // Send the error up so the app knows it failed
      }
    }
    return urls;
  }

  /// Uploads a single video file to Cloudinary.
  /// Returns the public HTTPS URL.
  Future<String> uploadVideo({
    required String userId,
    required String complaintId,
    required File file,
  }) async {
    return await _uploadFile(
      file: file,
      uploadUrl: _videoUploadUrl,
      folder: 'campusvoice/complaints/$userId/$complaintId/videos',
      resourceType: 'video',
    );
  }

  Future<String> _uploadFile({
    required File file,
    required String uploadUrl,
    required String folder,
    required String resourceType,
  }) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final mimeType = _mimeType(resourceType, ext);

      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = folder
        ..files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType.parse(mimeType),
        ));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return json['secure_url'] as String;
      } else {
        final error = json['error']?['message'] ?? 'Upload failed';
        throw CloudinaryException('Cloudinary upload failed: $error');
      }
    } catch (e) {
      if (e is CloudinaryException) rethrow;
      throw CloudinaryException('Upload error: $e');
    }
  }

  String _mimeType(String resourceType, String ext) {
    if (resourceType == 'video') {
      switch (ext) {
        case 'mp4':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        default:
          return 'video/mp4';
      }
    } else {
      switch (ext) {
        case 'jpg':
        case 'jpeg':
          return 'image/jpeg';
        case 'png':
          return 'image/png';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    }
  }
}
