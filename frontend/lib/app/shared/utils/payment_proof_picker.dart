library;

import 'payment_proof_picker_stub.dart'
    if (dart.library.js_interop) 'payment_proof_picker_web.dart'
    as impl;
import 'payment_proof_picker_types.dart';

Future<PickedPaymentProofFile?> pickPaymentProofFile() {
  return impl.pickPaymentProofFile();
}
