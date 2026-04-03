/// WHAT: Stores frontend-wide configuration and display constants.
/// WHY: Shared routes, labels, and backend URLs should not be duplicated across features.
/// HOW: Expose compile-time config and service label helpers through immutable static members.
library;

import '../core/i18n/app_language.dart';

class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:4000/api/v1',
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

  static const Map<String, String> serviceLabelsDe = <String, String>{
    'fire_damage_cleaning': 'Brandschadenreinigung',
    'needle_sweeps_sharps_cleanups': 'Nadel- und Spritzenfunde',
    'hoarding_cleanups': 'Messie-Reinigungen',
    'trauma_decomposition_cleanups': 'Trauma- und Dekontaminationsreinigung',
    'infection_control_cleaning': 'Infektionsschutzreinigung',
    'building_cleaning': 'Gebäudereinigung',
    'window_cleaning': 'Fensterreinigung',
    'office_cleaning': 'Büroreinigung',
    'house_cleaning': 'Hausreinigung',
    'warehouse_hall_cleaning': 'Lager- und Hallenreinigung',
    'winter_service': 'Winterdienst',
    'caretaker_service': 'Hausmeisterservice',
    'garden_care': 'Gartenpflege',
    'post_construction_cleaning': 'Bauendreinigung',
  };

  static const Map<String, String> _legacyServiceLabelsDe = <String, String>{
    'window_glass_cleaning': 'Fenster- und Glasreinigung',
  };

  static String serviceLabelFor(
    String serviceType, {
    AppLanguage language = AppLanguage.english,
  }) {
    final labels = language.isGerman ? serviceLabelsDe : serviceLabels;
    final legacyLabels = language.isGerman
        ? _legacyServiceLabelsDe
        : _legacyServiceLabels;

    return labels[serviceType] ?? legacyLabels[serviceType] ?? serviceType;
  }
}
