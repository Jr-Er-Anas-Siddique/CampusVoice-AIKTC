// lib/utils/campus_boundary.dart
//
// AIKTC Campus — New Panvel, Navi Mumbai
// Boundary from 4 verified corner coordinates (Google Maps):
// P1 NW: 19°00'04.5"N 73°06'12.4"E → 19.0012500, 73.1034444
// P2 NE: 19°00'04.5"N 73°06'21.7"E → 19.0012500, 73.1060278
// P3 SE: 18°59'59.7"N 73°06'21.7"E → 18.9999167, 73.1060278
// P4 SW: 19°00'00.1"N 73°06'10.9"E → 19.0000278, 73.1030278

class CampusBoundary {
  CampusBoundary._();

  /// AIKTC campus boundary polygon (lat/lng pairs).
  /// Derived from 4 GPS-verified corner points with a 50m margin added
  /// on each side to account for GPS drift inside buildings.
  static const List<List<double>> _boundaryPolygon = [
    [19.0018000, 73.1025000], // NW (with margin)
    [19.0018000, 73.1066000], // NE (with margin)
    [18.9994000, 73.1066000], // SE (with margin)
    [18.9994000, 73.1025000], // SW (with margin)
    [19.0018000, 73.1025000], // close polygon
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