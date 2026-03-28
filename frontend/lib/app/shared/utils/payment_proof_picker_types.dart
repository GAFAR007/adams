library;

class PickedPaymentProofFile {
  const PickedPaymentProofFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String mimeType;
}
