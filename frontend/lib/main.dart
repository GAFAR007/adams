/// WHAT: Launches the Flutter application with Riverpod enabled.
/// WHY: The app relies on shared providers for auth, routing, and API access.
/// HOW: Wrap the root widget in `ProviderScope` and hand control to `AdamsApp`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  runApp(const ProviderScope(child: AdamsApp()));
}
