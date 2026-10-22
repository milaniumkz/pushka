import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedImageFile {
  const PickedImageFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

Future<PickedImageFile?> pickWebImage() async => pickNativeImage();

Future<PickedImageFile?> pickNativeImage() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  final file = picked?.files.firstOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PickedImageFile(
    bytes: bytes,
    name: file.name,
    mimeType: _mimeType(file.extension),
  );
}

String _mimeType(String? extension) {
  return switch ((extension ?? '').toLowerCase()) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
