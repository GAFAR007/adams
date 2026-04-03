// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

library;

import 'dart:html' as html;

const String _appLanguageStorageKey = 'adams.app.language';

String? loadStoredAppLanguageCode() {
  return html.window.localStorage[_appLanguageStorageKey];
}

void saveStoredAppLanguageCode(String code) {
  html.window.localStorage[_appLanguageStorageKey] = code;
}

void clearStoredAppLanguageCode() {
  html.window.localStorage.remove(_appLanguageStorageKey);
}
