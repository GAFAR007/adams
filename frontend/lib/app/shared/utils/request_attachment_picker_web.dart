// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

library;

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'request_attachment_picker_types.dart';

Future<PickedRequestAttachmentFile?> pickRequestAttachmentFile() async {
  final completer = Completer<PickedRequestAttachmentFile?>();
  final input = html.FileUploadInputElement()
    ..accept =
        '.png,.jpg,.jpeg,.webp,.pdf,.txt,.doc,.docx,image/png,image/jpeg,image/webp,application/pdf,text/plain,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ..multiple = false
    ..style.display = 'none';

  html.document.body?.append(input);

  void cleanup() {
    input.remove();
  }

  input.onChange.listen((_) {
    final file = input.files?.first;
    if (file == null) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return;
    }

    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      final bytes = switch (result) {
        ByteBuffer value => Uint8List.view(value),
        Uint8List value => value,
        _ => null,
      };
      cleanup();

      if (bytes == null) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Browser could not decode the selected attachment.'),
          );
        }
        return;
      }

      if (!completer.isCompleted) {
        completer.complete(
          PickedRequestAttachmentFile(
            name: file.name,
            bytes: bytes,
            mimeType: file.type.isEmpty
                ? 'application/octet-stream'
                : file.type,
          ),
        );
      }
    });
    reader.onError.listen((_) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Browser could not read the selected attachment.'),
        );
      }
    });
    reader.readAsArrayBuffer(file);
  });
  input.click();

  return completer.future;
}
