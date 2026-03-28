library;

import 'external_url_opener_stub.dart'
    if (dart.library.js_interop) 'external_url_opener_web.dart'
    as impl;

Future<bool> openExternalUrl(String url) {
  return impl.openExternalUrl(url);
}
