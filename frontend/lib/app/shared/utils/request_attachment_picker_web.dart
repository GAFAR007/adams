// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

library;

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'request_attachment_picker_types.dart';

const _allAttachmentAcceptValue =
    '.png,.jpg,.jpeg,.webp,.mp4,.mov,.webm,.pdf,.txt,.doc,.docx,image/png,image/jpeg,image/webp,video/mp4,video/quicktime,video/webm,application/pdf,text/plain,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const _imageOnlyAcceptValue =
    '.png,.jpg,.jpeg,.webp,image/png,image/jpeg,image/webp';

Future<PickedRequestAttachmentFile?> pickRequestAttachmentFile() async {
  final files = await pickRequestAttachmentFiles();
  if (files.isEmpty) {
    return null;
  }

  return files.first;
}

Future<List<PickedRequestAttachmentFile>> pickRequestAttachmentFiles({
  int maxFiles = 1,
  bool imagesOnly = false,
}) async {
  final safeMaxFiles = maxFiles < 1 ? 1 : maxFiles;
  final completer = Completer<List<PickedRequestAttachmentFile>>();
  final input = html.FileUploadInputElement()
    ..accept = imagesOnly ? _imageOnlyAcceptValue : _allAttachmentAcceptValue
    ..multiple = safeMaxFiles > 1
    ..style.display = 'none';

  html.document.body?.append(input);

  void cleanup() {
    input.remove();
  }

  Future<PickedRequestAttachmentFile?> readFile(html.File file) async {
    final completer = Completer<PickedRequestAttachmentFile?>();
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      final bytes = switch (result) {
        ByteBuffer value => Uint8List.view(value),
        Uint8List value => value,
        _ => null,
      };

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
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Browser could not read the selected attachment.'),
        );
      }
    });

    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  input.onChange.listen((_) async {
    final selectedFiles = input.files;
    if (selectedFiles == null || selectedFiles.isEmpty) {
      cleanup();
      if (!completer.isCompleted) {
        completer.complete(const <PickedRequestAttachmentFile>[]);
      }
      return;
    }

    try {
      final items = <PickedRequestAttachmentFile>[];
      final limitedFiles = selectedFiles.take(safeMaxFiles);

      for (final file in limitedFiles) {
        final pickedFile = await readFile(file);
        if (pickedFile != null) {
          items.add(pickedFile);
        }
      }

      cleanup();
      if (!completer.isCompleted) {
        completer.complete(items);
      }
    } catch (error) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  });

  input.click();

  return completer.future;
}
