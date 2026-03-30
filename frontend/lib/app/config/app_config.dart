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
    'fire_damage_cleaning': 'Fire Damage Cleaning',
    'needle_sweeps_sharps_cleanups': 'Needle Sweeps & Sharps Clean-Ups',
    'hoarding_cleanups': 'Hoarding Clean-Ups',
    'trauma_decomposition_cleanups': 'Trauma & Decomposition Clean-Ups',
    'infection_control_cleaning': 'Infection Control Cleaning',
    'building_cleaning': 'Building Cleaning',
    'window_cleaning': 'Window Cleaning',
    'office_cleaning': 'Office Cleaning',
    'house_cleaning': 'House Cleaning',
    'warehouse_hall_cleaning': 'Warehouse & Hall Cleaning',
    'winter_service': 'Winter Service',
    'caretaker_service': 'Caretaker Service',
    'garden_care': 'Garden Care',
    'post_construction_cleaning': 'Post-Construction Cleaning',
  };

  static const Map<String, String> _legacyServiceLabels = <String, String>{
    'window_glass_cleaning': 'Window & Glass Cleaning',
  };

  static String serviceLabelFor(String serviceType) {
    return serviceLabels[serviceType] ??
        _legacyServiceLabels[serviceType] ??
        serviceType;
  }
}
