import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushka/classifieds_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpClassifieds(
  WidgetTester tester, {
  ClassifiedsStore? store,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ClassifiedsApp(
      initialStore: store ?? seededTestStore(),
      loadLocalPreferences: false,
      installErrorWidget: false,
    ),
  );
  await tester.pumpAndSettle();
}

ClassifiedsStore seededTestStore() {
  final store = ClassifiedsStore.test();
  store.categories.addAll(const [
    ListingCategory(
      id: 'all',
      titleRu: 'Все',
      titleKk: 'Барлығы',
      iconKey: 'grid',
    ),
    ListingCategory(
      id: 'electronics',
      titleRu: 'Электроника',
      titleKk: 'Электроника',
      iconKey: 'electronics',
      subcategories: [
        ListingSubcategory(
          id: 'phones',
          titleRu: 'Телефоны',
          titleKk: 'Телефондар',
        ),
      ],
      filters: [
        ListingAttributeFilter(
          id: 'brand',
          titleRu: 'Бренд',
          titleKk: 'Бренд',
          options: ['Apple', 'Samsung', 'Xiaomi'],
        ),
      ],
    ),
    ListingCategory(
      id: 'home',
      titleRu: 'Дом и сад',
      titleKk: 'Үй және бақ',
      iconKey: 'home',
    ),
  ]);
  store.locations.addAll(const [
    ListingLocation(
      id: 'cities',
      regionRu: 'Города',
      regionKk: 'Қалалар',
      cities: ['Алматы', 'Астана'],
    ),
  ]);
  store.listings.addAll([
    ListingAd(
      id: 'iphone',
      ownerId: 'seller_1',
      ownerName: 'Алихан',
      phone: '+7 (701) 555-22-11',
      title: 'iPhone 15 Pro 256 GB',
      description:
          'Состояние отличное, полный комплект, батарея 94%. Торг уместен.',
      categoryId: 'electronics',
      city: 'Алматы',
      district: 'Бостандыкский район',
      price: 489000,
      condition: ListingCondition.used,
      images: const ['https://example.com/electronics.png'],
      status: ListingStatus.active,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      views: 184,
      favoriteCount: 12,
      topUntil: DateTime.now().add(const Duration(days: 5)),
    ),
    ListingAd(
      id: 'sofa',
      ownerId: 'seller_2',
      ownerName: 'Мария',
      phone: '+7 (777) 333-44-55',
      title: 'Диван серый раскладной',
      description:
          'Аккуратный диван для гостиной, самовывоз сегодня или завтра.',
      categoryId: 'home',
      city: 'Астана',
      district: 'Есиль',
      price: 85000,
      condition: ListingCondition.used,
      images: const ['https://example.com/home.png'],
      status: ListingStatus.active,
      createdAt: DateTime.now().subtract(const Duration(hours: 7)),
      views: 91,
    ),
  ]);
  store.promotionPlans.addAll(const [
    PromotionPlan(
      id: 'boost',
      title: 'Поднять',
      caption: 'Поднять объявление в выдаче на 7 дней',
      price: 990,
      days: 7,
    ),
    PromotionPlan(
      id: 'top',
      title: 'ТОП',
      caption: 'Показ в блоке ТОП объявлений на 7 дней',
      price: 2490,
      days: 7,
    ),
  ]);
  return store;
}

