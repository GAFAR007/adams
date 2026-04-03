library;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_language_storage.dart';

enum AppLanguage { english, german }

AppLanguage appLanguageFromCode(String? code) {
  return code == 'de' ? AppLanguage.german : AppLanguage.english;
}

String appLanguageCode(AppLanguage language) {
  return language == AppLanguage.german ? 'de' : 'en';
}

extension AppLanguageX on AppLanguage {
  bool get isGerman => this == AppLanguage.german;

  String pick({required String en, required String de}) {
    return isGerman ? de : en;
  }
}

class AppLanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final storedCode = ref.read(appLanguageStorageProvider).load();
    return appLanguageFromCode(storedCode);
  }

  void setLanguage(AppLanguage language) {
    if (state == language) {
      return;
    }

    _setStateSafely(language);
    ref.read(appLanguageStorageProvider).save(appLanguageCode(language));
  }

  void syncFromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return;
    }

    final nextLanguage = appLanguageFromCode(code);
    if (state == nextLanguage) {
      return;
    }

    _setStateSafely(nextLanguage);
    ref.read(appLanguageStorageProvider).save(appLanguageCode(state));
  }

  void _setStateSafely(AppLanguage nextLanguage) {
    void apply() {
      state = nextLanguage;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
      return;
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      apply();
    });
  }
}

final appLanguageProvider =
    NotifierProvider<AppLanguageController, AppLanguage>(
      AppLanguageController.new,
    );

String t(AppLanguage language, {required String en, required String de}) {
  return language.pick(en: en, de: de);
}
