import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:pushka/classifieds_app.dart';
import 'widget_test.dart' show seededTestStore;

class BatchPicker extends ImagePickerPlatform {
  int calls = 0;
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    calls++;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jHn0AAAAASUVORK5CYII=',
    );
    return List.generate(
      3,
      (i) => XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'photo$i.png',
        path: '/virtual/photo$i.png',
        mimeType: 'image/png',
      ),
    );
  }
}

class PhotoStore extends ClassifiedsStore {
  PhotoStore() : super.test();
  final uploaded = <String>[];
  @override
  Future<String> uploadImage(XFile image, String folder) async {
    uploaded.add(image.name);
    return 'https://example.com/${image.name}';
  }
}

void main() {
  testWidgets('one selection uploads all photos and saves the listing', (
    tester,
  ) async {
    final previous = ImagePickerPlatform.instance;
    final picker = BatchPicker();
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previous);
    final seed = seededTestStore();
    final store = PhotoStore()
      ..isAuthorized = true
      ..userId = 'seller_1'
      ..phone = '+77771112233';
    store.categories.addAll(seed.categories);
    store.locations.addAll(seed.locations);
    store.listings.addAll(seed.listings);
    final listing = store.listings.first..images = [];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ClassifiedsScope(
        controller: store,
        child: MaterialApp(
          home: Scaffold(body: CreateListingScreen(editingListing: listing)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final photos = find.text('Фото (0/8)');
    await tester.ensureVisible(photos);
    await tester.pumpAndSettle();
    await tester.tap(photos);
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('Фото (3/8)'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Сохранить изменения');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.uploaded, ['photo0.png', 'photo1.png', 'photo2.png']);
    expect(listing.images, hasLength(3));
    expect(find.text('Объявление обновлено'), findsOneWidget);
    expect(listing.status, isNot(ListingStatus.rejected));
  });
}
