library;

class PickedRequestAttachmentFile {
  const PickedRequestAttachmentFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String mimeType;
}
