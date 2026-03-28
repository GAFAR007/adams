/// WHAT: Stores frontend-wide configuration and display constants.
/// WHY: Shared routes, labels, and backend URLs should not be duplicated across features.
/// HOW: Expose compile-time config and service label helpers through immutable static members.
library;

class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000/api/v1',
  );

  static const Map<String, String> serviceLabels = <String, String>{
    'building_cleaning': 'Building Cleaning',
    'warehouse_hall_cleaning': 'Warehouse & Hall Cleaning',
    'window_glass_cleaning': 'Window & Glass Cleaning',
    'winter_service': 'Winter Service',
    'caretaker_service': 'Caretaker Service',
    'garden_care': 'Garden Care',
    'post_construction_cleaning': 'Post-Construction Cleaning',
  };

  static String serviceLabelFor(String serviceType) {
    return serviceLabels[serviceType] ?? serviceType;
  }
}
