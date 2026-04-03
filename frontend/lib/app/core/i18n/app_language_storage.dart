library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_language_storage_io.dart'
    if (dart.library.html) 'app_language_storage_web.dart'
    as language_storage;

final appLanguageStorageProvider = Provider<AppLanguageStorage>((Ref ref) {
  return const AppLanguageStorage();
});

class AppLanguageStorage {
  const AppLanguageStorage();

  String? load() {
    return language_storage.loadStoredAppLanguageCode();
  }

  void save(String code) {
    language_storage.saveStoredAppLanguageCode(code);
  }

  void clear() {
    language_storage.clearStoredAppLanguageCode();
  }
}
