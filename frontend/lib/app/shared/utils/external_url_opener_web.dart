// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

library;

import 'dart:html' as html;

Future<bool> openExternalUrl(String url, {bool sameTab = false}) async {
  final normalized = url.trim();
  if (normalized.isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(normalized);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  final isBrowserNavigation = scheme == 'http' || scheme == 'https';

  if (sameTab || !isBrowserNavigation) {
    html.window.location.href = normalized;
    return true;
  }

  html.window.open(normalized, '_blank');
  return true;
}