Future<void> signIn(
  WidgetTester tester, {
  String phone = '+7 (777) 111-22-33',
}) async {
  await tester.tap(find.byIcon(Icons.person_outline_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('classifiedsOpenAuthButton')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('classifiedsPhoneField')),
    phone,
  );
  await tester.tap(find.byKey(const ValueKey('classifiedsRequestOtpButton')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('classifiedsOtpField')),
    phone == ownerPhone ? ownerCode : '3718',
  );
  await tester.tap(find.byKey(const ValueKey('classifiedsVerifyOtpButton')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('phone formatter keeps second seven as subscriber digit', () {
    const formatter = KazakhstanPhoneFormatter();
    final first = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(text: '7'),
    );
    expect(first.text, '+7');

    final second = formatter.formatEditUpdate(
      first,
      const TextEditingValue(text: '+77'),
    );
    expect(second.text, '+7 (7');

    final third = formatter.formatEditUpdate(
      second,
      const TextEditingValue(text: '+7 (77'),
    );
    expect(third.text, '+7 (77');

    final pasted = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(text: '770535345345'),
    );
    expect(pasted.text, '+7 (705) 353-45-34');
  });

  testWidgets('guest sees classifieds home and inspection notebook', (tester) async {
    await pumpClassifieds(tester);

    expect(find.text('PUSHKA'), findsWidgets);
    expect(find.text('Главная'), findsWidgets);
    expect(find.text('Категории'), findsWidgets);
    expect(find.text('Добавить'), findsWidgets);
    expect(find.text('Мой блокнот осмотров'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ТОП объявления'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('ТОП объявления'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Свежие объявления'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Свежие объявления'), findsOneWidget);
    expect(find.textContaining('iPhone 15 Pro'), findsWidgets);
  });

  testWidgets('category button filters listings', (tester) async {
    final store = seededTestStore();
    await pumpClassifieds(tester, store: store);

    await tester.tap(find.byIcon(Icons.grid_view_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом и сад'));
    await tester.pumpAndSettle();

    expect(store.selectedCategoryId, 'home');
    expect(
      store.publicListings.any((item) => item.title.contains('Диван')),
      isTrue,
    );
  });

  test('AI moderation approves, rejects, and escalates', () async {
    final store = seededTestStore()
      ..isAuthorized = true
      ..userId = 'u1'
      ..phone = '+7 (777) 111-22-33';

    final approved = await store.createListing(
      title: 'Ноутбук Lenovo IdeaPad',
      description:
          'Хорошее состояние, зарядка в комплекте, можно проверить на месте.',
      categoryId: 'electronics',
      city: 'Алматы',
      district: 'Ауэзовский',
      price: 180000,
      condition: ListingCondition.used,
      images: const ['https://example.com/electronics.png'],
    );
    expect(approved.status, ListingStatus.active);

    final rejected = await store.createListing(
      title: 'Запрещенное оружие',
      description: 'Описание запрещенного товара для проверки модерации.',
      categoryId: 'services',
      city: 'Алматы',
      district: 'Центр',
      price: 1000,
      condition: ListingCondition.used,
      images: const ['https://example.com/electronics.png'],
    );
    expect(rejected.status, ListingStatus.rejected);

    final risky = await store.createListing(
      title: 'Дом',
      description: 'Срочно',
      categoryId: 'real_estate',
      city: 'Алматы',
      district: 'Центр',
      price: 45000000,
      condition: ListingCondition.used,
      images: const [],
    );
    expect(risky.status, ListingStatus.rejected);
  });

  test('banner pending payment status is not active', () {
    final status = statusFromString('pending_payment');

    expect(status, ListingStatus.pendingPayment);
    expect(
      UserBannerAd(
        id: 'b1',
        ownerId: 'u1',
        title: 'Баннер',
        caption: 'Описание баннера',
        imageUrl: 'https://example.com/banner.png',
        status: status,
        createdAt: DateTime.now(),
      ).isActiveBanner,
      isFalse,
    );
  });

  test('favorites and chats require authorized user', () async {
    final store = seededTestStore();
    final listing = store.listings.first;

    expect(store.toggleFavorite(listing.id), isFalse);
    expect(store.openChat(listing), throwsStateError);

    store
      ..isAuthorized = true
      ..userId = 'buyer_1'
      ..phone = '+7 (777) 111-22-33';

    expect(store.toggleFavorite(listing.id), isTrue);
    final chat = await store.openChat(listing);
    store.sendMessage(chat, 'Здравствуйте, объявление актуально?');

    expect(store.favoriteIds, contains(listing.id));
    expect(chat.messages.length, 1);
    store.reportMessage(chat, chat.messages.first, 'Подозрительное сообщение');
    expect(store.moderationCases.last.type, 'message');
    await store.loadChatsFromFirebase();
    expect(store.chats, isNotEmpty);
  });

  test('saved searches and listing views work locally', () async {
    final store = seededTestStore()
      ..isAuthorized = true
      ..userId = 'u1'
      ..phone = '+7 (777) 111-22-33';
    final listing = store.listings.first;

    store.setSearch('iphone');
    store.applyFilters(
      min: 1000,
      max: 900000,
      withPhoto: true,
      promoted: false,
      negotiable: true,
      condition: 'used',
      categoryId: 'electronics',
      subcategoryId: 'phones',
      city: 'Алматы',
      sort: 'newest',
      attributes: const {'brand': 'Apple'},
    );
    await store.saveCurrentSearch();
    expect(store.savedSearches.length, 1);

    store.setSearch('');
    store.applySavedSearch(store.savedSearches.first);
    expect(store.searchQuery, 'iphone');
    expect(store.selectedAttributeFilters['brand'], 'Apple');

    final views = listing.views;
    store.trackListingView(listing.id);
    expect(listing.views, views + 1);
  });

  test('owner otp fallback sets owner role in test mode', () async {
    final store = seededTestStore();
    await store.requestOtp(ownerPhone);
    final ok = await store.verifyOtp(ownerCode);
    expect(ok, isTrue);
    expect(store.isOwner, isTrue);
  });

  test(
    'first release rejects promotion purchases before contacting Firebase',
    () async {
      final store = seededTestStore()..isAuthorized = true;
      expect(paidPromotionEnabled, isFalse);
      await expectLater(
        store.purchasePromotion(
          store.listings.first,
          store.promotionPlans.first,
        ),
        throwsStateError,
      );
    },
  );

  test('demo sign in displays a code and never requires Firebase', () async {
    final store = ClassifiedsStore.demo();
    await store.requestOtp('+7 (700) 000-00-01');
    expect(store.pendingOtpCode, isNotNull);
    expect(await store.verifyOtp('9999'), isFalse);
    expect(await store.verifyOtp(store.pendingOtpCode!), isTrue);
    expect(store.isOwner, isFalse);
    expect(store.listings, isNotEmpty);
  });

  testWidgets(
    'account deletion requires confirmation and clears personal state',
    (tester) async {
      final store = seededTestStore()
        ..isAuthorized = true
        ..userId = 'seller_1'
        ..phone = '+7 (700) 000-00-01';
      await tester.pumpWidget(
        ClassifiedsScope(
          controller: store,
          child: const MaterialApp(home: DeleteAccountScreen()),
        ),
      );
      await tester.tap(find.text('Удалить аккаунт и данные'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.isAuthorized, isTrue);
      expect(store.myListings, isNotEmpty);
      await tester.tap(find.text('Удалить аккаунт и данные'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить', skipOffstage: false));
      await tester.pumpAndSettle();
      expect(store.isAuthorized, isFalse);
      expect(store.phone, isEmpty);
      expect(
        store.listings.any((listing) => listing.ownerId == 'seller_1'),
        isFalse,
      );
      expect(
        store.listings.any((listing) => listing.ownerId == 'seller_2'),
        isTrue,
      );
    },
  );

  testWidgets('owner opens moderation dashboard through same auth flow', (
    tester,
  ) async {
    final store = seededTestStore();
    await pumpClassifieds(tester, store: store);
    await signIn(tester, phone: ownerPhone);

    expect(store.isOwner, isTrue);
    expect(find.text('Панель владельца'), findsOneWidget);
    expect(find.text('Очередь модерации'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Тарифы продвижения'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Тарифы продвижения'), findsOneWidget);
  });
}
