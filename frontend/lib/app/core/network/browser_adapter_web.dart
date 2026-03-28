/// WHAT: Configures Dio for Flutter web requests that rely on browser-managed cookies.
/// WHY: The backend stores refresh tokens in HttpOnly cookies, so web requests must send credentials.
/// HOW: Swap in the browser HTTP adapter and enable `withCredentials`.
library;

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureBrowserAdapter(Dio dio) {
  final adapter = BrowserHttpClientAdapter()..withCredentials = true;
  dio.httpClientAdapter = adapter;
}
