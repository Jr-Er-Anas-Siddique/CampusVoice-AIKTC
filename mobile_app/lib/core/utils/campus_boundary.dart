// lib/utils/campus_boundary.dart
//
// AIKTC Campus — New Panvel, Navi Mumbai
// Center: 19.0002258, 73.1046218
// Campus size: ~10.5 acres
// Boundary polygon traced around Plot No. 2 & 3, Sector-16, Khandagao

class CampusBoundary {
  CampusBoundary._();

  /// AIKTC campus boundary polygon (lat/lng pairs).
  /// Based on center point 19.0002258, 73.1046218
  /// Covers ~10.5 acres around the campus plots.
  static const List<List<double>> _boundaryPolygon = [
    [19.0012000, 73.1036000], // NW corner
    [19.0012000, 73.1058000], // NE corner
    [18.9992000, 73.1058000], // SE corner
    [18.9992000, 73.1036000], // SW corner
    [19.0012000, 73.1036000], // close polygon
  ];

  /// Returns true if the given [lat]/[lng] is inside the campus boundary.
  static bool isOnCampus(double lat, double lng) {
    final polygon = _boundaryPolygon;
    int intersections = 0;
    final n = polygon.length;

    for (int i = 0; i < n - 1; i++) {
      final x1 = polygon[i][1];
      final y1 = polygon[i][0];
      final x2 = polygon[i + 1][1];
      final y2 = polygon[i + 1][0];

      if (((y1 <= lat && lat < y2) || (y2 <= lat && lat < y1)) &&
          (lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  static const double maxAccuracyMetres = 50.0;

  static bool isAccuracyAcceptable(double accuracyMetres) =>
      accuracyMetres <= maxAccuracyMetres;
}