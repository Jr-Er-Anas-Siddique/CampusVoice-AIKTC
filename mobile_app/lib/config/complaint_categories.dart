// lib/config/complaint_categories.dart

import '../models/post_model.dart';

class ComplaintCategories {
  ComplaintCategories._();

  static const List<ComplaintCategory> all = ComplaintCategory.values;

  /// Infrastructure complaints require GPS + camera only (no gallery)
  static bool requiresGps(ComplaintCategory category) =>
      category == ComplaintCategory.infrastructure;

  static bool cameraOnly(ComplaintCategory category) =>
      category == ComplaintCategory.infrastructure;
}
