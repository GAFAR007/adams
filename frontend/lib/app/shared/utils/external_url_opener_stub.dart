library;

import 'package:url_launcher/url_launcher_string.dart';

Future<bool> openExternalUrl(String url, {bool sameTab = false}) async {
  final normalized = url.trim();
  if (normalized.isEmpty) {
    return false;
  }

  return launchUrlString(normalized, mode: LaunchMode.externalApplication);
}
