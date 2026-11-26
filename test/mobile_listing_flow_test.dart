import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushka/classifieds_app.dart';

import 'widget_test.dart' show pumpClassifieds, seededTestStore;

class SubmissionStore extends ClassifiedsStore {
  SubmissionStore({this.resultStatus = ListingStatus.ownerReview}) : super.test() {
    final seed = seededTestStore();
    categories.addAll(seed.categories);
    locations.addAll(seed.locations);
    isAuthorized = true;
    userId = 'seller';
    phone = '+7 (777) 111-22-33';
    selectedTab = 2;
  }

  final ListingStatus resultStatus;
  int submissions = 0;

  @override
  Future<ListingAd> createListing({
    required String title,
    required String description,
    required String categoryId,
    required String city,
    String regionId = '',
    required String district,
    required int price,
    required ListingCondition condition,
    required List<String> images,
    Map<String, String> attributes = const {},
  }) async {
    submissions++;
    final listing = ListingAd(
      id: 'submitted',
      ownerId: userId,
      ownerName: userName,
      phone: phone,
      title: title,
      description: description,
      categoryId: categoryId,
      city: city,
      district: district,
      price: price,
      condition: condition,
      images: images,
      attributes: attributes,
      status: resultStatus,
      createdAt: DateTime(2026, 1, 1),
      rejectionReasonRu: resultStatus == ListingStatus.rejected
          ? 'Исправьте описание объявления.'
          : '',
    );
    listings.insert(0, listing);
    notifyListeners();
    return listing;
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> fillAndSubmit(WidgetTester tester) async {
  await tester.ensureVisible(field('Название'));
  await tester.enterText(field('Название'), 'Телефон в хорошем состоянии');
  await tester.ensureVisible(field('Описание'));
  await tester.enterText(field('Описание'), 'Полный комплект, можно проверить.');
  final submit = find.widgetWithText(FilledButton, 'Опубликовать');
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> pumpPhotoFrames(WidgetTester tester) async {
  // Alternate fake frames and real I/O for the platform-picker fixtures.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}

void main() {
  testWidgets('iOS numeric keyboard can be dismissed with Done', (tester) async {
    final store = SubmissionStore();
    await pumpClassifieds(tester, store: store);
    await tester.ensureVisible(field('Цена, ₸'));
    await tester.showKeyboard(field('Цена, ₸'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const ValueKey('dismissKeyboardButton')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    final editable = tester.widget<EditableText>(
      find.descendant(of: field('Цена, ₸'), matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isFalse);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('iOS form dismisses keyboard on outside tap and drag', (tester) async {
    await pumpClassifieds(tester, store: SubmissionStore());
    await tester.ensureVisible(field('Название'));
    await tester.showKeyboard(field('Название'));
    await tester.tap(find.byType(CSectionAppBar));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.showKeyboard(field('Название'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('main sections have working back arrows', (tester) async {
    final store = SubmissionStore()..selectedTab = 0;
    await pumpClassifieds(tester, store: store);
    for (final tab in [1, 2, 3, 4]) {
      store.selectTab(tab);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sectionBackButton')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sectionBackButton')));
      await tester.pumpAndSettle();
      expect(store.selectedTab, 0);
    }
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('editing route has a back arrow to My listings', (tester) async {
    final store = seededTestStore()
      ..isAuthorized = true
      ..userId = 'seller_1';
    store.listings.first.images = [];
    await tester.pumpWidget(
      ClassifiedsScope(
        controller: store,
        child: const MaterialApp(home: MyListingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Редактировать'));
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sectionBackButton')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sectionBackButton')));
    await tester.pumpAndSettle();
    expect(find.byType(MyListingsScreen), findsOneWidget);
    expect(find.byType(CreateListingScreen), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('OK opens My listings and never restores the draft keyboard', (tester) async {
    final store = SubmissionStore();
    await pumpClassifieds(tester, store: store);
    await fillAndSubmit(tester);
    expect(find.text('Объявление отправлено'), findsOneWidget);
    expect(store.submissions, 1);
    expect(store.selectedTab, 2);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    expect(find.byType(MyListingsScreen), findsOneWidget);
    expect(find.byType(CreateListingScreen), findsNothing);
    expect(store.selectedTab, 4);
    expect(store.myListings.single.id, 'submitted');
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ClassifiedsProfileScreen), findsOneWidget);
    expect(find.byType(CreateListingScreen), findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('rejected submission stays in the form for correction', (tester) async {
    final store = SubmissionStore(resultStatus: ListingStatus.rejected);
    await pumpClassifieds(tester, store: store);
    await fillAndSubmit(tester);
    expect(find.text('Объявление отправлено'), findsNothing);
    expect(find.byType(CreateListingScreen), findsOneWidget);
    expect(store.selectedTab, 2);
    expect(find.text('Исправьте описание объявления.'), findsWidgets);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('multiple picked photos can be removed and replaced at the limit', (tester) async {
    late Directory directory;
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAEElEQVR4AQEFAPr/AP////8J+wP9o9FJCgAAAABJRU5ErkJggg==',
    );
    final paths = <String>[];
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('pushka-photo-test');
      for (var i = 0; i < 9; i++) {
        final file = File('${directory.path}/photo-$i.png');
        await file.writeAsBytes(png);
        paths.add(file.path);
      }
    });
    addTearDown(() => directory.delete(recursive: true));
    final selections = [paths.take(8).toList(), [paths.last]];
    var pickerCalls = 0;
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickMultiImage');
      pickerCalls++;
      return selections.removeAt(0);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await pumpClassifieds(tester, store: SubmissionStore());
    var button = find.widgetWithText(OutlinedButton, 'Фото (0/8)');
    await tester.ensureVisible(button);
    await pumpPhotoFrames(tester);
    await tester.tap(button);
    await pumpPhotoFrames(tester);
    expect(pickerCalls, 1);
    expect(tester.widget<ImagePreviewStrip>(find.byType(ImagePreviewStrip)).images.length, 8);
    expect(tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Фото (8/8)')).onPressed, isNull);

    await tester.ensureVisible(find.byType(ImagePreviewStrip));
    await pumpPhotoFrames(tester);
    await tester.tap(find.descendant(
      of: find.byType(ImagePreviewStrip),
      matching: find.byType(PhotoRemoveButton),
    ).first);
    await pumpPhotoFrames(tester);
    expect(tester.widget<ImagePreviewStrip>(find.byType(ImagePreviewStrip)).images.length, 7);
    button = find.widgetWithText(OutlinedButton, 'Фото (7/8)');
    await tester.ensureVisible(button);
    await pumpPhotoFrames(tester);
    await tester.tap(button);
    await pumpPhotoFrames(tester);
    final selected = tester.widget<ImagePreviewStrip>(find.byType(ImagePreviewStrip)).images;
    expect(pickerCalls, 2);
    expect(selected.length, 8);
    expect(selected.any((image) => image.path == paths.first), isFalse);
    expect(selected.any((image) => image.path == paths.last), isTrue);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('existing photo removal is saved only on confirmation', (tester) async {
    final store = seededTestStore()
      ..isAuthorized = true
      ..userId = 'seller_1';
    final listing = store.listings.first
      ..images = ['assets/brand/pushka_logo.png'];
    await tester.pumpWidget(
      ClassifiedsScope(
        controller: store,
        child: MaterialApp(home: CreateListingScreen(editingListing: listing)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ExistingImageStrip));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Удалить фото'));
    await tester.pumpAndSettle();
    expect(find.byType(ExistingImageStrip), findsNothing);
    expect(find.text('Фото (0/8)'), findsOneWidget);
    expect(listing.images, hasLength(1));
    final save = find.widgetWithText(FilledButton, 'Сохранить изменения');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(listing.images, isEmpty);
    expect(find.text('Объявление обновлено'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

  test('two devices remove archived public listing without refresh and preserve its date', () async {
    final public = StreamController<List<ListingAd>>.broadcast();
    final own = StreamController<List<ListingAd>>.broadcast();
    final first = SubmissionStore();
    final second = SubmissionStore();
    addTearDown(() async {
      first.dispose();
      second.dispose();
      await public.close();
      await own.close();
    });
    first.watchListingFeeds(publicFeed: public.stream, ownFeed: own.stream);
    second.watchListingFeeds(publicFeed: public.stream, ownFeed: own.stream);
    final date = DateTime(2025, 12, 1);
    ListingAd record(ListingStatus status) => ListingAd(
      id: 'shared', ownerId: 'seller', ownerName: 'Продавец', phone: '',
      title: 'Объявление', description: 'Описание', categoryId: 'phones',
      city: 'Алматы', district: '', price: 1000,
      condition: ListingCondition.used, images: const [],
      status: status, createdAt: date,
    );
    public.add([record(ListingStatus.active)]);
    own.add([record(ListingStatus.active)]);
    await Future<void>.delayed(Duration.zero);
    for (final store in [first, second]) {
      expect(store.listings, hasLength(1));
      expect(store.publicListings, hasLength(1));
      expect(store.listings.single.createdAt, date);
    }
    own.add([record(ListingStatus.archived)]);
    public.add([]);
    await Future<void>.delayed(Duration.zero);
    for (final store in [first, second]) {
      expect(store.publicListings, isEmpty);
      expect(store.myListings.single.status, ListingStatus.archived);
      expect(store.myListings.single.createdAt, date);
    }
    own.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(first.listings, isEmpty);
    expect(second.listings, isEmpty);
  });

  test('stream errors retain cached listings and disposal detaches listeners', () async {
    final feed = StreamController<List<ListingAd>>();
    final store = seededTestStore();
    final cached = store.listings.first;
    store.watchListingFeeds(publicFeed: feed.stream);
    feed.add([cached]);
    await Future<void>.delayed(Duration.zero);
    feed.addError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(store.listings.single.id, cached.id);
    expect(store.firebaseLoadError, contains('offline'));
    store.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(feed.hasListener, isFalse);
    await feed.close();
  });

  test('account switch cancels old private feeds immediately', () async {
    final public = StreamController<List<ListingAd>>.broadcast();
    final own = StreamController<List<ListingAd>>.broadcast();
    final store = SubmissionStore();
    store.watchListingFeeds(publicFeed: public.stream, ownFeed: own.stream);
    final private = ListingAd(
      id: 'private', ownerId: 'seller', ownerName: '', phone: '',
      title: 'Архив', description: '', categoryId: 'phones', city: 'Алматы',
      district: '', price: 0, condition: ListingCondition.used, images: const [],
      status: ListingStatus.archived, createdAt: DateTime(2026),
    );
    own.add([private]);
    await Future<void>.delayed(Duration.zero);
    expect(store.myListings, hasLength(1));
    store.logout();
    own.add([private]);
    await Future<void>.delayed(Duration.zero);
    expect(store.listings.where((item) => item.id == 'private'), isEmpty);
    store.dispose();
    await public.close();
    await own.close();
  });

  testWidgets('open details show an unavailable state after live deletion', (tester) async {
    final store = seededTestStore();
    final listing = store.listings.first;
    final feed = StreamController<List<ListingAd>>();
    addTearDown(() async {
      store.dispose();
      await feed.close();
    });
    await tester.pumpWidget(
      ClassifiedsScope(
        controller: store,
        child: MaterialApp(home: ListingDetailsScreen(listingId: listing.id)),
      ),
    );
    await tester.pumpAndSettle();
    store.watchListingFeeds(publicFeed: feed.stream);
    feed.add([]);
    await tester.pumpAndSettle();
    expect(find.text('Объявление недоступно'), findsOneWidget);
    expect(find.text('Позвонить'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
