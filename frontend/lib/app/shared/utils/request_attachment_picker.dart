library;

import 'request_attachment_picker_stub.dart'
    if (dart.library.js_interop) 'request_attachment_picker_web.dart'
    as impl;
import 'request_attachment_picker_types.dart';

Future<PickedRequestAttachmentFile?> pickRequestAttachmentFile() {
  return impl.pickRequestAttachmentFile();
}
