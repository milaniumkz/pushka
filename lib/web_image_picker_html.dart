// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

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

Future<PickedImageFile?> pickNativeImage() => pickWebImage();

Future<PickedImageFile?> pickWebImage() {
  final completer = Completer<PickedImageFile?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false
    ..style.display = 'none';

  html.document.body?.append(input);

  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      input.remove();
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      input.remove();
      if (!completer.isCompleted) {
        completer.completeError(StateError('image_read_failed'));
      }
    });
    reader.onLoad.first.then((_) {
      input.remove();
      final result = reader.result;
      if (result is Uint8List) {
        completer.complete(
          PickedImageFile(
            bytes: result,
            name: file.name,
            mimeType: file.type.isEmpty ? 'image/jpeg' : file.type,
          ),
        );
      } else {
        completer.completeError(StateError('image_read_failed'));
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      input.remove();
      return null;
    },
  );
}
