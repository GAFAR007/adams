library;

import 'request_attachment_picker_stub.dart'
    if (dart.library.js_interop) 'request_attachment_picker_web.dart'
    as impl;
import 'request_attachment_picker_types.dart';

Future<PickedRequestAttachmentFile?> pickRequestAttachmentFile() {
  return impl.pickRequestAttachmentFile();
}

Future<List<PickedRequestAttachmentFile>> pickRequestAttachmentFiles({
  int maxFiles = 1,
  bool imagesOnly = false,
}) {
  return impl.pickRequestAttachmentFiles(
    maxFiles: maxFiles,
    imagesOnly: imagesOnly,
  );
}
