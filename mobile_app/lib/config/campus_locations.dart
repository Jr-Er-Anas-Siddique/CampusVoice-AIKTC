// lib/config/campus_locations.dart

class CampusLocations {
  CampusLocations._();

  static const List<String> indoorBuildings = [
    'Architecture Building',
    'Engineering Building',
    'Pharmacy Building',
  ];

  static const List<String> outdoorAreas = [
    'Ground',
    'Parking Area',
    'Campus Roads',
    'Backyard Area',
  ];

  static List<String> get allLocations => [
        ...indoorBuildings,
        ...outdoorAreas,
      ];

  static const List<String> floors = [
    'Ground Floor',
    '1st Floor',
    '2nd Floor',
    '3rd Floor',
    'Terrace',
  ];

  static bool isOutdoor(String location) => outdoorAreas.contains(location);
  static bool isIndoor(String location) => indoorBuildings.contains(location);
}
