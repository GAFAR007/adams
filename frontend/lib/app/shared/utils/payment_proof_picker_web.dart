// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

library;

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'payment_proof_picker_types.dart';

Future<PickedPaymentProofFile?> pickPaymentProofFile() async {
  final completer = Completer<PickedPaymentProofFile?>();
  final input = html.FileUploadInputElement()
    ..accept = '.png,.jpg,.jpeg,.pdf,image/png,image/jpeg,application/pdf';

  input.onChange.listen((_) {
    final file = input.files?.first;
    if (file == null) {
      completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is! ByteBuffer) {
        completer.complete(null);
        return;
      }

      completer.complete(
        PickedPaymentProofFile(
          name: file.name,
          bytes: Uint8List.view(result),
          mimeType: file.type.isEmpty ? 'application/octet-stream' : file.type,
        ),
      );
    });
    reader.onError.listen((_) => completer.complete(null));
    reader.readAsArrayBuffer(file);
  });
  input.click();

  return completer.future;
}
