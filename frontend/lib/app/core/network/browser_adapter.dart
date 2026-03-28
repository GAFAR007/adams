/// WHAT: Provides the default non-web browser adapter configuration hook for Dio.
/// WHY: Web credential handling needs a different implementation than mobile and desktop builds.
/// HOW: Export a no-op adapter setup that other platforms can compile safely.
library;

import 'package:dio/dio.dart';

void configureBrowserAdapter(Dio dio) {
  // Non-web builds do not need browser credential configuration.
  if (dio.options.baseUrl.isEmpty) {
    return;
  }
}
