// ignore_for_file: deprecated_member_use, invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'local_preferences.dart';
import 'payment_view.dart';
import 'web_image_picker.dart';

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNullC => isEmpty ? null : first;
}

const cBlue = Color(0xFF0647C6);
const cDeepBlue = Color(0xFF052B7F);
const cNavy = Color(0xFF071327);
const cMuted = Color(0xFF7C879A);
const cLine = Color(0xFFE4EAF3);
const cBg = Color(0xFFFAFCFF);
const cSoftBlue = Color(0xFFEAF2FF);
const cGreen = Color(0xFF16AA58);
const cOrange = Color(0xFFFFB21A);
const cShadow = Color(0x1A8EA2C0);

const ownerPhone = '+7 (000) 000-00-00';
const ownerCode = '1234';
const paidPromotionEnabled = false;
const demoAuthenticationEnabled = bool.fromEnvironment('PUSHKA_DEMO_AUTH');

bool get isAdminHostingHost {
  final host = Uri.base.host.toLowerCase();
  return host == 'pushka-admin-f4e4f.web.app' ||
      host == 'pushka-admin-f4e4f.firebaseapp.com' ||
      host.startsWith('admin.');
}

enum ClassifiedsLanguage { ru, kk }

enum ListingStatus {
  draft,
  moderation,
  pendingPayment,
  active,
  rejected,
  ownerReview,
  archived,
  deleted,
}

enum ModerationDecision { approved, rejected, ownerReview }

enum ListingCondition { newItem, used, broken }

String cTr(ClassifiedsLanguage language, String ru, String kk) {
  return language == ClassifiedsLanguage.ru ? ru : kk;
}

String cMoney(int value) {
  if (value <= 0) {
    return 'Договорная';
  }
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < raw.length; index += 1) {
    final left = raw.length - index;
    buffer.write(raw[index]);
    if (left > 1 && left % 3 == 1) {
      buffer.write(' ');
    }
  }
  return '${buffer.toString()} ₸';
}

String listingStatusMessage(ListingStatus status) {
  return switch (status) {
    ListingStatus.active => 'Объявление опубликовано',
    ListingStatus.pendingPayment => 'Ожидает оплаты',
    ListingStatus.rejected => 'Объявление отклонено',
    ListingStatus.ownerReview ||
    ListingStatus.moderation => 'Объявление отправлено на проверку',
    ListingStatus.archived => 'Объявление в архиве',
    ListingStatus.deleted => 'Удалено владельцем',
    ListingStatus.draft => 'Черновик сохранён',
  };
}

String cFriendlyError(Object error) {
  final text = error.toString();
  if (text.contains('user_banned')) {
    return 'Аккаунт временно заблокирован. Обратитесь в поддержку или к владельцу приложения.';
  }
  if (text.contains('auth_required') || text.contains('unauthenticated')) {
    return 'Для продолжения нужно войти в аккаунт.';
  }
  if (text.contains('profile_required')) {
    return 'Заполните профиль перед публикацией объявления.';
  }
  if (text.contains('location_required')) {
    return 'Выберите область и город из списка.';
  }
  if (text.contains('listing_required_fields')) {
    return 'Заполните все обязательные поля объявления.';
  }
  if (text.contains('listing_not_found')) {
    return 'Объявление недоступно или уже снято с публикации.';
  }
  if (text.contains('chat_forbidden')) {
    return 'Нет доступа к этому чату.';
  }
  if (text.contains('internal')) {
    return 'Не удалось открыть чат. Попробуйте обновить страницу и повторить.';
  }
  if (text.contains('storage_url_forbidden')) {
    return 'Фото не загружено. Попробуйте выбрать фото заново.';
  }
  return text.replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
}

String normalizePhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    return '+7${digits.substring(1)}';
  }
  if (digits.length == 11 && digits.startsWith('7')) {
    return '+$digits';
  }
  if (digits.length == 10) {
    return '+7$digits';
  }
  return value.startsWith('+') ? value : '+$digits';
}

String prettyPhone(String value) {
  final normalized = normalizePhone(value);
  final digits = normalized.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 11) {
    return value;
  }
  return '+7 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7, 9)}-${digits.substring(9, 11)}';
}

class KazakhstanPhoneFormatter extends TextInputFormatter {
  const KazakhstanPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    var rawDigits = rawText.replaceAll(RegExp(r'\D'), '');
    if (rawDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    if (rawDigits.startsWith('8')) {
      rawDigits = '7${rawDigits.substring(1)}';
    }

    final hasFormattedCountryPrefix =
        rawText.trimLeft().startsWith('+7') ||
        oldValue.text.trimLeft().startsWith('+7');
    var digits = rawDigits;
    final isStartingWithCountryCode =
        oldValue.text.isEmpty && rawDigits.length == 1 && rawDigits == '7';
    final isPastedFullNumber =
        rawDigits.length >= 11 && rawDigits.startsWith('7');
    if (isStartingWithCountryCode) {
      digits = '';
    } else if (hasFormattedCountryPrefix && rawDigits.startsWith('7')) {
      digits = rawDigits.substring(1);
    } else if (isPastedFullNumber) {
      digits = rawDigits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);
    if (digits.isEmpty) {
      return TextEditingValue(
        text: '+7',
        selection: const TextSelection.collapsed(offset: 2),
      );
    }

    final buffer = StringBuffer('+7');
    if (digits.isNotEmpty) {
      buffer.write(' (');
      buffer.write(digits.substring(0, min(3, digits.length)));
      if (digits.length >= 3) buffer.write(')');
    }
    if (digits.length > 3) {
      buffer.write(' ');
      buffer.write(digits.substring(3, min(6, digits.length)));
    }
    if (digits.length > 6) {
      buffer.write('-');
      buffer.write(digits.substring(6, min(8, digits.length)));
    }
    if (digits.length > 8) {
      buffer.write('-');
      buffer.write(digits.substring(8, min(10, digits.length)));
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

Uri phoneUri(String value) {
  return Uri(scheme: 'tel', path: normalizePhone(value));
}

Uri whatsAppUri(String value) {
  final digits = normalizePhone(value).replaceAll(RegExp(r'\D'), '');
  return Uri.parse('https://wa.me/$digits');
}

User? firebaseAuthUserOrNull() {
  try {
    return FirebaseAuth.instance.currentUser;
  } catch (_) {
    return null;
  }
}

String uploadErrorMessage(Object error) {
  if (error is FirebaseException) {
    if (error.plugin == 'firebase_storage') {
      return switch (error.code) {
        'unauthorized' =>
          'Нет доступа к загрузке фото. Выйдите и войдите заново.',
        'canceled' => 'Загрузка фото отменена.',
        'quota-exceeded' => 'Лимит хранилища Firebase исчерпан.',
        _ => 'Не удалось загрузить фото: ${error.message ?? error.code}',
      };
    }
    return error.message ?? error.code;
  }
  if ('$error'.contains('empty_image')) {
    return 'Файл пустой. Выберите другое фото.';
  }
  return 'Не удалось загрузить фото. Попробуйте выбрать фото заново.';
}

void logAnalyticsEvent(String name, [Map<String, Object>? parameters]) {
  try {
    unawaited(
      FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters),
    );
  } catch (_) {
    // Analytics must never block the main user flow.
  }
}

class ListingCategory {
  const ListingCategory({
    required this.id,
    required this.titleRu,
    required this.titleKk,
    required this.iconKey,
    this.isActive = true,
    this.subcategories = const [],
    this.filters = const [],
  });

  final String id;
  final String titleRu;
  final String titleKk;
  final String iconKey;
  final bool isActive;
  final List<ListingSubcategory> subcategories;
  final List<ListingAttributeFilter> filters;

  IconData get icon => iconForCategory(iconKey);

  String title(ClassifiedsLanguage language) => cTr(language, titleRu, titleKk);
}

class ListingSubcategory {
  const ListingSubcategory({
    required this.id,
    required this.titleRu,
    required this.titleKk,
  });

  final String id;
  final String titleRu;
  final String titleKk;

  String title(ClassifiedsLanguage language) => cTr(language, titleRu, titleKk);
}

class ListingAttributeFilter {
  const ListingAttributeFilter({
    required this.id,
    required this.titleRu,
    required this.titleKk,
    required this.options,
  });

  final String id;
  final String titleRu;
  final String titleKk;
  final List<String> options;

  String title(ClassifiedsLanguage language) => cTr(language, titleRu, titleKk);
}

class ListingLocation {
  const ListingLocation({
    required this.id,
    required this.regionRu,
    required this.regionKk,
    required this.cities,
  });

  final String id;
  final String regionRu;
  final String regionKk;
  final List<String> cities;

  String region(ClassifiedsLanguage language) =>
      cTr(language, regionRu, regionKk);
}

class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.city,
    required this.role,
    required this.status,
    required this.sellerType,
    required this.violationCount,
    required this.bannedReasonRu,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final String city;
  final String role;
  final String status;
  final String sellerType;
  final int violationCount;
  final String bannedReasonRu;
  final DateTime createdAt;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.userId,
    required this.userName,
    required this.phone,
    required this.subject,
    required this.message,
    required this.status,
    required this.ownerReply,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String phone;
  final String subject;
  final String message;
  final String status;
  final String ownerReply;
  final DateTime createdAt;
}

class OwnerReport {
  const OwnerReport({
    required this.id,
    required this.reporterId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.type = 'listing',
    this.listingId = '',
    this.chatId = '',
    this.messageId = '',
    this.reportedUserId = '',
  });

  final String id;
  final String reporterId;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String type;
  final String listingId;
  final String chatId;
  final String messageId;
  final String reportedUserId;
}

class SavedSearch {
  SavedSearch({
    required this.id,
    required this.title,
    required this.query,
    required this.categoryId,
    required this.subcategoryId,
    required this.city,
    required this.minPrice,
    required this.maxPrice,
    required this.condition,
    required this.sortMode,
    required this.attributes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String query;
  final String categoryId;
  final String subcategoryId;
  final String city;
  final int minPrice;
  final int maxPrice;
  final String condition;
  final String sortMode;
  final Map<String, String> attributes;
  final DateTime createdAt;
}

class ListingAd {
  ListingAd({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.phone,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.city,
    required this.district,
    required this.price,
    required this.condition,
    required this.images,
    required this.status,
    required this.createdAt,
    this.sellerType = 'private',
    this.attributes = const {},
    this.rejectionReasonRu = '',
    this.rejectionReasonKk = '',
    this.views = 0,
    this.favoriteCount = 0,
    this.boostUntil,
    this.topUntil,
    this.vipUntil,
    this.archivedAt,
    this.restoreUntil,
  });

  final String id;
  final String ownerId;
  String ownerName;
  String phone;
  String title;
  String description;
  String categoryId;
  String city;
  String district;
  int price;
  ListingCondition condition;
  List<String> images;
  ListingStatus status;
  DateTime createdAt;
  String sellerType;
  Map<String, String> attributes;
  String rejectionReasonRu;
  String rejectionReasonKk;
  int views;
  int favoriteCount;
  DateTime? boostUntil;
  DateTime? topUntil;
  DateTime? vipUntil;
  DateTime? archivedAt;
  DateTime? restoreUntil;

  bool get isPromoted {
    final now = DateTime.now();
    return (topUntil?.isAfter(now) ?? false) ||
        (vipUntil?.isAfter(now) ?? false) ||
        (boostUntil?.isAfter(now) ?? false);
  }

  bool get isPublic => status == ListingStatus.active;

  bool get isBusiness => sellerType == 'business';

  bool get canRestoreFromArchive =>
      status == ListingStatus.archived &&
      restoreUntil != null &&
      restoreUntil!.isAfter(DateTime.now());
}

class UserBannerAd {
  UserBannerAd({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.caption,
    required this.imageUrl,
    required this.status,
    required this.createdAt,
    this.activeUntil,
    this.rejectionReasonRu = '',
  });

  final String id;
  final String ownerId;
  String title;
  String caption;
  String imageUrl;
  ListingStatus status;
  DateTime createdAt;
  DateTime? activeUntil;
  String rejectionReasonRu;

  bool get isActiveBanner =>
      status == ListingStatus.active &&
      activeUntil != null &&
      activeUntil!.isAfter(DateTime.now());
}

class PromotionPlan {
  const PromotionPlan({
    required this.id,
    required this.title,
    required this.caption,
    required this.price,
    required this.days,
    this.titleKk = '',
    this.captionKk = '',
    this.isActive = true,
  });

  final String id;
  final String title;
  final String titleKk;
  final String caption;
  final String captionKk;
  final int price;
  final int days;
  final bool isActive;

  String localizedTitle(ClassifiedsLanguage language) =>
      cTr(language, title, titleKk.isEmpty ? title : titleKk);

  String localizedCaption(ClassifiedsLanguage language) =>
      cTr(language, caption, captionKk.isEmpty ? caption : captionKk);
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.imageUrl = '',
    this.fileUrl = '',
    this.fileName = '',
    this.flagged = false,
    this.deleted = false,
  });

  final String id;
  final String senderId;
  String text;
  final DateTime createdAt;
  String imageUrl;
  String fileUrl;
  String fileName;
  bool flagged;
  bool deleted;
}

class ChatThread {
  ChatThread({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.title,
    required this.messages,
  });

  final String id;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final String title;
  final List<ChatMessage> messages;
}

class ModerationCase {
  ModerationCase({
    required this.id,
    required this.type,
    required this.targetId,
    required this.title,
    required this.reasonRu,
    required this.reasonKk,
    required this.riskScore,
    required this.createdAt,
    this.resolved = false,
  });

  final String id;
  final String type;
  final String targetId;
  final String title;
  final String reasonRu;
  final String reasonKk;
  final double riskScore;
  final DateTime createdAt;
  bool resolved;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.text,
    required this.isRead,
    required this.createdAt,
    this.type = '',
    this.data = const {},
    this.resolved = false,
  });

  final String id;
  final String userId;
  final String text;
  final bool isRead;
  final DateTime createdAt;
  final String type;
  final Map<String, String> data;
  final bool resolved;
}

class OwnerStats {
  const OwnerStats({
    this.users = 0,
    this.listings = 0,
    this.activeListings = 0,
    this.moderationCases = 0,
    this.banners = 0,
    this.chats = 0,
    this.payments = 0,
    this.revenue = 0,
  });

  final int users;
  final int listings;
  final int activeListings;
  final int moderationCases;
  final int banners;
  final int chats;
  final int payments;
  final int revenue;
}

class OwnerPayment {
  const OwnerPayment({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.createdAt,
    this.listingId = '',
    this.bannerId = '',
  });

  final String id;
  final String userId;
  final String type;
  final String status;
  final int amount;
  final String currency;
  final String provider;
  final DateTime createdAt;
  final String listingId;
  final String bannerId;
}

class OwnerAuditEvent {
  const OwnerAuditEvent({
    required this.id,
    required this.actorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
    this.details = const {},
  });

  final String id;
  final String actorId;
  final String action;
  final String targetType;
  final String targetId;
  final DateTime createdAt;
  final Map<String, String> details;
}

class ModerationResult {
  const ModerationResult({
    required this.decision,
    required this.reasonRu,
    required this.reasonKk,
    required this.riskScore,
  });

  final ModerationDecision decision;
  final String reasonRu;
  final String reasonKk;
  final double riskScore;
}

ModerationResult moderationResultFromData(Map<String, dynamic> data) {
  final moderation = data['moderation'] is Map
      ? Map<String, dynamic>.from(data['moderation'] as Map)
      : <String, dynamic>{};
  final reason = moderation['reason'] is Map
      ? Map<String, dynamic>.from(moderation['reason'] as Map)
      : <String, dynamic>{};
  return ModerationResult(
    decision: switch ('${moderation['decision'] ?? ''}') {
      'approved' => ModerationDecision.approved,
      'rejected' => ModerationDecision.rejected,
      _ => ModerationDecision.ownerReview,
    },
    reasonRu: '${reason['ru'] ?? ''}',
    reasonKk: '${reason['kk'] ?? reason['ru'] ?? ''}',
    riskScore: NumberParser.toDouble('${moderation['riskScore'] ?? 0}'),
  );
}

class ClassifiedsStore extends ChangeNotifier {
  ClassifiedsStore() : allowLocalFallback = false;

  @visibleForTesting
  ClassifiedsStore.test() : allowLocalFallback = true;

  factory ClassifiedsStore.demo() {
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
        id: 'demo_phone',
        ownerId: 'demo_seller',
        ownerName: 'Тестовый продавец',
        phone: '+7 (700) 000-00-01',
        title: 'Смартфон — тестовое объявление',
        description: 'Пример объявления для знакомства с PUSHKA.',
        categoryId: 'electronics',
        city: 'Алматы',
        district: '',
        price: 120000,
        condition: ListingCondition.used,
        images: const [],
        status: ListingStatus.active,
        createdAt: DateTime.now(),
      ),
      ListingAd(
        id: 'demo_sofa',
        ownerId: 'demo_seller',
        ownerName: 'Тестовый продавец',
        phone: '+7 (700) 000-00-01',
        title: 'Диван — тестовое объявление',
        description: 'Пример объявления для знакомства с PUSHKA.',
        categoryId: 'home',
        city: 'Астана',
        district: '',
        price: 65000,
        condition: ListingCondition.used,
        images: const [],
        status: ListingStatus.active,
        createdAt: DateTime.now(),
      ),
    ]);
    return store;
  }

  final bool allowLocalFallback;

  ClassifiedsLanguage language = ClassifiedsLanguage.ru;
  bool localPreferencesLoaded = false;
  bool languageSelected = true;
  bool isAuthorized = false;
  bool isOwner = false;
  bool needsProfileCompletion = false;
  String userId = 'guest';
  String userName = 'Пользователь';
  String phone = '';
  String city = 'Алматы';
  int selectedTab = 0;
  String selectedCategoryId = 'all';
  String selectedSubcategoryId = 'all';
  String searchQuery = '';
  String selectedCity = 'Алматы';
  String filterCity = 'all';
  int minPrice = 0;
  int maxPrice = 100000000;
  bool onlyWithPhoto = false;
  bool onlyPromoted = false;
  bool includeNegotiable = true;
  String selectedCondition = 'all';
  String sortMode = 'recommended';
  String firebaseLoadError = '';
  final selectedAttributeFilters = <String, String>{};
  String? pendingOtpPhone;
  String? pendingOtpCode;
  String? pendingPromotionPaymentId;
  StreamSubscription<String>? fcmTokenRefreshSubscription;
  final categories = <ListingCategory>[];
  final locations = <ListingLocation>[];
  final listings = <ListingAd>[];
  final favoriteIds = <String>[];
  final blockedUserIds = <String>{};
  final banners = <UserBannerAd>[];
  final chats = <ChatThread>[];
  final moderationCases = <ModerationCase>[];
  final notifications = <AppNotification>[];
  final ownerUsers = <AppUserProfile>[];
  final supportTickets = <SupportTicket>[];
  final ownerReports = <OwnerReport>[];
  final savedSearches = <SavedSearch>[];
  final promotionPlans = <PromotionPlan>[];
  final bannerPlans = <PromotionPlan>[];
  final ownerPayments = <OwnerPayment>[];
  final ownerAuditEvents = <OwnerAuditEvent>[];
  OwnerStats ownerStats = const OwnerStats();

  int get unreadNotificationCount =>
      notifications.where((item) => !item.isRead).length;

  void addLocalNotification(String text) {
    if (!allowLocalFallback) return;
    notifications.insert(
      0,
      AppNotification(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        userId: userId,
        text: text,
        isRead: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<ListingAd> get publicListings {
    final query = searchQuery.trim().toLowerCase();
    final result = listings.where((listing) {
      if (!listing.isPublic || blockedUserIds.contains(listing.ownerId)) {
        return false;
      }
      final categoryIds = categoryIdsForFilter(selectedCategoryId);
      if (selectedSubcategoryId != 'all' &&
          listing.categoryId != selectedSubcategoryId) {
        return false;
      }
      if (selectedSubcategoryId == 'all' &&
          selectedCategoryId != 'all' &&
          !categoryIds.contains(listing.categoryId)) {
        return false;
      }
      if (query.isNotEmpty &&
          !('${listing.title} ${listing.description} ${listing.city}'
              .toLowerCase()
              .contains(query))) {
        return false;
      }
      if (filterCity != 'all' && listing.city != filterCity) return false;
      if (!includeNegotiable && listing.price <= 0) return false;
      if (listing.price < minPrice || listing.price > maxPrice) return false;
      if (onlyWithPhoto && listing.images.isEmpty) return false;
      if (onlyPromoted && !listing.isPromoted) return false;
      if (selectedCondition != 'all' &&
          listing.condition.name != selectedCondition) {
        return false;
      }
      for (final entry in selectedAttributeFilters.entries) {
        if (entry.value != 'all' &&
            listing.attributes[entry.key] != entry.value) {
          return false;
        }
      }
      return true;
    }).toList();
    result.sort((a, b) {
      if (a.isPromoted != b.isPromoted) return a.isPromoted ? -1 : 1;
      return switch (sortMode) {
        'price_asc' => a.price.compareTo(b.price),
        'price_desc' => b.price.compareTo(a.price),
        'popular' => b.views.compareTo(a.views),
        'newest' => b.createdAt.compareTo(a.createdAt),
        _ => b.createdAt.compareTo(a.createdAt),
      };
    });
    return result;
  }

  Set<String> categoryIdsForFilter(String categoryId) {
    final category = categories
        .where((item) => item.id == categoryId)
        .firstOrNullC;
    return {
      categoryId,
      if (category != null) ...category.subcategories.map((item) => item.id),
    };
  }

  String rootCategoryId(String categoryId) {
    if (categories.any((item) => item.id == categoryId)) return categoryId;
    final parent = categories
        .where((item) => item.subcategories.any((sub) => sub.id == categoryId))
        .firstOrNullC;
    return parent?.id ?? categoryId;
  }

  List<ListingAttributeFilter> attributeFiltersFor(String categoryId) {
    final rootId = rootCategoryId(categoryId);
    final category = categories.where((item) => item.id == rootId).firstOrNullC;
    if (category != null && category.filters.isNotEmpty) {
      return category.filters;
    }
    return const [];
  }

  List<ListingAd> get myListings =>
      listings.where((item) => item.ownerId == userId).toList();

  List<ListingAd> get promotedListings =>
      publicListings.where((item) => item.isPromoted).take(10).toList();

  List<UserBannerAd> get activeBanners =>
      banners.where((item) => item.isActiveBanner).toList();

  String tx(String ru, String kk) => cTr(language, ru, kk);

  Future<void> loadLocalPreferences() async {
    try {
      const prefs = LocalPreferenceStore();
      language = await prefs.getString('pushka_classifieds_language') == 'kk'
          ? ClassifiedsLanguage.kk
          : ClassifiedsLanguage.ru;
      languageSelected =
          await prefs.getBool('pushka_classifieds_language_selected') ?? true;
      await prefs.remove('pushka_classifieds_phone');
      await prefs.remove('pushka_classifieds_name');
      final firebaseUser = firebaseAuthUserOrNull();
      if (firebaseUser != null) {
        userId = firebaseUser.uid;
        isAuthorized = true;
        await loadCurrentUserProfileFromFirebase();
        if (isOwner) {
          unawaited(loadOwnerData());
        }
        unawaited(loadFavoritesFromFirebase());
        unawaited(loadNotificationsFromFirebase());
        unawaited(loadSavedSearches());
        unawaited(loadMyListingsFromFirebase());
        unawaited(loadChatsFromFirebase());
        unawaited(loadBlockedMarketplaceUsers());
        unawaited(registerFcmToken());
      }
    } finally {
      localPreferencesLoaded = true;
      notifyListeners();
    }
  }

  Future<void> saveSession() async {
    const prefs = LocalPreferenceStore();
    await prefs.setString('pushka_classifieds_language', language.name);
    await prefs.setBool(
      'pushka_classifieds_language_selected',
      languageSelected,
    );
    await prefs.remove('pushka_classifieds_phone');
    await prefs.remove('pushka_classifieds_name');
    if (isAuthorized) {
      unawaited(saveProfileLanguageToFirebase());
    }
  }

  Future<void> loadCurrentUserProfileFromFirebase() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? userId;
    if (uid.isEmpty || uid == 'guest') return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null) return;
      userId = uid;
      phone = prettyPhone('${data['phone'] ?? phone}');
      userName = '${data['name'] ?? userName}';
      city = '${data['city'] ?? city}';
      selectedCity = city.isEmpty ? selectedCity : city;
      isOwner = data['role'] == 'owner' || data['role'] == 'admin';
      needsProfileCompletion =
          !isOwner &&
          (userName.trim().isEmpty ||
              userName == 'Пользователь' ||
              city.trim().isEmpty);
      final remoteLanguage = '${data['language'] ?? ''}';
      if (remoteLanguage == 'kk') language = ClassifiedsLanguage.kk;
      if (remoteLanguage == 'ru') language = ClassifiedsLanguage.ru;
    } catch (error) {
      debugPrint('User profile load skipped: $error');
    }
  }

  Future<void> saveProfileLanguageToFirebase() async {
    try {
      if (userId.isEmpty || userId == 'guest') return;
      await FirebaseFunctions.instance.httpsCallable('updateUserLanguage').call(
        {'language': language.name},
      );
    } catch (error) {
      debugPrint('User language save skipped: $error');
    }
  }

  Future<void> registerFcmToken() async {
    if (!isAuthorized || userId == 'guest') return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFunctions.instance.httpsCallable('registerFcmToken').call(
          {'token': token},
        );
      }
      fcmTokenRefreshSubscription ??= messaging.onTokenRefresh.listen((
        refreshedToken,
      ) {
        unawaited(
          FirebaseFunctions.instance.httpsCallable('registerFcmToken').call({
            'token': refreshedToken,
          }),
        );
      });
    } catch (error) {
      debugPrint('FCM token registration skipped: $error');
    }
  }

  Future<void> loadFromFirebase() async {
    if (demoAuthenticationEnabled && allowLocalFallback) return;
    try {
      final categoryQuery = FirebaseFirestore.instance
          .collection('listingCategories')
          .orderBy('sortOrder');
      final categorySnap = isOwner
          ? await categoryQuery.get()
          : await categoryQuery.where('isActive', isEqualTo: true).get();
      categories
        ..clear()
        ..add(
          ListingCategory(
            id: 'all',
            titleRu: 'Все',
            titleKk: 'Барлығы',
            iconKey: 'grid',
          ),
        )
        ..addAll(
          categorySnap.docs
              .where((doc) => isOwner || doc.data()['isActive'] == true)
              .map((doc) {
                final data = doc.data();
                final title = Map<String, dynamic>.from(data['title'] as Map);
                final subcategories = data['subcategories'] is List
                    ? (data['subcategories'] as List)
                          .whereType<Map>()
                          .map((item) {
                            final subTitle = item['title'] is Map
                                ? Map<String, dynamic>.from(
                                    item['title'] as Map,
                                  )
                                : <String, dynamic>{};
                            return ListingSubcategory(
                              id: '${item['id'] ?? ''}',
                              titleRu: '${subTitle['ru'] ?? item['id'] ?? ''}',
                              titleKk:
                                  '${subTitle['kk'] ?? subTitle['ru'] ?? item['id'] ?? ''}',
                            );
                          })
                          .where((item) => item.id.isNotEmpty)
                          .toList()
                    : <ListingSubcategory>[];
                final filters = data['filters'] is List
                    ? (data['filters'] as List)
                          .whereType<Map>()
                          .map((item) {
                            final filterTitle = item['title'] is Map
                                ? Map<String, dynamic>.from(
                                    item['title'] as Map,
                                  )
                                : <String, dynamic>{};
                            final options = item['options'] is List
                                ? List<String>.from(
                                        (item['options'] as List).map(
                                          (option) => '$option',
                                        ),
                                      )
                                      .where((option) => option.isNotEmpty)
                                      .toList()
                                : <String>[];
                            return ListingAttributeFilter(
                              id: '${item['id'] ?? ''}',
                              titleRu:
                                  '${filterTitle['ru'] ?? item['id'] ?? ''}',
                              titleKk:
                                  '${filterTitle['kk'] ?? filterTitle['ru'] ?? item['id'] ?? ''}',
                              options: options,
                            );
                          })
                          .where(
                            (item) =>
                                item.id.isNotEmpty && item.options.isNotEmpty,
                          )
                          .toList()
                    : <ListingAttributeFilter>[];
                return ListingCategory(
                  id: doc.id,
                  titleRu: '${title['ru'] ?? doc.id}',
                  titleKk: '${title['kk'] ?? title['ru'] ?? doc.id}',
                  iconKey: '${data['iconKey'] ?? doc.id}',
                  isActive: data['isActive'] == true,
                  subcategories: subcategories,
                  filters: filters,
                );
              }),
        );

      final locationQuery = FirebaseFirestore.instance
          .collection('locations')
          .orderBy('sortOrder');
      final locationSnap = isOwner
          ? await locationQuery.get()
          : await locationQuery.where('isActive', isEqualTo: true).get();
      locations
        ..clear()
        ..addAll(
          locationSnap.docs.map((doc) {
            final data = doc.data();
            final title = data['title'] is Map
                ? Map<String, dynamic>.from(data['title'] as Map)
                : <String, dynamic>{};
            final cities = data['cities'] is List
                ? List<String>.from(
                    (data['cities'] as List).map((item) => '$item'),
                  )
                : <String>[];
            return ListingLocation(
              id: doc.id,
              regionRu: '${title['ru'] ?? doc.id}',
              regionKk: '${title['kk'] ?? title['ru'] ?? doc.id}',
              cities: cities,
            );
          }),
        );

      final listingQuery = FirebaseFirestore.instance
          .collection('listings')
          .orderBy('createdAt', descending: true)
          .limit(isOwner ? 200 : 80);
      final listingSnap = isOwner
          ? await listingQuery.get()
          : await listingQuery.where('status', isEqualTo: 'active').get();
      listings
        ..removeWhere((item) => item.ownerId != userId)
        ..addAll(listingSnap.docs.map(listingFromDoc));
      await loadMyListingsFromFirebase();

      final bannerQuery = FirebaseFirestore.instance
          .collection('bannerAds')
          .limit(isOwner ? 100 : 20);
      final bannerSnap = isOwner
          ? await bannerQuery.get()
          : await bannerQuery.where('status', isEqualTo: 'active').get();
      banners
        ..removeWhere((item) => item.ownerId != userId)
        ..addAll(bannerSnap.docs.map(bannerFromDoc));
      await loadMyBannersFromFirebase();
      await loadFavoritesFromFirebase();
      await loadNotificationsFromFirebase();
      await loadChatsFromFirebase();
      await loadPlansFromFirebase();
      if (isOwner) {
        await loadOwnerData();
      }
      firebaseLoadError = '';
      notifyListeners();
    } catch (error) {
      firebaseLoadError = '$error';
      debugPrint('Classifieds Firebase load failed: $error');
      notifyListeners();
    }
  }

  Future<void> loadChatsFromFirebase() async {
    if (!isAuthorized) return;
    try {
      QuerySnapshot<Map<String, dynamic>> chatSnap;
      try {
        final chatQuery = FirebaseFirestore.instance
            .collection('chatRooms')
            .orderBy('updatedAt', descending: true)
            .limit(isOwner ? 120 : 50);
        chatSnap = isOwner
            ? await chatQuery.get()
            : await chatQuery
                  .where('participants', arrayContains: userId)
                  .get();
      } catch (_) {
        final fallbackQuery = FirebaseFirestore.instance
            .collection('chatRooms')
            .where('participants', arrayContains: userId)
            .limit(50);
        chatSnap = await fallbackQuery.get();
      }
      final loadedChats = <ChatThread>[];
      for (final doc in chatSnap.docs) {
        final data = doc.data();
        final messageSnap = await doc.reference
            .collection('messages')
            .orderBy('createdAt')
            .limit(80)
            .get();
        loadedChats.add(
          ChatThread(
            id: doc.id,
            listingId: '${data['listingId'] ?? ''}',
            buyerId: '${data['buyerId'] ?? ''}',
            sellerId: '${data['sellerId'] ?? ''}',
            title: '${data['listingTitle'] ?? data['title'] ?? 'Чат'}',
            messages: messageSnap.docs.map(messageFromDoc).toList(),
          ),
        );
      }
      loadedChats.sort((a, b) {
        final aDate = a.messages.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : a.messages.last.createdAt;
        final bDate = b.messages.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : b.messages.last.createdAt;
        return bDate.compareTo(aDate);
      });
      chats
        ..clear()
        ..addAll(loadedChats);
      notifyListeners();
    } catch (error) {
      debugPrint('Chats load skipped: $error');
    }
  }

  Future<void> loadMyListingsFromFirebase() async {
    if (!isAuthorized) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .where('ownerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      listings
        ..removeWhere((item) => item.ownerId == userId)
        ..addAll(snap.docs.map(listingFromDoc));
      notifyListeners();
    } catch (error) {
      debugPrint('My listings load skipped: $error');
    }
  }

  Future<void> loadFavoritesFromFirebase() async {
    if (!isAuthorized) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listingFavorites')
          .doc(userId)
          .get();
      final data = snap.data();
      final items = data?['items'];
      favoriteIds
        ..clear()
        ..addAll(
          items is Map
              ? items.entries
                    .where((entry) => entry.value == true)
                    .map((entry) => '${entry.key}')
              : const <String>[],
        );
      notifyListeners();
    } catch (error) {
      debugPrint('Favorites load skipped: $error');
    }
  }

  Future<void> loadNotificationsFromFirebase() async {
    if (!isAuthorized) return;
    notifications.removeWhere((item) => item.userId != userId);
    notifyListeners();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      notifications
        ..clear()
        ..addAll(
          snap.docs
              .map(notificationFromDoc)
              .where((item) => item.userId == userId),
        );
      notifyListeners();
    } catch (error) {
      debugPrint('Notifications load skipped: $error');
    }
  }

  Future<void> loadMyBannersFromFirebase() async {
    if (!isAuthorized || isOwner) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bannerAds')
          .where('ownerId', isEqualTo: userId)
          .limit(50)
          .get();
      banners
        ..removeWhere((item) => item.ownerId == userId)
        ..addAll(snap.docs.map(bannerFromDoc));
      banners.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    } catch (error) {
      debugPrint('My banners load skipped: $error');
    }
  }

  Future<void> markNotificationsRead() async {
    if (!isAuthorized || unreadNotificationCount == 0) return;
    final unreadIds = notifications
        .where((item) => !item.isRead && !item.id.startsWith('local_'))
        .map((item) => item.id)
        .toList();
    final marked = notifications
        .map(
          (item) => AppNotification(
            id: item.id,
            userId: item.userId,
            text: item.text,
            isRead: true,
            createdAt: item.createdAt,
            type: item.type,
            data: item.data,
            resolved: item.resolved,
          ),
        )
        .toList();
    notifications
      ..clear()
      ..addAll(marked);
    notifyListeners();
    try {
      await FirebaseFunctions.instance
          .httpsCallable('markNotificationsRead')
          .call({'notificationIds': unreadIds});
    } catch (error) {
      debugPrint('Notifications read sync skipped: $error');
    }
  }

  Future<void> loadPlansFromFirebase() async {
    final promoQuery = FirebaseFirestore.instance
        .collection('promotionPlans')
        .orderBy('sortOrder');
    final promoSnap = isOwner
        ? await promoQuery.get()
        : await promoQuery.where('isActive', isEqualTo: true).get();
    promotionPlans
      ..clear()
      ..addAll(promoSnap.docs.map((doc) => planFromDoc(doc)));
    final bannerPlanQuery = FirebaseFirestore.instance
        .collection('bannerPlans')
        .orderBy('sortOrder');
    final bannerPlanSnap = isOwner
        ? await bannerPlanQuery.get()
        : await bannerPlanQuery.where('isActive', isEqualTo: true).get();
    bannerPlans
      ..clear()
      ..addAll(bannerPlanSnap.docs.map((doc) => planFromDoc(doc)));
  }

  PromotionPlan planFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = data['title'] is Map
        ? Map<String, dynamic>.from(data['title'] as Map)
        : <String, dynamic>{};
    final description = data['description'] is Map
        ? Map<String, dynamic>.from(data['description'] as Map)
        : <String, dynamic>{};
    return PromotionPlan(
      id: doc.id,
      title: '${title['ru'] ?? doc.id}',
      titleKk: '${title['kk'] ?? title['ru'] ?? doc.id}',
      caption: '${description['ru'] ?? ''}',
      captionKk: '${description['kk'] ?? description['ru'] ?? ''}',
      price: NumberParser.toInt(data['price']),
      days: NumberParser.toInt(data['durationDays']),
      isActive: data['isActive'] != false,
    );
  }

  ListingAd listingFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final boostUntil = data['boostUntil'];
    final topUntil = data['topUntil'];
    final vipUntil = data['vipUntil'];
    final archivedAt = data['archivedAt'];
    final restoreUntil = data['restoreUntil'];
    final attributes = data['attributes'] is Map
        ? Map<String, String>.from(
            (data['attributes'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            ),
          )
        : <String, String>{};
    final moderation = data['moderation'] is Map
        ? Map<String, dynamic>.from(data['moderation'] as Map)
        : <String, dynamic>{};
    final moderationReason = moderation['reason'] is Map
        ? Map<String, dynamic>.from(moderation['reason'] as Map)
        : <String, dynamic>{};
    return ListingAd(
      id: doc.id,
      ownerId: '${data['ownerId'] ?? ''}',
      ownerName: '${data['ownerName'] ?? 'Пользователь'}',
      phone: prettyPhone('${data['phone'] ?? ''}'),
      title: '${data['title'] ?? ''}',
      description: '${data['description'] ?? ''}',
      categoryId: '${data['categoryId'] ?? 'electronics'}',
      city: '${data['city'] ?? 'Алматы'}',
      district: '${data['district'] ?? ''}',
      price: NumberParser.toInt(data['price']),
      condition: conditionFromString('${data['condition'] ?? 'used'}'),
      images: (data['images'] as List? ?? const []).map((e) => '$e').toList(),
      status: statusFromString('${data['status'] ?? 'active'}'),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      sellerType: '${data['sellerType'] ?? 'private'}' == 'business'
          ? 'business'
          : 'private',
      attributes: attributes,
      rejectionReasonRu:
          '${data['rejectionReasonRu'] ?? moderationReason['ru'] ?? ''}',
      rejectionReasonKk:
          '${data['rejectionReasonKk'] ?? moderationReason['kk'] ?? ''}',
      views: NumberParser.toInt(data['views']),
      favoriteCount: NumberParser.toInt(data['favoriteCount']),
      boostUntil: boostUntil is Timestamp ? boostUntil.toDate() : null,
      topUntil: topUntil is Timestamp ? topUntil.toDate() : null,
      vipUntil: vipUntil is Timestamp ? vipUntil.toDate() : null,
      archivedAt: archivedAt is Timestamp ? archivedAt.toDate() : null,
      restoreUntil: restoreUntil is Timestamp ? restoreUntil.toDate() : null,
    );
  }

  UserBannerAd bannerFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final activeUntil = data['activeUntil'];
    final moderation = data['moderation'] is Map
        ? Map<String, dynamic>.from(data['moderation'] as Map)
        : <String, dynamic>{};
    final moderationReason = moderation['reason'] is Map
        ? Map<String, dynamic>.from(moderation['reason'] as Map)
        : <String, dynamic>{};
    return UserBannerAd(
      id: doc.id,
      ownerId: '${data['ownerId'] ?? ''}',
      title: '${data['title'] ?? ''}',
      caption: '${data['caption'] ?? ''}',
      imageUrl: '${data['imageUrl'] ?? ''}',
      status: statusFromString('${data['status'] ?? 'active'}'),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      activeUntil: activeUntil is Timestamp ? activeUntil.toDate() : null,
      rejectionReasonRu:
          '${data['rejectionReasonRu'] ?? moderationReason['ru'] ?? ''}',
    );
  }

  ChatMessage messageFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final status = '${data['status'] ?? 'sent'}';
    final deleted = data['deleted'] == true || status == 'deleted';
    return ChatMessage(
      id: doc.id,
      senderId: '${data['senderId'] ?? ''}',
      text: deleted ? 'Сообщение удалено' : '${data['text'] ?? ''}',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      imageUrl: deleted ? '' : '${data['imageUrl'] ?? ''}',
      fileUrl: deleted ? '' : '${data['fileUrl'] ?? ''}',
      fileName: deleted ? '' : '${data['fileName'] ?? ''}',
      flagged: status == 'owner_review',
      deleted: deleted,
    );
  }

  AppNotification notificationFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    String localized(Object? value) {
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        return '${map[language.name] ?? map['ru'] ?? map['kk'] ?? ''}';
      }
      return '${value ?? ''}';
    }

    final title = localized(data['title']).trim();
    final body = localized(data['body']).trim();
    final rawData = data['data'] is Map
        ? Map<String, String>.from(
            (data['data'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            ),
          )
        : <String, String>{};
    final text = title.isEmpty
        ? body
        : body.isEmpty
        ? title
        : '$title: $body';
    return AppNotification(
      id: doc.id,
      userId: '${data['userId'] ?? ''}',
      text: text,
      isRead: data['isRead'] == true,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      type: '${data['type'] ?? ''}',
      data: rawData,
      resolved: data['resolved'] == true,
    );
  }

  Future<void> loadOwnerData() async {
    if (!isOwner) return;
    try {
      await loadModerationCasesFromFirebase();
      await loadSupportTicketsFromFirebase();
      await loadOwnerReportsFromFirebase();
      await loadOwnerPaymentsFromFirebase();
      await loadOwnerAuditFromFirebase();
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      ownerUsers
        ..clear()
        ..addAll(
          userSnap.docs.map((doc) {
            final data = doc.data();
            final createdAt = data['createdAt'];
            return AppUserProfile(
              id: doc.id,
              name: '${data['name'] ?? 'Пользователь'}',
              phone: prettyPhone('${data['phone'] ?? ''}'),
              city: '${data['city'] ?? ''}',
              role: '${data['role'] ?? 'user'}',
              status: '${data['status'] ?? 'active'}',
              sellerType:
                  '${data['sellerType'] ?? data['accountType'] ?? 'private'}' ==
                      'business'
                  ? 'business'
                  : 'private',
              violationCount: NumberParser.toInt(data['violationCount']),
              bannedReasonRu: data['bannedReason'] is Map
                  ? '${Map<String, dynamic>.from(data['bannedReason'] as Map)['ru'] ?? ''}'
                  : '${data['bannedReason'] ?? ''}',
              createdAt: createdAt is Timestamp
                  ? createdAt.toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0),
            );
          }),
        );
      ownerStats = OwnerStats(
        users: ownerUsers.length,
        listings: listings.length,
        activeListings: listings
            .where((item) => item.status == ListingStatus.active)
            .length,
        moderationCases: moderationCases.where((item) => !item.resolved).length,
        banners: banners.length,
        chats: chats.length,
        payments: ownerPayments.length,
        revenue: ownerPayments
            .where((item) => item.status == 'paid')
            .fold<int>(0, (total, item) => total + item.amount),
      );
      notifyListeners();
    } catch (error) {
      debugPrint('Owner users load skipped: $error');
    }
  }

  Future<void> loadOwnerPaymentsFromFirebase() async {
    if (!isOwner) return;
    final snap = await FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    ownerPayments
      ..clear()
      ..addAll(snap.docs.map(ownerPaymentFromDoc));
  }

  OwnerPayment ownerPaymentFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return OwnerPayment(
      id: doc.id,
      userId: '${data['userId'] ?? ''}',
      type: '${data['type'] ?? ''}',
      status: '${data['status'] ?? 'pending'}',
      amount: NumberParser.toInt(data['amount']),
      currency: '${data['currency'] ?? 'KZT'}',
      provider: '${data['provider'] ?? ''}',
      listingId: '${data['listingId'] ?? ''}',
      bannerId: '${data['bannerId'] ?? ''}',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }

  Future<void> loadOwnerAuditFromFirebase() async {
    if (!isOwner) return;
    final snap = await FirebaseFirestore.instance
        .collection('ownerAuditLog')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    ownerAuditEvents
      ..clear()
      ..addAll(snap.docs.map(ownerAuditFromDoc));
  }

  OwnerAuditEvent ownerAuditFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final details = data['details'] is Map
        ? Map<String, String>.from(
            (data['details'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            ),
          )
        : <String, String>{};
    return OwnerAuditEvent(
      id: doc.id,
      actorId: '${data['actorId'] ?? ''}',
      action: '${data['action'] ?? ''}',
      targetType: '${data['targetType'] ?? ''}',
      targetId: '${data['targetId'] ?? ''}',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      details: details,
    );
  }

  Future<void> loadSupportTicketsFromFirebase() async {
    if (!isOwner) return;
    final snap = await FirebaseFirestore.instance
        .collection('supportTickets')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    supportTickets
      ..clear()
      ..addAll(snap.docs.map(supportTicketFromDoc));
  }

  Future<void> loadOwnerReportsFromFirebase() async {
    if (!isOwner) return;
    final snap = await FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    ownerReports
      ..clear()
      ..addAll(snap.docs.map(ownerReportFromDoc));
  }

  OwnerReport ownerReportFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return OwnerReport(
      id: doc.id,
      reporterId: '${data['reporterId'] ?? ''}',
      reason: '${data['reason'] ?? ''}',
      status: '${data['status'] ?? 'open'}',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      type: '${data['type'] ?? 'listing'}',
      listingId: '${data['listingId'] ?? ''}',
      chatId: '${data['chatId'] ?? ''}',
      messageId: '${data['messageId'] ?? ''}',
      reportedUserId: '${data['reportedUserId'] ?? ''}',
    );
  }

  SupportTicket supportTicketFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    return SupportTicket(
      id: doc.id,
      userId: '${data['userId'] ?? ''}',
      userName: '${data['userName'] ?? 'Пользователь'}',
      phone: prettyPhone('${data['phone'] ?? ''}'),
      subject: '${data['subject'] ?? ''}',
      message: '${data['message'] ?? ''}',
      status: '${data['status'] ?? 'open'}',
      ownerReply: '${data['ownerReply'] ?? ''}',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }

  Future<void> loadModerationCasesFromFirebase() async {
    if (!isOwner) return;
    final snap = await FirebaseFirestore.instance
        .collection('moderationCases')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    moderationCases
      ..clear()
      ..addAll(snap.docs.map(moderationCaseFromDoc));
  }

  ModerationCase moderationCaseFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final reason = data['reason'] is Map
        ? Map<String, dynamic>.from(data['reason'] as Map)
        : <String, dynamic>{};
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};
    return ModerationCase(
      id: doc.id,
      type: '${data['type'] ?? ''}',
      targetId: '${data['targetId'] ?? ''}',
      title: '${payload['title'] ?? data['targetId'] ?? 'Материал'}',
      reasonRu: '${reason['ru'] ?? data['reasonRu'] ?? ''}',
      reasonKk: '${reason['kk'] ?? reason['ru'] ?? data['reasonKk'] ?? ''}',
      riskScore: NumberParser.toDouble(data['riskScore']),
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      resolved: data['status'] == 'resolved',
    );
  }

  Future<String> installationCredential() async {
    const prefs = LocalPreferenceStore();
    final existing = await prefs.getString('pushka_installation_credential');
    if (existing != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
      return existing;
    }
    final random = Random.secure();
    final credential = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString('pushka_installation_credential', credential);
    return credential;
  }

  Future<void> requestOtp(String value) async {
    final formatted = prettyPhone(value);
    pendingOtpPhone = formatted;
    final normalized = normalizePhone(formatted);
    final ownerLikeNumber = value
        .replaceAll(RegExp(r'\D'), '')
        .contains('0000000000');
    pendingOtpCode = allowLocalFallback
        ? (normalized == normalizePhone(ownerPhone) || ownerLikeNumber
              ? ownerCode
              : '3718')
        : null;
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('requestDeviceAccessCode')
          .call<Map<String, dynamic>>({
            'phone': formatted,
            'deviceCredential': await installationCredential(),
            'language': language.name,
          });
      final data = Map<String, dynamic>.from(response.data);
      final code = '${data['code'] ?? ''}';
      if (code.isNotEmpty) pendingOtpCode = code;
    } catch (error) {
      if (!allowLocalFallback) rethrow;
      debugPrint('requestOtp local fallback: $error');
    }
    notifyListeners();
  }

  Future<bool> verifyOtp(String code) async {
    final otpPhone = pendingOtpPhone;
    if (otpPhone == null) return false;
    Map<String, dynamic> data = {};
    if (!allowLocalFallback || pendingOtpCode == null) {
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyDeviceAccessCode')
          .call<Map<String, dynamic>>({
            'phone': otpPhone,
            'code': code.trim(),
            'deviceCredential': await installationCredential(),
          });
      data = Map<String, dynamic>.from(response.data);
      final token = '${data['customToken'] ?? ''}';
      if (token.isEmpty) throw StateError('custom_token_missing');
      await FirebaseAuth.instance.signInWithCustomToken(token);
    } else {
      final isOwnerFallbackCode = code.trim() == ownerCode;
      if (code.trim() != pendingOtpCode && !isOwnerFallbackCode) return false;
      try {
        final response = await FirebaseFunctions.instance
            .httpsCallable('verifyWhatsAppOtp')
            .call<Map<String, dynamic>>({
              'phone': otpPhone,
              'code': code.trim(),
            });
        data = Map<String, dynamic>.from(response.data);
        final token = '${data['customToken'] ?? ''}';
        if (token.isNotEmpty) {
          await FirebaseAuth.instance.signInWithCustomToken(token);
        }
      } catch (error) {
        debugPrint('verifyOtp local fallback: $error');
      }
    }
    final firebaseUser = firebaseAuthUserOrNull();
    if (!allowLocalFallback && firebaseUser == null) {
      throw StateError('firebase_auth_required');
    }
    phone = otpPhone;
    final ownerByFallbackCode =
        allowLocalFallback &&
        (code.trim() == ownerCode || pendingOtpCode == ownerCode);
    userId =
        firebaseUser?.uid ??
        '${data['uid'] ?? 'phone_${normalizePhone(phone).replaceAll(RegExp(r'\D'), '')}'}';
    isAuthorized = true;
    isOwner =
        (allowLocalFallback &&
            normalizePhone(phone) == normalizePhone(ownerPhone)) ||
        data['role'] == 'owner' ||
        data['role'] == 'admin' ||
        ownerByFallbackCode;
    userName =
        '${data['name'] ?? (isOwner ? 'Владелец PUSHKA' : 'Пользователь')}';
    city = '${data['city'] ?? city}';
    selectedCity = city.isEmpty ? selectedCity : city;
    needsProfileCompletion =
        !isOwner &&
        (data['isNewUser'] == true ||
            userName.trim().isEmpty ||
            userName == 'Пользователь' ||
            city.trim().isEmpty);
    final remoteLanguage = '${data['language'] ?? ''}';
    if (remoteLanguage == 'kk') language = ClassifiedsLanguage.kk;
    if (remoteLanguage == 'ru') language = ClassifiedsLanguage.ru;
    selectedTab = 0;
    await saveSession();
    if (isOwner) {
      unawaited(loadOwnerData());
    }
    unawaited(loadFavoritesFromFirebase());
    unawaited(loadNotificationsFromFirebase());
    unawaited(loadSavedSearches());
    unawaited(loadMyListingsFromFirebase());
    unawaited(loadChatsFromFirebase());
    unawaited(loadBlockedMarketplaceUsers());
    unawaited(registerFcmToken());
    logAnalyticsEvent('login', {
      'method': 'phone_whatsapp',
      'role': isOwner ? 'owner' : 'user',
      'is_new_user': needsProfileCompletion ? 'true' : 'false',
    });
    notifyListeners();
    return true;
  }

  Future<void> completeProfile({
    required String name,
    required String city,
  }) async {
    if (!isAuthorized) throw StateError('auth_required');
    final cleanName = name.trim();
    final cleanCity = city.trim();
    if (cleanName.isEmpty || cleanCity.isEmpty) {
      throw StateError('profile_required');
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('completeUserProfile')
          .call({'name': cleanName, 'city': cleanCity});
    }
    userName = cleanName;
    this.city = cleanCity;
    selectedCity = cleanCity;
    needsProfileCompletion = false;
    await saveSession();
    unawaited(registerFcmToken());
    logAnalyticsEvent('sign_up', {'method': 'phone_whatsapp'});
    notifyListeners();
  }

  void logout() {
    blockedUserIds.clear();
    isAuthorized = false;
    isOwner = false;
    needsProfileCompletion = false;
    userId = 'guest';
    phone = '';
    userName = 'Пользователь';
    notifications.clear();
    favoriteIds.clear();
    chats.clear();
    savedSearches.clear();
    if (firebaseAuthUserOrNull() != null) FirebaseAuth.instance.signOut();
    notifyListeners();
  }

  Future<void> requestAccountDeletion() async {
    if (!isAuthorized) throw StateError('auth_required');
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('deleteAccount').call();
      await FirebaseAuth.instance.signOut();
      await const LocalPreferenceStore().remove(
        'pushka_installation_credential',
      );
      await const LocalPreferenceStore().setBool(
        'clear_deleted_account_cache',
        true,
      );
    }
    final deletedUserId = userId;
    pendingOtpPhone = null;
    pendingOtpCode = null;
    isAuthorized = false;
    isOwner = false;
    needsProfileCompletion = false;
    userId = 'guest';
    phone = '';
    userName = 'Пользователь';
    city = '';
    selectedCity = 'all';
    selectedTab = 0;
    notifications.clear();
    favoriteIds.clear();
    blockedUserIds.clear();
    chats.clear();
    savedSearches.clear();
    banners.clear();
    ownerUsers.clear();
    supportTickets.clear();
    ownerReports.clear();
    ownerPayments.clear();
    ownerAuditEvents.clear();
    listings.removeWhere((item) => item.ownerId == deletedUserId);
    await saveSession();
    notifyListeners();
  }

  void selectTab(int value) {
    selectedTab = value;
    notifyListeners();
  }

  void selectCategory(String value) {
    selectedCategoryId = value;
    selectedSubcategoryId = 'all';
    selectedTab = 1;
    notifyListeners();
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void applyFilters({
    required int min,
    required int max,
    required bool withPhoto,
    required bool promoted,
    required bool negotiable,
    required String condition,
    required String categoryId,
    required String subcategoryId,
    required String city,
    required String sort,
    required Map<String, String> attributes,
  }) {
    minPrice = min;
    maxPrice = max;
    onlyWithPhoto = withPhoto;
    onlyPromoted = promoted;
    includeNegotiable = negotiable;
    selectedCondition = condition;
    selectedCategoryId = categoryId;
    selectedSubcategoryId = subcategoryId;
    filterCity = city;
    sortMode = sort;
    selectedAttributeFilters
      ..clear()
      ..addAll(attributes);
    notifyListeners();
  }

  bool get hasActiveSearch {
    return searchQuery.trim().isNotEmpty ||
        selectedCategoryId != 'all' ||
        selectedSubcategoryId != 'all' ||
        filterCity != 'all' ||
        minPrice > 0 ||
        maxPrice < 100000000 ||
        onlyWithPhoto ||
        onlyPromoted ||
        !includeNegotiable ||
        selectedCondition != 'all' ||
        selectedAttributeFilters.isNotEmpty;
  }

  String currentSearchTitle() {
    final category = categories
        .where((item) => item.id == selectedCategoryId)
        .firstOrNullC;
    final parts = [
      if (searchQuery.trim().isNotEmpty) searchQuery.trim(),
      if (category != null && selectedCategoryId != 'all')
        category.title(language),
      if (filterCity != 'all') filterCity,
      if (partsPriceLabel().isNotEmpty) partsPriceLabel(),
    ];
    return parts.isEmpty
        ? tx('Все объявления', 'Барлық хабарландыру')
        : parts.join(' · ');
  }

  String partsPriceLabel() {
    if (minPrice <= 0 && maxPrice >= 100000000) return '';
    return '${cMoney(minPrice)} - ${cMoney(maxPrice)}';
  }

  Future<void> loadSavedSearches() async {
    if (!isAuthorized) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('savedSearches')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      savedSearches
        ..clear()
        ..addAll(snap.docs.map(savedSearchFromDoc));
      notifyListeners();
    } catch (error) {
      debugPrint('Saved searches load skipped: $error');
    }
  }

  SavedSearch savedSearchFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    final attributes = data['attributes'] is Map
        ? Map<String, String>.from(
            (data['attributes'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            ),
          )
        : <String, String>{};
    return SavedSearch(
      id: doc.id,
      title: '${data['title'] ?? 'Поиск'}',
      query: '${data['query'] ?? ''}',
      categoryId: '${data['categoryId'] ?? 'all'}',
      subcategoryId: '${data['subcategoryId'] ?? 'all'}',
      city: '${data['city'] ?? 'all'}',
      minPrice: NumberParser.toInt(data['minPrice']),
      maxPrice: NumberParser.toInt(data['maxPrice']) == 0
          ? 100000000
          : NumberParser.toInt(data['maxPrice']),
      condition: '${data['condition'] ?? 'all'}',
      sortMode: '${data['sortMode'] ?? 'recommended'}',
      attributes: attributes,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    );
  }

  Future<void> saveCurrentSearch() async {
    if (!isAuthorized) throw StateError('auth_required');
    final id = 'search_${DateTime.now().microsecondsSinceEpoch}';
    final item = SavedSearch(
      id: id,
      title: currentSearchTitle(),
      query: searchQuery.trim(),
      categoryId: selectedCategoryId,
      subcategoryId: selectedSubcategoryId,
      city: filterCity,
      minPrice: minPrice,
      maxPrice: maxPrice,
      condition: selectedCondition,
      sortMode: sortMode,
      attributes: Map<String, String>.from(selectedAttributeFilters),
      createdAt: DateTime.now(),
    );
    if (allowLocalFallback) {
      savedSearches.insert(0, item);
      notifyListeners();
      return;
    }
    try {
      await FirebaseFunctions.instance
          .httpsCallable('saveSavedSearch')
          .call<Map<String, dynamic>>({
            'id': id,
            'title': item.title,
            'query': item.query,
            'categoryId': item.categoryId,
            'subcategoryId': item.subcategoryId,
            'city': item.city,
            'minPrice': item.minPrice,
            'maxPrice': item.maxPrice,
            'condition': item.condition,
            'sortMode': item.sortMode,
            'attributes': item.attributes,
          });
      await loadSavedSearches();
      logAnalyticsEvent('save_search', {
        'category_id': item.categoryId,
        'city': item.city,
      });
    } catch (error) {
      rethrow;
    }
  }

  void applySavedSearch(SavedSearch item) {
    searchQuery = item.query;
    selectedCategoryId = item.categoryId;
    selectedSubcategoryId = item.subcategoryId;
    filterCity = item.city;
    minPrice = item.minPrice;
    maxPrice = item.maxPrice;
    selectedCondition = item.condition;
    sortMode = item.sortMode;
    selectedAttributeFilters
      ..clear()
      ..addAll(item.attributes);
    selectedTab = 1;
    notifyListeners();
  }

  Future<void> deleteSavedSearch(SavedSearch item) async {
    if (allowLocalFallback) {
      savedSearches.removeWhere((search) => search.id == item.id);
      notifyListeners();
      return;
    }
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteSavedSearch').call({
        'searchId': item.id,
      });
      await loadSavedSearches();
    } catch (error) {
      rethrow;
    }
  }

  Future<String> createSupportTicket({
    required String subject,
    required String message,
  }) async {
    if (!isAuthorized) throw StateError('auth_required');
    final cleanSubject = subject.trim();
    final cleanMessage = message.trim();
    if (cleanSubject.isEmpty || cleanMessage.isEmpty) {
      throw StateError('support_required');
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('createSupportTicket')
        .call<Map<String, dynamic>>({
          'subject': cleanSubject,
          'message': cleanMessage,
        });
    final data = Map<String, dynamic>.from(response.data);
    final ticketId = '${data['ticketId'] ?? ''}';
    logAnalyticsEvent('support_ticket_created', {'ticket_id': ticketId});
    await loadNotificationsFromFirebase();
    return ticketId;
  }

  Future<void> ownerSendPush({
    required String titleRu,
    required String titleKk,
    required String bodyRu,
    required String bodyKk,
    String topic = 'all',
    String userId = '',
  }) async {
    if (!isOwner) throw StateError('owner_required');
    await FirebaseFunctions.instance.httpsCallable('sendPushNotification').call(
      {
        if (userId.trim().isNotEmpty)
          'userId': userId.trim()
        else
          'topic': topic,
        'title': {'ru': titleRu.trim(), 'kk': titleKk.trim()},
        'body': {'ru': bodyRu.trim(), 'kk': bodyKk.trim()},
        'data': {'source': 'owner_panel'},
      },
    );
    await loadOwnerAuditFromFirebase();
    notifyListeners();
  }

  Future<String> ownerRunListingModerationSweep({
    bool rejectAll = false,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final response = await FirebaseFunctions.instance
        .httpsCallable('ownerRunListingModerationSweep')
        .call<Map<String, dynamic>>({'limit': 500, 'rejectAll': rejectAll});
    final data = Map<String, dynamic>.from(response.data);
    await loadFromFirebase();
    await loadOwnerAuditFromFirebase();
    notifyListeners();
    return 'Проверено: ${data['checked'] ?? 0}, отклонено: ${data['rejected'] ?? 0}, одобрено: ${data['approved'] ?? 0}';
  }

  Future<void> ownerSaveLegalDocuments({
    required String version,
    required Map<String, Map<String, String>> documents,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    await FirebaseFunctions.instance
        .httpsCallable('ownerSaveLegalDocuments')
        .call({'currentVersion': version.trim(), 'documents': documents});
    await loadOwnerAuditFromFirebase();
  }

  Future<void> ownerSaveAppSettings({
    required String supportPhone,
    required String supportWhatsApp,
    required bool moderationEnabled,
    required double autoApproveBelow,
    required double ownerReviewAbove,
    required double autoRejectAbove,
    required int maxListingPhotos,
    required int maxBannerDays,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    await FirebaseFunctions.instance
        .httpsCallable('ownerSaveAppSettings')
        .call({
          'supportPhone': supportPhone.trim(),
          'supportWhatsApp': supportWhatsApp.trim(),
          'moderationEnabled': moderationEnabled,
          'autoApproveBelow': autoApproveBelow,
          'ownerReviewAbove': ownerReviewAbove,
          'autoRejectAbove': autoRejectAbove,
          'maxListingPhotos': maxListingPhotos,
          'maxBannerDays': maxBannerDays,
        });
    await loadOwnerAuditFromFirebase();
  }

  Future<void> saveCategory({
    required String id,
    required String titleRu,
    required String titleKk,
    required String iconKey,
    required bool isActive,
    List<ListingSubcategory> subcategories = const [],
    List<ListingAttributeFilter> filters = const [],
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final cleanId = id.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]+'),
      '_',
    );
    if (cleanId.isEmpty || titleRu.trim().isEmpty) {
      throw StateError('category_required');
    }
    final category = ListingCategory(
      id: cleanId,
      titleRu: titleRu.trim(),
      titleKk: titleKk.trim().isEmpty ? titleRu.trim() : titleKk.trim(),
      iconKey: iconKey,
      isActive: isActive,
      subcategories: subcategories,
      filters: filters,
    );
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('ownerSaveCategory').call({
        'id': cleanId,
        'titleRu': category.titleRu,
        'titleKk': category.titleKk,
        'iconKey': category.iconKey,
        'isActive': isActive,
        'subcategories': subcategories
            .map(
              (item) => {
                'id': item.id,
                'titleRu': item.titleRu,
                'titleKk': item.titleKk,
              },
            )
            .toList(),
        'filters': filters
            .map(
              (item) => {
                'id': item.id,
                'titleRu': item.titleRu,
                'titleKk': item.titleKk,
                'options': item.options,
              },
            )
            .toList(),
      });
    }
    categories.removeWhere((item) => item.id == cleanId);
    if (cleanId != 'all' && isActive) {
      categories.add(category);
    }
    notifyListeners();
  }

  Future<void> savePlan({
    required PromotionPlan plan,
    required bool banner,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final list = banner ? bannerPlans : promotionPlans;
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('ownerSavePlan').call({
        'id': plan.id,
        'title': plan.title,
        'titleKk': plan.titleKk,
        'caption': plan.caption,
        'captionKk': plan.captionKk,
        'price': plan.price,
        'days': plan.days,
        'banner': banner,
        'isActive': plan.isActive,
      });
    }
    list.removeWhere((item) => item.id == plan.id);
    list.add(plan);
    notifyListeners();
  }

  Future<void> saveLocation(ListingLocation location, bool isActive) async {
    if (!isOwner) throw StateError('owner_required');
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('ownerSaveLocation').call({
        'id': location.id,
        'titleRu': location.regionRu,
        'titleKk': location.regionKk,
        'cities': location.cities,
        'isActive': isActive,
      });
    }
    locations.removeWhere((item) => item.id == location.id);
    if (isActive) locations.add(location);
    notifyListeners();
  }

  Future<void> setUserBlocked(AppUserProfile user, bool blocked) async {
    if (!isOwner) throw StateError('owner_required');
    try {
      await FirebaseFunctions.instance
          .httpsCallable('ownerSetUserStatus')
          .call({
            'userId': user.id,
            'status': blocked ? 'banned' : 'active',
            'reason': blocked ? 'Решение владельца приложения' : '',
          });
    } catch (error) {
      if (!allowLocalFallback) rethrow;
      debugPrint('ownerSetUserStatus skipped: $error');
    }
    final index = ownerUsers.indexWhere((item) => item.id == user.id);
    if (index >= 0) {
      ownerUsers[index] = AppUserProfile(
        id: user.id,
        name: user.name,
        phone: user.phone,
        city: user.city,
        role: user.role,
        status: blocked ? 'banned' : 'active',
        sellerType: user.sellerType,
        violationCount: user.violationCount,
        bannedReasonRu: blocked ? 'Решение владельца приложения' : '',
        createdAt: user.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> setUserRole(AppUserProfile user, String role) async {
    if (!isOwner) throw StateError('owner_required');
    if (!['user', 'admin', 'owner'].contains(role)) {
      throw StateError('invalid_role');
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('ownerSetUserRole').call({
        'userId': user.id,
        'role': role,
      });
    }
    final index = ownerUsers.indexWhere((item) => item.id == user.id);
    if (index >= 0) {
      ownerUsers[index] = AppUserProfile(
        id: user.id,
        name: user.name,
        phone: user.phone,
        city: user.city,
        role: role,
        status: user.status,
        sellerType: user.sellerType,
        violationCount: user.violationCount,
        bannedReasonRu: user.bannedReasonRu,
        createdAt: user.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> updateOwnerUserProfile({
    required AppUserProfile user,
    required String name,
    required String city,
    required String phone,
    required String sellerType,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('ownerUpdateUserProfile')
          .call({
            'userId': user.id,
            'name': name.trim(),
            'city': city.trim(),
            'phone': phone.trim(),
            'sellerType': sellerType,
          });
    }
    final index = ownerUsers.indexWhere((item) => item.id == user.id);
    if (index >= 0) {
      ownerUsers[index] = AppUserProfile(
        id: user.id,
        name: name.trim(),
        phone: prettyPhone(phone),
        city: city.trim(),
        role: user.role,
        status: user.status,
        sellerType: sellerType,
        violationCount: user.violationCount,
        bannedReasonRu: user.bannedReasonRu,
        createdAt: user.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> setOwnerListingStatus(
    ListingAd listing,
    ListingStatus status, {
    String reason = '',
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final serverStatus = switch (status) {
      ListingStatus.pendingPayment => 'pending_payment',
      ListingStatus.ownerReview || ListingStatus.moderation => 'owner_review',
      ListingStatus.active => 'active',
      ListingStatus.rejected => 'rejected',
      ListingStatus.deleted => 'deleted',
      ListingStatus.archived || ListingStatus.draft => 'archived',
    };
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('ownerSetListingStatus')
          .call({
            'listingId': listing.id,
            'status': serverStatus,
            'reason': reason,
          });
    }
    listing.status = status;
    if (status == ListingStatus.rejected) {
      listing.rejectionReasonRu = reason.isEmpty
          ? 'Отклонено владельцем приложения.'
          : reason;
    }
    notifyListeners();
  }

  Future<void> setOwnerBannerStatus(
    UserBannerAd banner,
    ListingStatus status, {
    String reason = '',
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final serverStatus = switch (status) {
      ListingStatus.pendingPayment => 'pending_payment',
      ListingStatus.ownerReview || ListingStatus.moderation => 'owner_review',
      ListingStatus.active => 'active',
      ListingStatus.rejected => 'rejected',
      ListingStatus.deleted => 'deleted',
      ListingStatus.archived || ListingStatus.draft => 'archived',
    };
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('ownerSetBannerStatus')
          .call({
            'bannerId': banner.id,
            'status': serverStatus,
            'reason': reason,
          });
    }
    banner.status = status;
    if (status == ListingStatus.rejected) {
      banner.rejectionReasonRu = reason.isEmpty
          ? 'Баннер отклонён владельцем приложения.'
          : reason;
    }
    notifyListeners();
  }

  Future<void> setSupportTicketStatus(
    SupportTicket ticket,
    String status, {
    String reply = '',
  }) async {
    if (!isOwner) throw StateError('owner_required');
    if (!['open', 'closed', 'resolved'].contains(status)) {
      throw StateError('invalid_support_status');
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('ownerSetSupportTicketStatus')
          .call({'ticketId': ticket.id, 'status': status, 'reply': reply});
    }
    final index = supportTickets.indexWhere((item) => item.id == ticket.id);
    if (index >= 0) {
      supportTickets[index] = SupportTicket(
        id: ticket.id,
        userId: ticket.userId,
        userName: ticket.userName,
        phone: ticket.phone,
        subject: ticket.subject,
        message: ticket.message,
        status: status,
        ownerReply: reply.trim().isNotEmpty ? reply.trim() : ticket.ownerReply,
        createdAt: ticket.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> resolveOwnerReport(
    OwnerReport report,
    String status, {
    String reason = '',
  }) async {
    if (!isOwner) throw StateError('owner_required');
    if (!['resolved', 'rejected'].contains(status)) {
      throw StateError('invalid_report_status');
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('ownerResolveReport').call(
        {'reportId': report.id, 'status': status, 'reason': reason},
      );
    }
    final index = ownerReports.indexWhere((item) => item.id == report.id);
    if (index >= 0) {
      ownerReports[index] = OwnerReport(
        id: report.id,
        reporterId: report.reporterId,
        reason: report.reason,
        status: status,
        createdAt: report.createdAt,
        type: report.type,
        listingId: report.listingId,
        chatId: report.chatId,
        messageId: report.messageId,
        reportedUserId: report.reportedUserId,
      );
      notifyListeners();
    }
  }

  Future<String> ownerSyncPayment(OwnerPayment payment) async {
    if (!isOwner) throw StateError('owner_required');
    final response = await FirebaseFunctions.instance
        .httpsCallable('ownerSyncPaymentStatus')
        .call<Map<String, dynamic>>({'paymentId': payment.id});
    final data = Map<String, dynamic>.from(response.data);
    await loadOwnerPaymentsFromFirebase();
    notifyListeners();
    return '${data['status'] ?? 'pending'}';
  }

  bool toggleFavorite(String listingId) {
    if (!isAuthorized) return false;
    final listing = listings.where((item) => item.id == listingId).firstOrNullC;
    if (favoriteIds.contains(listingId)) {
      favoriteIds.remove(listingId);
      if (listing != null && listing.favoriteCount > 0) {
        listing.favoriteCount--;
      }
    } else {
      favoriteIds.add(listingId);
      if (listing != null) listing.favoriteCount++;
    }
    notifyListeners();
    final favorite = favoriteIds.contains(listingId);
    logAnalyticsEvent(favorite ? 'add_to_favorites' : 'remove_from_favorites', {
      'listing_id': listingId,
    });
    unawaited(syncFavorite(listingId, favorite, listing));
    return true;
  }

  Future<void> syncFavorite(
    String listingId,
    bool favorite,
    ListingAd? listing,
  ) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('setListingFavorite').call(
        {'listingId': listingId, 'favorite': favorite},
      );
      await loadFavoritesFromFirebase();
    } catch (_) {
      if (!allowLocalFallback) {
        if (favoriteIds.contains(listingId)) {
          favoriteIds.remove(listingId);
          if (listing != null && listing.favoriteCount > 0) {
            listing.favoriteCount--;
          }
        } else {
          favoriteIds.add(listingId);
          if (listing != null) listing.favoriteCount++;
        }
        addLocalNotification('Не удалось сохранить избранное');
        notifyListeners();
      }
    }
  }

  void trackListingView(String listingId) {
    final listing = listings.where((item) => item.id == listingId).firstOrNullC;
    if (listing == null) return;
    listing.views++;
    logAnalyticsEvent('view_listing', {
      'listing_id': listing.id,
      'category_id': listing.categoryId,
      'city': listing.city,
    });
    notifyListeners();
    unawaited(syncListingView(listingId, listing));
  }

  Future<void> syncListingView(String listingId, ListingAd listing) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('trackListingView').call({
        'listingId': listingId,
      });
      await loadFromFirebase();
    } catch (_) {
      if (!allowLocalFallback && listing.views > 0) {
        listing.views--;
        notifyListeners();
      }
    }
  }

  ModerationResult moderateText({
    required String title,
    required String description,
    required int price,
    required String categoryId,
    required List<String> images,
  }) {
    final titleText = title.toLowerCase();
    final text = '$title $description'.toLowerCase();
    final hasIntimWithoutNegation =
        RegExp(r'\bинтим\w*').hasMatch(text) &&
        !RegExp(r'\bбез\s+интим\w*').hasMatch(text);
    if (RegExp(r'\bинтим\w*').hasMatch(titleText) || hasIntimWithoutNegation) {
      return const ModerationResult(
        decision: ModerationDecision.rejected,
        reasonRu:
            'Объявление отклонено: интим-услуги и услуги 18+ запрещены правилами сервиса.',
        reasonKk:
            'Хабарландыру қабылданбады: интим қызметтер мен 18+ қызметтеріне сервис ережелері бойынша тыйым салынған.',
        riskScore: .94,
      );
    }
    final blocked = ['наркот', 'оруж', 'поддел', 'мошен', 'ставк', 'казино'];
    if (blocked.any(text.contains)) {
      return const ModerationResult(
        decision: ModerationDecision.rejected,
        reasonRu: 'Объявление содержит запрещённый товар или услугу.',
        reasonKk: 'Хабарландыруда тыйым салынған тауар немесе қызмет бар.',
        riskScore: .96,
      );
    }
    if (price > 20000000) {
      return const ModerationResult(
        decision: ModerationDecision.rejected,
        reasonRu:
            'Объявление отклонено: цена выше допустимого лимита 20 000 000 ₸. Укажите реальную цену до 20 000 000 ₸ или выберите «Договорная».',
        reasonKk:
            'Хабарландыру қабылданбады: баға рұқсат етілген 20 000 000 ₸ шегінен жоғары.',
        riskScore: .62,
      );
    }
    return const ModerationResult(
      decision: ModerationDecision.approved,
      reasonRu: 'Объявление опубликовано.',
      reasonKk: 'Хабарландыру жарияланды.',
      riskScore: .08,
    );
  }

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
    if (!isAuthorized) {
      throw StateError('auth_required');
    }
    if (!allowLocalFallback) {
      final payload = {
        'id': 'listing_${DateTime.now().microsecondsSinceEpoch}',
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'city': city,
        'regionId': regionId,
        'district': district,
        'price': price,
        'condition': condition.name,
        'images': images,
        'phone': phone,
        'sellerType': 'private',
        'attributes': attributes,
        'skipModeration': isOwner,
      };
      final response = await FirebaseFunctions.instance
          .httpsCallable('createListing')
          .call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(response.data);
      final moderation = moderationResultFromData(data);
      final listing = ListingAd(
        id: '${data['listingId'] ?? payload['id']}',
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
        status: statusFromString('${data['status'] ?? 'ownerReview'}'),
        createdAt: DateTime.now(),
        sellerType: 'private',
        attributes: attributes,
        rejectionReasonRu: moderation.reasonRu,
        rejectionReasonKk: moderation.reasonKk,
      );
      listings.removeWhere((item) => item.id == listing.id);
      listings.insert(0, listing);
      notifyListeners();
      await loadMyListingsFromFirebase();
      await loadNotificationsFromFirebase();
      logAnalyticsEvent('create_listing', {
        'listing_id': listing.id,
        'category_id': categoryId,
        'city': city,
        'status': listing.status.name,
      });
      return listing;
    }
    final moderation = moderateText(
      title: title,
      description: description,
      price: price,
      categoryId: categoryId,
      images: images,
    );
    final id = 'listing_${DateTime.now().microsecondsSinceEpoch}';
    final status = switch (moderation.decision) {
      ModerationDecision.approved => ListingStatus.active,
      ModerationDecision.rejected => ListingStatus.rejected,
      ModerationDecision.ownerReview => ListingStatus.ownerReview,
    };
    final listing = ListingAd(
      id: id,
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
      status: status,
      createdAt: DateTime.now(),
      sellerType: 'private',
      attributes: attributes,
      rejectionReasonRu: moderation.reasonRu,
      rejectionReasonKk: moderation.reasonKk,
    );
    listings.insert(0, listing);
    if (status == ListingStatus.ownerReview) {
      addModerationCase('listing', listing.id, listing.title, moderation);
    }
    addLocalNotification('${listing.title}: ${listingStatusMessage(status)}');
    logAnalyticsEvent('create_listing', {
      'listing_id': listing.id,
      'category_id': categoryId,
      'city': city,
      'status': status.name,
    });
    notifyListeners();
    unawaited(
      _call('createListing', {
        ...listingPayload(listing),
        'regionId': regionId,
      }),
    );
    return listing;
  }

  Future<ListingAd> updateListing({
    required ListingAd listing,
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
    if (!isAuthorized) throw StateError('auth_required');
    if (!allowLocalFallback) {
      final response = await FirebaseFunctions.instance
          .httpsCallable('updateListing')
          .call<Map<String, dynamic>>({
            'listingId': listing.id,
            'title': title,
            'description': description,
            'categoryId': categoryId,
            'city': city,
            'regionId': regionId,
            'district': district,
            'price': price,
            'condition': condition.name,
            'images': images,
            'phone': phone,
            'attributes': attributes,
          });
      final data = Map<String, dynamic>.from(response.data);
      final moderation = moderationResultFromData(data);
      listing.status = statusFromString('${data['status'] ?? 'ownerReview'}');
      listing.title = title;
      listing.description = description;
      listing.categoryId = categoryId;
      listing.city = city;
      listing.district = district;
      listing.price = price;
      listing.condition = condition;
      listing.images = images;
      listing.attributes = Map<String, String>.from(attributes);
      listing.rejectionReasonRu = moderation.reasonRu;
      listing.rejectionReasonKk = moderation.reasonKk;
      if (isOwner) {
        await loadFromFirebase();
      } else {
        await loadMyListingsFromFirebase();
      }
      await loadNotificationsFromFirebase();
      return listing;
    } else {
      listing.status = ListingStatus.ownerReview;
    }
    listing.title = title;
    listing.description = description;
    listing.categoryId = categoryId;
    listing.city = city;
    listing.district = district;
    listing.price = price;
    listing.condition = condition;
    listing.images = images;
    listing.attributes = Map<String, String>.from(attributes);
    addLocalNotification(
      '${listing.title}: ${listingStatusMessage(listing.status)}',
    );
    notifyListeners();
    return listing;
  }

  Future<void> archiveListing(ListingAd listing) async {
    if (!isAuthorized) throw StateError('auth_required');
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('archiveListing').call({
        'listingId': listing.id,
      });
      await loadMyListingsFromFirebase();
      await loadNotificationsFromFirebase();
      return;
    }
    listing.status = ListingStatus.archived;
    addLocalNotification('${listing.title}: объявление в архиве');
    notifyListeners();
  }

  Future<void> restoreListing(ListingAd listing) async {
    if (!isAuthorized) throw StateError('auth_required');
    if (!listing.canRestoreFromArchive) {
      throw StateError('restore_expired');
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('restoreListing').call({
        'listingId': listing.id,
      });
      await loadMyListingsFromFirebase();
      await loadNotificationsFromFirebase();
      return;
    }
    listing.status = ListingStatus.active;
    listing.archivedAt = null;
    listing.restoreUntil = null;
    addLocalNotification('${listing.title}: объявление восстановлено');
    notifyListeners();
  }

  Future<void> trackListingCall(ListingAd listing) async {
    if (!isAuthorized || listing.isBusiness || listing.ownerId == userId) {
      return;
    }
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('trackListingCall').call({
        'listingId': listing.id,
      });
      return;
    }
  }

  Future<void> resolveListingCallNotification(
    AppNotification notification,
    bool agreed,
  ) async {
    final listingId = notification.data['listingId'] ?? '';
    if (listingId.isEmpty) throw StateError('listing_id_missing');
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('resolveListingCall').call(
        {
          'listingId': listingId,
          'notificationId': notification.id,
          'agreed': agreed,
        },
      );
      await loadMyListingsFromFirebase();
      await loadNotificationsFromFirebase();
      return;
    }
    final listing = listings.where((item) => item.id == listingId).firstOrNullC;
    if (listing != null && agreed) {
      listing.status = ListingStatus.archived;
      listing.archivedAt = DateTime.now();
      listing.restoreUntil = DateTime.now().add(const Duration(hours: 24));
    }
    notifyListeners();
  }

  Future<UserBannerAd> createBanner({
    required String title,
    required String caption,
    required String imageUrl,
  }) async {
    if (!isAuthorized) {
      throw StateError('auth_required');
    }
    if (!allowLocalFallback) {
      final response = await FirebaseFunctions.instance
          .httpsCallable('createBannerAd')
          .call<Map<String, dynamic>>({
            'id': 'banner_${DateTime.now().microsecondsSinceEpoch}',
            'title': title,
            'caption': caption,
            'imageUrl': imageUrl,
          });
      final data = Map<String, dynamic>.from(response.data);
      final moderation = moderationResultFromData(data);
      final banner = UserBannerAd(
        id: '${data['bannerId'] ?? ''}',
        ownerId: userId,
        title: title,
        caption: caption,
        imageUrl: imageUrl,
        status: statusFromString('${data['status'] ?? 'ownerReview'}'),
        createdAt: DateTime.now(),
        rejectionReasonRu: moderation.reasonRu,
      );
      banners.removeWhere((item) => item.id == banner.id);
      banners.insert(0, banner);
      notifyListeners();
      await loadFromFirebase();
      return banner;
    }
    final moderation = moderateText(
      title: title,
      description: caption,
      price: 1,
      categoryId: 'banner',
      images: imageUrl.isEmpty ? const [] : [imageUrl],
    );
    final status = switch (moderation.decision) {
      ModerationDecision.approved => ListingStatus.pendingPayment,
      ModerationDecision.rejected => ListingStatus.rejected,
      ModerationDecision.ownerReview => ListingStatus.ownerReview,
    };
    final banner = UserBannerAd(
      id: 'banner_${DateTime.now().microsecondsSinceEpoch}',
      ownerId: userId,
      title: title,
      caption: caption,
      imageUrl: imageUrl,
      status: status,
      createdAt: DateTime.now(),
      rejectionReasonRu: moderation.reasonRu,
    );
    banners.insert(0, banner);
    if (status == ListingStatus.ownerReview) {
      addModerationCase('banner', banner.id, banner.title, moderation);
    }
    notifyListeners();
    unawaited(_call('createBannerAd', bannerPayload(banner)));
    return banner;
  }

  Future<UserBannerAd> updateBanner({
    required UserBannerAd banner,
    required String title,
    required String caption,
    required String imageUrl,
  }) async {
    if (!isOwner) throw StateError('owner_required');
    final response = await FirebaseFunctions.instance
        .httpsCallable('ownerUpdateBanner')
        .call<Map<String, dynamic>>({
          'bannerId': banner.id,
          'title': title,
          'caption': caption,
          'imageUrl': imageUrl,
        });
    final data = Map<String, dynamic>.from(response.data);
    banner.title = title;
    banner.caption = caption;
    banner.imageUrl = imageUrl;
    banner.status = statusFromString('${data['status'] ?? 'ownerReview'}');
    await loadFromFirebase();
    return banner;
  }

  void addModerationCase(
    String type,
    String targetId,
    String title,
    ModerationResult result,
  ) {
    moderationCases.insert(
      0,
      ModerationCase(
        id: 'case_${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        targetId: targetId,
        title: title,
        reasonRu: result.reasonRu,
        reasonKk: result.reasonKk,
        riskScore: result.riskScore,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> ownerResolveCase(ModerationCase item, bool approve) async {
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('ownerResolveModerationCase')
          .call({
            'caseId': item.id,
            'targetId': item.targetId,
            'type': item.type,
            'decision': approve ? 'approved' : 'rejected',
          });
    }
    item.resolved = true;
    final listing = listings.where((l) => l.id == item.targetId).firstOrNullC;
    if (listing != null) {
      listing.status = approve ? ListingStatus.active : ListingStatus.rejected;
      listing.rejectionReasonRu = approve
          ? ''
          : 'Отклонено владельцем приложения.';
    }
    final banner = banners.where((b) => b.id == item.targetId).firstOrNullC;
    if (banner != null) {
      banner.status = approve
          ? ListingStatus.pendingPayment
          : ListingStatus.rejected;
      banner.rejectionReasonRu = approve
          ? ''
          : 'Отклонено владельцем приложения.';
    }
    notifyListeners();
    if (allowLocalFallback) {
      unawaited(
        _call('ownerResolveModerationCase', {
          'caseId': item.id,
          'targetId': item.targetId,
          'type': item.type,
          'decision': approve ? 'approved' : 'rejected',
        }),
      );
    }
  }

  Future<void> purchasePromotion(ListingAd listing, PromotionPlan plan) async {
    if (!paidPromotionEnabled) throw StateError('promotion_unavailable');
    if (!isAuthorized) {
      throw StateError('auth_required');
    }
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('purchasePromotion')
          .call<Map<String, dynamic>>({
            'listingId': listing.id,
            'planId': plan.id,
          });
      final data = Map<String, dynamic>.from(response.data);
      pendingPromotionPaymentId = '${data['paymentId'] ?? ''}';
      activatePromotionLocally(listing, plan);
      await loadMyListingsFromFirebase();
      logAnalyticsEvent('promotion_purchase_success', {
        'listing_id': listing.id,
        'plan_id': plan.id,
        'amount': plan.price,
      });
    } catch (error) {
      debugPrint('purchasePromotion failed: $error');
      rethrow;
    }
  }

  void activatePromotionLocally(ListingAd listing, PromotionPlan plan) {
    final until = DateTime.now().add(Duration(days: plan.days));
    if (plan.id == 'boost') listing.boostUntil = until;
    if (plan.id == 'top') listing.topUntil = until;
    if (plan.id == 'vip') listing.vipUntil = until;
    addLocalNotification('${localizedPlanTitle(plan)}: ${listing.title}');
    notifyListeners();
  }

  String localizedPlanTitle(PromotionPlan plan) =>
      plan.localizedTitle(language);

  Future<void> purchaseBannerPlacement(
    UserBannerAd banner,
    PromotionPlan plan,
  ) async {
    if (!paidPromotionEnabled) throw StateError('promotion_unavailable');
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('purchaseBannerPlacement')
          .call<Map<String, dynamic>>({
            'bannerId': banner.id,
            'planId': plan.id,
          });
      final data = Map<String, dynamic>.from(response.data);
      pendingPromotionPaymentId = '${data['paymentId'] ?? ''}';
      banner.status = ListingStatus.active;
      banner.activeUntil = DateTime.now().add(Duration(days: plan.days));
      notifyListeners();
      await loadFromFirebase();
      logAnalyticsEvent('banner_purchase_success', {
        'banner_id': banner.id,
        'plan_id': plan.id,
        'amount': plan.price,
      });
    } catch (error) {
      if (allowLocalFallback) {
        banner.status = ListingStatus.active;
        banner.activeUntil = DateTime.now().add(Duration(days: plan.days));
        notifyListeners();
        return;
      }
      rethrow;
    }
  }

  Future<ChatThread> openChat(ListingAd listing) async {
    if (!isAuthorized) throw StateError('auth_required');
    final chatIdParts = [listing.id, userId, listing.ownerId]..sort();
    final chatId = chatIdParts.join('_');
    final existing = chats.where((chat) {
      return chat.id == chatId ||
          (chat.listingId == listing.id &&
              chat.buyerId == userId &&
              chat.sellerId == listing.ownerId);
    }).firstOrNullC;
    if (existing != null) return existing;
    var resolvedChatId = chatId;
    if (!allowLocalFallback) {
      final response = await FirebaseFunctions.instance
          .httpsCallable('createChatRoom')
          .call<Map<String, dynamic>>({'listingId': listing.id});
      final data = Map<String, dynamic>.from(response.data);
      resolvedChatId = '${data['chatId'] ?? chatId}';
    }
    final chat = ChatThread(
      id: resolvedChatId,
      listingId: listing.id,
      buyerId: userId,
      sellerId: listing.ownerId,
      title: listing.title,
      messages: [],
    );
    chats.insert(0, chat);
    logAnalyticsEvent('open_chat', {
      'listing_id': listing.id,
      'chat_id': chat.id,
    });
    notifyListeners();
    return chat;
  }

  Future<void> sendMessage(
    ChatThread chat,
    String text, {
    String imageUrl = '',
    String fileUrl = '',
    String fileName = '',
  }) async {
    final messageText = text.trim();
    if (messageText.isEmpty && imageUrl.isEmpty && fileUrl.isEmpty) return;
    var flagged = false;
    var messageId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('sendMessage')
          .call<Map<String, dynamic>>({
            'chatId': chat.id,
            'text': messageText,
            'imageUrl': imageUrl,
            'fileUrl': fileUrl,
            'fileName': fileName,
          });
      final data = Map<String, dynamic>.from(response.data);
      messageId = '${data['messageId'] ?? messageId}';
      final status = '${data['status'] ?? ''}';
      if (status == 'blocked') {
        await loadNotificationsFromFirebase();
        notifyListeners();
        return;
      }
      flagged = status == 'owner_review';
      if (!allowLocalFallback) {
        chat.messages.add(
          ChatMessage(
            id: messageId,
            senderId: userId,
            text: flagged ? 'Сообщение отправлено на проверку' : messageText,
            createdAt: DateTime.now(),
            imageUrl: flagged ? '' : imageUrl,
            fileUrl: flagged ? '' : fileUrl,
            fileName: flagged ? '' : fileName,
            flagged: flagged,
          ),
        );
        notifyListeners();
        await loadChatsFromFirebase();
        await loadNotificationsFromFirebase();
        logAnalyticsEvent('send_message', {
          'chat_id': chat.id,
          'status': status.isEmpty ? 'sent' : status,
          'has_image': imageUrl.isNotEmpty ? 'true' : 'false',
          'has_file': fileUrl.isNotEmpty ? 'true' : 'false',
        });
        return;
      }
    } catch (error) {
      if (!allowLocalFallback) rethrow;
      debugPrint('sendMessage local fallback: $error');
      flagged =
          moderateText(
            title: chat.title,
            description: messageText,
            price: 1,
            categoryId: 'message',
            images: const ['message'],
          ).decision !=
          ModerationDecision.approved;
    }
    chat.messages.add(
      ChatMessage(
        id: messageId,
        senderId: userId,
        text: flagged ? 'Сообщение отправлено на проверку' : messageText,
        createdAt: DateTime.now(),
        imageUrl: flagged ? '' : imageUrl,
        fileUrl: flagged ? '' : fileUrl,
        fileName: flagged ? '' : fileName,
        flagged: flagged,
      ),
    );
    logAnalyticsEvent('send_message', {
      'chat_id': chat.id,
      'status': flagged ? 'owner_review' : 'sent',
      'has_image': imageUrl.isNotEmpty ? 'true' : 'false',
      'has_file': fileUrl.isNotEmpty ? 'true' : 'false',
    });
    if (flagged) {
      addModerationCase(
        'message',
        chat.id,
        chat.title,
        const ModerationResult(
          decision: ModerationDecision.ownerReview,
          reasonRu: 'Сообщение отправлено на проверку.',
          reasonKk: 'Хабарлама тексеруге жіберілді.',
          riskScore: .7,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> deleteMessage(
    ChatThread chat,
    ChatMessage message, {
    String reason = '',
  }) async {
    if (message.senderId != userId && !isOwner) return;
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('deleteMessage').call({
        'chatId': chat.id,
        'messageId': message.id,
        'reason': reason.trim(),
      });
      message.deleted = true;
      message.text = 'Сообщение удалено';
      message.imageUrl = '';
      message.fileUrl = '';
      message.fileName = '';
      notifyListeners();
      return;
    }
    message.deleted = true;
    message.text = 'Сообщение удалено';
    message.imageUrl = '';
    message.fileUrl = '';
    message.fileName = '';
    notifyListeners();
    unawaited(
      _call('deleteMessage', {
        'chatId': chat.id,
        'messageId': message.id,
        'reason': reason.trim(),
      }),
    );
  }

  Future<void> loadBlockedMarketplaceUsers() async {
    if (allowLocalFallback) return;
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('getBlockedMarketplaceUsers')
          .call<Map<String, dynamic>>();
      blockedUserIds
        ..clear()
        ..addAll(
          (response.data['userIds'] as List? ?? []).map((value) => '$value'),
        );
      notifyListeners();
    } catch (error) {
      debugPrint('Blocked users load: $error');
    }
  }

  Future<void> blockMarketplaceUser(String target, bool blocked) async {
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance
          .httpsCallable('blockMarketplaceUser')
          .call({'userId': target, 'blocked': blocked});
    }
    if (blocked) {
      blockedUserIds.add(target);
    } else {
      blockedUserIds.remove(target);
    }
    notifyListeners();
  }

  Future<void> reportMessage(
    ChatThread chat,
    ChatMessage message,
    String reason,
  ) async {
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('reportMessage').call({
        'chatId': chat.id,
        'messageId': message.id,
        'reason': reason,
      });
      notifyListeners();
      return;
    }
    addModerationCase(
      'message',
      '${chat.id}/${message.id}',
      chat.title,
      ModerationResult(
        decision: ModerationDecision.ownerReview,
        reasonRu: reason,
        reasonKk: reason,
        riskScore: .8,
      ),
    );
    addLocalNotification('Жалоба на сообщение отправлена владельцу');
    notifyListeners();
    unawaited(
      _call('reportMessage', {
        'chatId': chat.id,
        'messageId': message.id,
        'reason': reason,
      }),
    );
  }

  Future<void> reportListing(ListingAd listing, String reason) async {
    if (!allowLocalFallback) {
      await FirebaseFunctions.instance.httpsCallable('reportListing').call({
        'listingId': listing.id,
        'reason': reason,
      });
      notifyListeners();
      return;
    }
    addModerationCase(
      'report',
      listing.id,
      listing.title,
      ModerationResult(
        decision: ModerationDecision.ownerReview,
        reasonRu: reason,
        reasonKk: reason,
        riskScore: .75,
      ),
    );
    addLocalNotification('Жалоба отправлена владельцу приложения');
    notifyListeners();
    unawaited(
      _call('reportListing', {'listingId': listing.id, 'reason': reason}),
    );
  }

  Future<String> uploadImage(XFile image, String folder) async {
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) throw StateError('empty_image');
    if (demoAuthenticationEnabled && allowLocalFallback) {
      if (bytes.length > 10 * 1024 * 1024) throw StateError('file_too_large');
      return 'data:${image.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}';
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? userId;
    final extension = image.name.split('.').last.toLowerCase();
    final safeExtension = ['jpg', 'jpeg', 'png', 'webp'].contains(extension)
        ? extension
        : 'jpg';
    final metadata = SettableMetadata(
      contentType: safeExtension == 'png'
          ? 'image/png'
          : safeExtension == 'webp'
          ? 'image/webp'
          : 'image/jpeg',
    );
    final ref = FirebaseStorage.instance.ref(
      '$folder/$uid/${DateTime.now().microsecondsSinceEpoch}.$safeExtension',
    );
    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  Future<String> uploadChatFile(PlatformFile file) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? userId;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) throw StateError('empty_file');
    if (bytes.length > 12 * 1024 * 1024) throw StateError('file_too_large');
    final extension = (file.extension ?? 'file').toLowerCase();
    final safeExtension = extension.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final metadata = SettableMetadata(
      contentType: switch (safeExtension) {
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        _ => 'application/octet-stream',
      },
    );
    final ref = FirebaseStorage.instance.ref(
      'chatFiles/$uid/${DateTime.now().microsecondsSinceEpoch}.$safeExtension',
    );
    await ref.putData(bytes, metadata);
    return ref.getDownloadURL();
  }

  Future<void> _call(String name, Map<String, dynamic> data) async {
    try {
      await FirebaseFunctions.instance.httpsCallable(name).call(data);
    } catch (error) {
      debugPrint('$name skipped: $error');
    }
  }

  Future<String> syncPendingPaymentStatus() async {
    final paymentId = pendingPromotionPaymentId;
    if (paymentId == null || paymentId.isEmpty) return 'none';
    final response = await FirebaseFunctions.instance
        .httpsCallable('syncKassa24PaymentStatus')
        .call<Map<String, dynamic>>({'paymentId': paymentId});
    final data = Map<String, dynamic>.from(response.data);
    final status = '${data['status'] ?? 'pending'}';
    if (status == 'paid') {
      pendingPromotionPaymentId = null;
      await loadFromFirebase();
      addLocalNotification('Оплата подтверждена');
      logAnalyticsEvent('payment_success', {'payment_id': paymentId});
      notifyListeners();
    } else if (status == 'failed') {
      pendingPromotionPaymentId = null;
      logAnalyticsEvent('payment_failed', {'payment_id': paymentId});
      notifyListeners();
    }
    return status;
  }

  Map<String, dynamic> listingPayload(ListingAd item) => {
    'id': item.id,
    'title': item.title,
    'description': item.description,
    'categoryId': item.categoryId,
    'city': item.city,
    'district': item.district,
    'price': item.price,
    'condition': item.condition.name,
    'images': item.images,
    'phone': item.phone,
    'sellerType': item.sellerType,
    'attributes': item.attributes,
  };

  Map<String, dynamic> bannerPayload(UserBannerAd item) => {
    'id': item.id,
    'title': item.title,
    'caption': item.caption,
    'imageUrl': item.imageUrl,
  };

  @override
  void dispose() {
    unawaited(fcmTokenRefreshSubscription?.cancel());
    super.dispose();
  }
}

const categoryIconOptions = <String, IconData>{
  'grid': Icons.grid_view_rounded,
  'transport': Icons.directions_car_rounded,
  'parts': Icons.settings_suggest_rounded,
  'real_estate': Icons.apartment_rounded,
  'electronics': Icons.phone_iphone_rounded,
  'home': Icons.chair_rounded,
  'jobs': Icons.work_outline_rounded,
  'services': Icons.handyman_rounded,
  'construction_repair': Icons.construction_rounded,
  'rent': Icons.event_repeat_rounded,
  'fashion': Icons.checkroom_rounded,
  'kids': Icons.toys_rounded,
  'hobby_sport': Icons.sports_soccer_rounded,
  'animals': Icons.pets_rounded,
  'free': Icons.volunteer_activism_rounded,
};

IconData iconForCategory(String key) {
  return categoryIconOptions[key] ?? Icons.grid_view_rounded;
}

ListingCondition conditionFromString(String value) {
  return ListingCondition.values.firstWhere(
    (item) => item.name == value,
    orElse: () => ListingCondition.used,
  );
}

ListingStatus statusFromString(String value) {
  final normalized = value.trim();
  if (normalized == 'pending_payment') return ListingStatus.pendingPayment;
  if (normalized == 'owner_review') return ListingStatus.ownerReview;
  return ListingStatus.values.firstWhere(
    (item) => item.name == normalized,
    orElse: () => ListingStatus.ownerReview,
  );
}

class NumberParser {
  const NumberParser._();
  static int toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? 0}'.replaceAll(RegExp(r'\D'), '')) ?? 0;
  }

  static double toDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? 0}'.replaceAll(',', '.')) ?? 0;
  }
}

class ClassifiedsApp extends StatefulWidget {
  const ClassifiedsApp({
    super.key,
    this.initialStore,
    this.loadLocalPreferences = true,
    this.installErrorWidget = true,
  });

  final ClassifiedsStore? initialStore;
  final bool loadLocalPreferences;
  final bool installErrorWidget;

  @override
  State<ClassifiedsApp> createState() => _ClassifiedsAppState();
}

class _ClassifiedsAppState extends State<ClassifiedsApp> {
  late final store =
      widget.initialStore ??
      (demoAuthenticationEnabled
          ? ClassifiedsStore.demo()
          : ClassifiedsStore());

  @override
  void initState() {
    super.initState();
    logAnalyticsEvent('app_open');
    store.addListener(_changed);
    if (widget.loadLocalPreferences) {
      unawaited(store.loadLocalPreferences());
    } else {
      store.localPreferencesLoaded = true;
    }
    unawaited(store.loadFromFirebase());
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ClassifiedsScope(
      controller: store,
      child: MaterialApp(
        title: 'PUSHKA',
        debugShowCheckedModeBanner: false,
        theme: classifiedsTheme(),
        builder: (context, child) {
          if (widget.installErrorWidget) {
            ErrorWidget.builder = (details) => Material(
              color: cBg,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CGlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ошибка экрана',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          details.exceptionAsString(),
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: cMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          final content = child ?? const SizedBox.shrink();
          return demoAuthenticationEnabled
              ? Banner(
                  message: 'ТЕСТ',
                  location: BannerLocation.topEnd,
                  color: cBlue,
                  child: content,
                )
              : content;
        },
        home: isAdminHostingHost
            ? AdminOnlyGate(store: store)
            : !store.localPreferencesLoaded
            ? const CLoadingScreen()
            : !store.languageSelected
            ? const CLanguageScreen()
            : store.needsProfileCompletion
            ? const CompleteProfileScreen()
            : store.isOwner
            ? const OwnerShell()
            : const ClassifiedsShell(),
      ),
    );
  }
}

class AdminOnlyGate extends StatelessWidget {
  const AdminOnlyGate({required this.store, super.key});
  final ClassifiedsStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.localPreferencesLoaded) {
      return const CLoadingScreen();
    }
    if (!store.isAuthorized) {
      return const AdminLoginScreen();
    }
    if (!store.isOwner) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CBrandHeader(
                  trailing: IconButton(
                    onPressed: store.logout,
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ),
                const Spacer(),
                const EmptyState(
                  title: 'Нет доступа',
                  text:
                      'Этот домен доступен только владельцу и администраторам.',
                  icon: Icons.admin_panel_settings_outlined,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: store.logout,
                  child: const Text('Выйти'),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }
    return const OwnerShell();
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final phone = TextEditingController();
  final code = TextEditingController();
  bool codeSent = false;
  bool busy = false;

  bool get phoneReady =>
      normalizePhone(phone.text).replaceAll(RegExp(r'\D'), '').length == 11;

  bool get codeReady => code.text.replaceAll(RegExp(r'\D'), '').length >= 4;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> requestCode() async {
    if (!phoneReady || busy) return;
    setState(() => busy = true);
    try {
      await ClassifiedsScope.of(context).requestOtp(phone.text);
      if (mounted) setState(() => codeSent = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Код: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signIn() async {
    if (!codeReady || busy) return;
    setState(() => busy = true);
    try {
      final ok = await ClassifiedsScope.of(context).verifyOtp(code.text);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Неверный код')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Вход: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CBrandHeader(),
            const SizedBox(height: 38),
            const Text(
              'Админка PUSHKA',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Вход только для владельца и администраторов.',
              style: TextStyle(color: cMuted),
            ),
            const SizedBox(height: 24),
            CGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: phone,
                    enabled: !codeSent && !busy,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [KazakhstanPhoneFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      hintText: '+7 (___) ___-__-__',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 14),
                    Text(
                      store.pendingOtpCode == null
                          ? 'Введите код подтверждения'
                          : 'Код: ${store.pendingOtpCode}',
                      style: const TextStyle(color: cMuted),
                    ),
                    const SizedBox(height: 12),
                    OtpCellsField(
                      controller: code,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : codeSent
                        ? signIn
                        : requestCode,
                    child: Text(
                      busy
                          ? 'Подождите...'
                          : codeSent
                          ? 'Войти'
                          : 'Получить код',
                    ),
                  ),
                  if (codeSent)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              codeSent = false;
                              code.clear();
                            }),
                      child: const Text('Изменить номер'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ThemeData classifiedsTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: cBlue, primary: cBlue),
    scaffoldBackgroundColor: cBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: cBg,
      foregroundColor: cNavy,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: cLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: cLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: cBlue),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cBlue,
        side: const BorderSide(color: cBlue),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

class ClassifiedsScope extends InheritedNotifier<ClassifiedsStore> {
  const ClassifiedsScope({
    required ClassifiedsStore controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ClassifiedsStore of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ClassifiedsScope>();
    if (scope?.notifier == null) throw StateError('ClassifiedsScope missing');
    return scope!.notifier!;
  }
}

class CLoadingScreen extends StatelessWidget {
  const CLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class CLanguageScreen extends StatelessWidget {
  const CLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CBrandHeader(),
              const Spacer(),
              const Text(
                'Выберите язык',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              CGlassCard(
                child: Column(
                  children: [
                    RadioListTile<ClassifiedsLanguage>(
                      value: ClassifiedsLanguage.ru,
                      groupValue: store.language,
                      onChanged: (value) {
                        store.language = value!;
                        store.notifyListeners();
                      },
                      title: const Text('Русский'),
                    ),
                    RadioListTile<ClassifiedsLanguage>(
                      value: ClassifiedsLanguage.kk,
                      groupValue: store.language,
                      onChanged: (value) {
                        store.language = value!;
                        store.notifyListeners();
                      },
                      title: const Text('Қазақша'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  store.languageSelected = true;
                  unawaited(store.saveSession());
                  store.notifyListeners();
                },
                child: const Text('Продолжить'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class ClassifiedsShell extends StatelessWidget {
  const ClassifiedsShell({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final screens = const [
      ClassifiedsHomeScreen(),
      ClassifiedsCatalogScreen(),
      CreateListingScreen(),
      ChatsScreen(),
      ClassifiedsProfileScreen(),
    ];
    return Scaffold(
      body: screens[store.selectedTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: store.selectedTab,
        onDestinationSelected: store.selectTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            label: store.tx('Главная', 'Басты'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_rounded),
            label: store.tx('Категории', 'Санаттар'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_rounded),
            label: store.tx('Добавить', 'Қосу'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: store.tx('Чаты', 'Чаттар'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            label: store.tx('Профиль', 'Профиль'),
          ),
        ],
      ),
    );
  }
}

class CBrandHeader extends StatelessWidget {
  const CBrandHeader({this.trailing, super.key});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: cShadow, blurRadius: 16, offset: Offset(0, 8)),
            ],
          ),
          child: Image.asset('assets/brand/pushka_logo.png', fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'PUSHKA',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cDeepBlue,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class CGlassCard extends StatelessWidget {
  const CGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cLine),
        boxShadow: const [
          BoxShadow(color: cShadow, blurRadius: 22, offset: Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class ClassifiedsHomeScreen extends StatelessWidget {
  const ClassifiedsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          CBrandHeader(
            trailing: IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsLogScreen(),
                ),
              ),
              icon: Badge(
                isLabelVisible: store.unreadNotificationCount > 0,
                label: Text('${min(9, store.unreadNotificationCount)}'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: store.setSearch,
            decoration: InputDecoration(
              hintText: store.tx('Поиск объявлений', 'Хабарландыру іздеу'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ListingFiltersSheet(),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (store.firebaseLoadError.isNotEmpty) ...[
            FirebaseErrorBanner(error: store.firebaseLoadError),
            const SizedBox(height: 16),
          ],
          const UserBannersCarousel(),
          const SizedBox(height: 20),
          SectionHeader(title: store.tx('Категории', 'Санаттар'), action: ''),
          const SizedBox(height: 10),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: store.categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  CategoryPill(category: store.categories[index]),
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: store.tx('ТОП объявления', 'ТОП хабарландырулар'),
            action: '',
          ),
          const SizedBox(height: 10),
          ListingHorizontalList(
            listings: store.promotedListings.isEmpty
                ? store.publicListings.take(5).toList()
                : store.promotedListings,
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: store.tx('Свежие объявления', 'Жаңа хабарландырулар'),
            action: '',
          ),
          const SizedBox(height: 10),
          ...store.publicListings
              .take(10)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListingRowCard(listing: item),
                ),
              ),
        ],
      ),
    );
  }
}

class UserBannersCarousel extends StatelessWidget {
  const UserBannersCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final banners = store.activeBanners;
    final banner = banners.isEmpty ? null : banners.first;
    if (banner == null) return const SizedBox.shrink();
    return Container(
      height: 170,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cSoftBlue,
        boxShadow: const [
          BoxShadow(color: cShadow, blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: banner?.imageUrl.isNotEmpty == true
                ? CNetworkOrAssetImage(banner!.imageUrl, fit: BoxFit.cover)
                : const Center(
                    child: Icon(Icons.image_outlined, color: cBlue, size: 34),
                  ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, required this.action, super.key});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: cNavy,
            ),
          ),
        ),
        if (action.isNotEmpty)
          Text(
            action,
            style: const TextStyle(color: cBlue, fontWeight: FontWeight.w800),
          ),
      ],
    );
  }
}

class FirebaseErrorBanner extends StatelessWidget {
  const FirebaseErrorBanner({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFC9BD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFC43D22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              store.tx(
                'Не удалось загрузить данные из Firebase.',
                'Firebase деректерін жүктеу мүмкін болмады.',
              ),
              style: const TextStyle(color: cNavy, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => store.loadFromFirebase(),
            child: Text(store.tx('Повторить', 'Қайталау')),
          ),
        ],
      ),
    );
  }
}

class CategoryPill extends StatelessWidget {
  const CategoryPill({required this.category, super.key});
  final ListingCategory category;
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return InkWell(
      onTap: () => store.selectCategory(category.id),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 104,
        height: 112,
        child: CGlassCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, color: cBlue, size: 28),
              const SizedBox(height: 6),
              Text(
                category.title(store.language),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ListingHorizontalList extends StatelessWidget {
  const ListingHorizontalList({required this.listings, super.key});
  final List<ListingAd> listings;
  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return const EmptyState(
        title: 'Объявлений пока нет',
        text: 'Добавьте своё объявление или выберите другую категорию.',
        icon: Icons.storefront_outlined,
      );
    }
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: listings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => SizedBox(
          width: 176,
          child: ListingSmallCard(listing: listings[index]),
        ),
      ),
    );
  }
}

class ListingSmallCard extends StatelessWidget {
  const ListingSmallCard({required this.listing, super.key});
  final ListingAd listing;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailsScreen(listingId: listing.id),
        ),
      ),
      borderRadius: BorderRadius.circular(18),
      child: CGlassCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ListingImage(listing: listing)),
            const SizedBox(height: 8),
            Text(
              cMoney(listing.price),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(listing.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              listing.city,
              style: const TextStyle(color: cMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class ListingRowCard extends StatelessWidget {
  const ListingRowCard({required this.listing, super.key});
  final ListingAd listing;
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ListingDetailsScreen(listingId: listing.id),
        ),
      ),
      borderRadius: BorderRadius.circular(18),
      child: CGlassCard(
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: ListingImage(listing: listing),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (listing.isPromoted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cSoftBlue,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            'TOP',
                            style: TextStyle(
                              color: cBlue,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          if (!store.toggleFavorite(listing.id)) {
                            showAuthSheet(context);
                          }
                        },
                        icon: Icon(
                          store.favoriteIds.contains(listing.id)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    cMoney(listing.price),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${listing.city}, ${listing.district}',
                    style: const TextStyle(color: cMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ListingImage extends StatelessWidget {
  const ListingImage({required this.listing, super.key});
  final ListingAd listing;
  @override
  Widget build(BuildContext context) {
    final source = listing.images.isEmpty ? '' : listing.images.first;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cSoftBlue,
        borderRadius: BorderRadius.circular(14),
      ),
      child: source.isEmpty
          ? const Icon(Icons.image_outlined, color: cBlue, size: 42)
          : CNetworkOrAssetImage(source, fit: BoxFit.cover),
    );
  }
}

class ListingGallery extends StatefulWidget {
  const ListingGallery({required this.listing, super.key});
  final ListingAd listing;

  @override
  State<ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends State<ListingGallery> {
  final controller = PageController();
  int index = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.listing.images;
    if (images.isEmpty) {
      return ListingImage(listing: widget.listing);
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: PageView.builder(
            controller: controller,
            itemCount: images.length,
            onPageChanged: (value) => setState(() => index = value),
            itemBuilder: (context, imageIndex) => GestureDetector(
              onTap: () => showListingPhotoViewer(
                context,
                images,
                initialIndex: imageIndex,
              ),
              child: ColoredBox(
                color: cSoftBlue,
                child: CNetworkOrAssetImage(
                  images[imageIndex],
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${index + 1}/${images.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                images.length,
                (dotIndex) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: dotIndex == index ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: dotIndex == index
                        ? cBlue
                        : Colors.white.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

void showListingPhotoViewer(
  BuildContext context,
  List<String> images, {
  required int initialIndex,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) =>
        _ListingPhotoViewer(images: images, initialIndex: initialIndex),
  );
}

class _ListingPhotoViewer extends StatefulWidget {
  const _ListingPhotoViewer({required this.images, required this.initialIndex});
  final List<String> images;
  final int initialIndex;

  @override
  State<_ListingPhotoViewer> createState() => _ListingPhotoViewerState();
}

class _ListingPhotoViewerState extends State<_ListingPhotoViewer> {
  late final controller = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() => index = value),
              itemBuilder: (context, imageIndex) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CNetworkOrAssetImage(
                    widget.images[imageIndex],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              right: 16,
              top: 18,
              child: Text(
                '${index + 1}/${widget.images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CNetworkOrAssetImage extends StatelessWidget {
  const CNetworkOrAssetImage(this.source, {this.fit = BoxFit.cover, super.key});
  final String source;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    if (source.startsWith('data:image/')) {
      return Image.memory(
        UriData.parse(source).contentAsBytes(),
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_outlined),
      );
    }
    if (source.startsWith('http')) {
      return Image.network(
        source,
        fit: fit,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.image_not_supported_outlined),
      );
    }
    return Image.asset(
      source,
      fit: fit,
      errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined),
    );
  }
}

class ClassifiedsCatalogScreen extends StatelessWidget {
  const ClassifiedsCatalogScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const CBrandHeader(),
          const SizedBox(height: 18),
          Text(
            store.tx('Категории', 'Санаттар'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: store.categories.map((category) {
              final selected = store.selectedCategoryId == category.id;
              return ChoiceChip(
                selected: selected,
                label: Text(category.title(store.language)),
                avatar: Icon(
                  category.icon,
                  size: 18,
                  color: selected ? Colors.white : cBlue,
                ),
                onSelected: (_) => store.selectCategory(category.id),
                selectedColor: cBlue,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : cNavy,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (store.firebaseLoadError.isNotEmpty) ...[
            FirebaseErrorBanner(error: store.firebaseLoadError),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const ListingFiltersSheet(),
            ),
            icon: const Icon(Icons.tune_rounded),
            label: Text(
              store.tx('Фильтры и сортировка', 'Сүзгі және сұрыптау'),
            ),
          ),
          const SizedBox(height: 16),
          if (store.publicListings.isEmpty)
            EmptyState(
              title: store.tx('Ничего не найдено', 'Ештеңе табылмады'),
              text: store.tx(
                'Измените поиск или фильтры.',
                'Іздеу немесе сүзгіні өзгертіңіз.',
              ),
              icon: Icons.search_off_rounded,
            )
          else
            ...store.publicListings.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListingRowCard(listing: item),
              ),
            ),
        ],
      ),
    );
  }
}

class ListingFiltersSheet extends StatefulWidget {
  const ListingFiltersSheet({super.key});
  @override
  State<ListingFiltersSheet> createState() => _ListingFiltersSheetState();
}

class _ListingFiltersSheetState extends State<ListingFiltersSheet> {
  late RangeValues price;
  late bool withPhoto;
  late bool promoted;
  late bool negotiable;
  late String categoryId;
  late String subcategoryId;
  late String city;
  late String condition;
  late String sort;
  late Map<String, String> attributes;
  @override
  void initState() {
    super.initState();
    final store = ClassifiedsScope.of(context);
    price = RangeValues(
      store.minPrice.toDouble(),
      store.maxPrice.clamp(100000, 100000000).toDouble(),
    );
    withPhoto = store.onlyWithPhoto;
    promoted = store.onlyPromoted;
    negotiable = store.includeNegotiable;
    categoryId = store.selectedCategoryId;
    subcategoryId = store.selectedSubcategoryId;
    city = store.filterCity;
    condition = store.selectedCondition;
    sort = store.sortMode;
    attributes = Map<String, String>.from(store.selectedAttributeFilters);
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final selectedCategory = store.categories
        .where((item) => item.id == categoryId)
        .firstOrNullC;
    final subcategories = selectedCategory?.subcategories ?? const [];
    final attributeFilters = store.attributeFiltersFor(
      subcategoryId != 'all' ? subcategoryId : categoryId,
    );
    return SheetFrame(
      title: store.tx('Фильтры', 'Сүзгілер'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: 'Категория'),
            items: store.categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.title(store.language)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              categoryId = value ?? 'all';
              subcategoryId = 'all';
              attributes.clear();
            }),
          ),
          const SizedBox(height: 10),
          if (subcategories.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: subcategoryId,
              decoration: const InputDecoration(labelText: 'Подкатегория'),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Все')),
                ...subcategories.map(
                  (subcategory) => DropdownMenuItem(
                    value: subcategory.id,
                    child: Text(subcategory.title(store.language)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() {
                subcategoryId = value ?? 'all';
                attributes.clear();
              }),
            ),
          const SizedBox(height: 10),
          ...attributeFilters.map(
            (filter) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                initialValue: attributes[filter.id] ?? 'all',
                decoration: InputDecoration(
                  labelText: filter.title(store.language),
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Все')),
                  ...filter.options.map(
                    (option) =>
                        DropdownMenuItem(value: option, child: Text(option)),
                  ),
                ],
                onChanged: (value) => setState(() {
                  if (value == null || value == 'all') {
                    attributes.remove(filter.id);
                  } else {
                    attributes[filter.id] = value;
                  }
                }),
              ),
            ),
          ),
          InkWell(
            onTap: () => showFilterCitySheet(
              context,
              selectedCity: city,
              onSelected: (value) => setState(() => city = value),
            ),
            borderRadius: BorderRadius.circular(16),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Город',
                suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
              ),
              child: Text(city == 'all' ? 'Все города' : city),
            ),
          ),
          const SizedBox(height: 14),
          Text('${cMoney(price.start.round())} - ${cMoney(price.end.round())}'),
          RangeSlider(
            values: price,
            min: 0,
            max: 100000000,
            divisions: 100,
            onChanged: (value) => setState(() => price = value),
          ),
          CheckboxListTile(
            value: withPhoto,
            onChanged: (v) => setState(() => withPhoto = v ?? false),
            title: const Text('Только с фото'),
          ),
          CheckboxListTile(
            value: promoted,
            onChanged: (v) => setState(() => promoted = v ?? false),
            title: const Text('ТОП/VIP'),
          ),
          CheckboxListTile(
            value: negotiable,
            onChanged: (v) => setState(() => negotiable = v ?? true),
            title: const Text('Показывать договорную цену'),
          ),
          DropdownButtonFormField<String>(
            initialValue: condition,
            decoration: const InputDecoration(labelText: 'Состояние'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Любое')),
              DropdownMenuItem(value: 'newItem', child: Text('Новое')),
              DropdownMenuItem(value: 'used', child: Text('Б/у')),
              DropdownMenuItem(value: 'broken', child: Text('На запчасти')),
            ],
            onChanged: (value) => setState(() => condition = value ?? 'all'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: sort,
            decoration: const InputDecoration(labelText: 'Сортировка'),
            items: const [
              DropdownMenuItem(
                value: 'recommended',
                child: Text('Рекомендованное'),
              ),
              DropdownMenuItem(value: 'newest', child: Text('Сначала новые')),
              DropdownMenuItem(value: 'popular', child: Text('Популярные')),
              DropdownMenuItem(
                value: 'price_asc',
                child: Text('Сначала дешевле'),
              ),
              DropdownMenuItem(
                value: 'price_desc',
                child: Text('Сначала дороже'),
              ),
            ],
            onChanged: (value) => setState(() => sort = value ?? 'recommended'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              store.applyFilters(
                min: price.start.round(),
                max: price.end.round(),
                withPhoto: withPhoto,
                promoted: promoted,
                negotiable: negotiable,
                condition: condition,
                categoryId: categoryId,
                subcategoryId: subcategoryId,
                city: city,
                sort: sort,
                attributes: attributes,
              );
              Navigator.of(context).pop();
            },
            child: const Text('Показать объявления'),
          ),
          if (store.isAuthorized) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                store.applyFilters(
                  min: price.start.round(),
                  max: price.end.round(),
                  withPhoto: withPhoto,
                  promoted: promoted,
                  negotiable: negotiable,
                  condition: condition,
                  categoryId: categoryId,
                  subcategoryId: subcategoryId,
                  city: city,
                  sort: sort,
                  attributes: attributes,
                );
                await store.saveCurrentSearch();
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Поиск сохранен')));
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Сохранить поиск'),
            ),
          ],
        ],
      ),
    );
  }
}

class ListingDetailsScreen extends StatefulWidget {
  const ListingDetailsScreen({required this.listingId, super.key});
  final String listingId;

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  bool tracked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!tracked) {
      tracked = true;
      ClassifiedsScope.of(context).trackListingView(widget.listingId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final listing = store.listings.firstWhere(
      (item) => item.id == widget.listingId,
    );
    return Scaffold(
      appBar: AppBar(title: const CBrandHeader(), titleSpacing: 0),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = phoneUri(listing.phone);
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (opened) {
                      unawaited(store.trackListingCall(listing));
                    }
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Не удалось открыть звонилку: ${listing.phone}',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Позвонить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(
                      whatsAppUri(listing.phone),
                      mode: LaunchMode.externalApplication,
                    );
                    if (opened) {
                      unawaited(store.trackListingCall(listing));
                    }
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Не удалось открыть WhatsApp'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      final chat = await store.openChat(listing);
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatDetailsScreen(chatId: chat.id),
                        ),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      if (!store.isAuthorized) {
                        showAuthSheet(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Чат: ${cFriendlyError(error)}'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('Написать'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          SizedBox(height: 330, child: ListingGallery(listing: listing)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  cMoney(listing.price),
                  style: const TextStyle(
                    color: cBlue,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => store.toggleFavorite(listing.id),
                icon: Icon(
                  store.favoriteIds.contains(listing.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
            ],
          ),
          Text(
            listing.title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '${listing.city}, ${listing.district}',
            style: const TextStyle(color: cMuted),
          ),
          const SizedBox(height: 16),
          CGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Описание',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(listing.description, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CGlassCard(
            child: Column(
              children: [
                DetailLine(label: 'Продавец', value: listing.ownerName),
                DetailLine(label: 'Телефон', value: listing.phone),
                DetailLine(
                  label: 'Состояние',
                  value: conditionLabel(listing.condition),
                ),
                DetailLine(label: 'Просмотры', value: '${listing.views}'),
                DetailLine(
                  label: 'В избранном',
                  value: '${listing.favoriteCount}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showReportSheet(context, listing),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Пожаловаться'),
          ),
          if (paidPromotionEnabled && listing.ownerId == store.userId) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PromoteListingScreen(listingId: listing.id),
                ),
              ),
              icon: const Icon(Icons.trending_up_rounded),
              label: const Text('Продвинуть объявление'),
            ),
          ],
        ],
      ),
    );
  }
}

String conditionLabel(ListingCondition condition) => switch (condition) {
  ListingCondition.newItem => 'Новое',
  ListingCondition.used => 'Б/у',
  ListingCondition.broken => 'На запчасти',
};

class DetailLine extends StatelessWidget {
  const DetailLine({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: cMuted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({this.editingListing, super.key});
  final ListingAd? editingListing;
  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final title = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final district = TextEditingController(text: 'Бостандыкский район');
  String regionId = 'cities';
  String selectedCity = 'Алматы';
  String categoryId = 'electronics';
  String subcategoryId = 'phones';
  ListingCondition condition = ListingCondition.used;
  final attributes = <String, String>{};
  bool negotiable = false;
  bool saving = false;
  String moderationMessage = '';
  final fieldErrors = <String, String>{};
  final pickedImages = <XFile>[];
  final imageUrls = <String>[];

  bool get editing => widget.editingListing != null;

  @override
  void initState() {
    super.initState();
    final listing = widget.editingListing;
    if (listing == null) return;
    title.text = listing.title;
    description.text = listing.description;
    price.text = listing.price <= 0 ? '' : '${listing.price}';
    district.text = listing.district;
    selectedCity = listing.city;
    categoryId = listing.categoryId;
    subcategoryId = listing.categoryId;
    condition = listing.condition;
    negotiable = listing.price <= 0;
    attributes.addAll(listing.attributes);
    imageUrls.addAll(listing.images);
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    price.dispose();
    district.dispose();
    super.dispose();
  }

  String? _clientCategoryMismatch(ClassifiedsStore store) {
    final text = '${title.text} ${description.text}'.toLowerCase();
    final rootId = store.rootCategoryId(
      subcategoryId.isEmpty ? categoryId : subcategoryId,
    );
    final rules = <({String root, String label, List<String> words})>[
      (
        root: 'services',
        label: 'Услуги',
        words: [
          'массаж',
          'маникюр',
          'педикюр',
          'ресниц',
          'стриж',
          'ремонт',
          'уборк',
          'юрист',
          'репетитор',
        ],
      ),
      (
        root: 'electronics',
        label: 'Электроника',
        words: [
          'телефон',
          'смартфон',
          'samsung',
          'iphone',
          'ноутбук',
          'планшет',
        ],
      ),
      (
        root: 'transport',
        label: 'Транспорт',
        words: ['авто', 'машин', 'toyota', 'hyundai', 'kia', 'bmw', 'мото'],
      ),
      (
        root: 'real_estate',
        label: 'Недвижимость',
        words: ['квартир', 'дом', 'участок', 'офис', 'комнат'],
      ),
      (
        root: 'jobs',
        label: 'Работа',
        words: ['ваканси', 'работа', 'зарплат', 'требуется'],
      ),
    ];
    for (final rule in rules) {
      if (rule.words.any(text.contains) && rootId != rule.root) {
        return 'Неверная категория: для этого объявления выберите категорию «${rule.label}».';
      }
    }
    return null;
  }

  void _showModerationIssue(String reason) {
    final lower = reason.toLowerCase();
    setState(() {
      moderationMessage = reason;
      fieldErrors.clear();
      if (lower.contains('категор')) {
        fieldErrors['category'] = reason;
      }
      if (lower.contains('назван') ||
          lower.contains('заголов') ||
          lower.contains('лексик')) {
        fieldErrors['title'] = reason;
      }
      if (lower.contains('описан') ||
          lower.contains('интим') ||
          lower.contains('18+') ||
          lower.contains('мошен')) {
        fieldErrors['description'] = reason;
      }
      if (lower.contains('цена') ||
          lower.contains('баға') ||
          lower.contains('20 000 000')) {
        fieldErrors['price'] = reason;
      }
      if (fieldErrors.isEmpty) {
        fieldErrors['description'] = reason;
      }
    });
  }

  void _clearIssue(String key) {
    if (!fieldErrors.containsKey(key) && moderationMessage.isEmpty) return;
    setState(() {
      fieldErrors.remove(key);
      if (fieldErrors.isEmpty) moderationMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    if (!store.categories.any((item) => item.id == categoryId)) {
      final parentId = store.rootCategoryId(categoryId);
      if (parentId != 'all') {
        categoryId = parentId;
        subcategoryId = widget.editingListing?.categoryId ?? subcategoryId;
      }
    }
    if (!store.isAuthorized) {
      return AuthRequiredPane(
        title: store.tx(
          'Войдите, чтобы подать объявление',
          'Хабарландыру беру үшін кіріңіз',
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const CBrandHeader(),
          const SizedBox(height: 18),
          Text(
            editing
                ? store.tx('Редактировать объявление', 'Хабарландыруды өңдеу')
                : store.tx('Новое объявление', 'Жаңа хабарландыру'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          CGlassCard(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: InputDecoration(
                    labelText: 'Категория',
                    errorText: fieldErrors['category'],
                  ),
                  items: store.categories
                      .where((c) => c.id != 'all')
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.title(store.language)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    categoryId = value ?? categoryId;
                    final category = store.categories
                        .where((item) => item.id == categoryId)
                        .firstOrNullC;
                    subcategoryId =
                        category?.subcategories.firstOrNullC?.id ?? '';
                    attributes.clear();
                    fieldErrors.remove('category');
                    if (fieldErrors.isEmpty) moderationMessage = '';
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: subcategoryId.isEmpty ? null : subcategoryId,
                  decoration: InputDecoration(
                    labelText: 'Подкатегория',
                    errorText: fieldErrors['category'],
                  ),
                  items:
                      (store.categories
                                  .where((item) => item.id == categoryId)
                                  .firstOrNullC
                                  ?.subcategories ??
                              const <ListingSubcategory>[])
                          .map(
                            (subcategory) => DropdownMenuItem(
                              value: subcategory.id,
                              child: Text(subcategory.title(store.language)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() {
                    subcategoryId = value ?? '';
                    attributes.clear();
                    fieldErrors.remove('category');
                    if (fieldErrors.isEmpty) moderationMessage = '';
                  }),
                ),
                const SizedBox(height: 10),
                ...store
                    .attributeFiltersFor(
                      subcategoryId.isEmpty ? categoryId : subcategoryId,
                    )
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: attributes[filter.id],
                          decoration: InputDecoration(
                            labelText: filter.title(store.language),
                          ),
                          items: filter.options
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(option),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            if (value == null) {
                              attributes.remove(filter.id);
                            } else {
                              attributes[filter.id] = value;
                            }
                          }),
                        ),
                      ),
                    ),
                TextField(
                  controller: title,
                  onChanged: (_) => _clearIssue('title'),
                  decoration: InputDecoration(
                    labelText: 'Название',
                    errorText: fieldErrors['title'],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (_) => _clearIssue('description'),
                  decoration: InputDecoration(
                    labelText: 'Описание',
                    errorText: fieldErrors['description'],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        enabled: !negotiable,
                        controller: price,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _clearIssue('price'),
                        decoration: InputDecoration(
                          labelText: 'Цена, ₸',
                          errorText: fieldErrors['price'],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CheckboxListTile(
                        value: negotiable,
                        onChanged: (v) =>
                            setState(() => negotiable = v ?? false),
                        title: const Text('Договорная'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<ListingCondition>(
                  initialValue: condition,
                  decoration: const InputDecoration(labelText: 'Состояние'),
                  items: ListingCondition.values
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(conditionLabel(c)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => condition = value ?? condition),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => showLocationSheet(
                    context,
                    selectedRegionId: regionId,
                    selectedCity: selectedCity,
                    onSelected: (region, city) {
                      setState(() {
                        regionId = region.id;
                        selectedCity = city;
                      });
                    },
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Область и город',
                      suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    child: Text(selectedCity),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: district,
                  decoration: const InputDecoration(labelText: 'Район/адрес'),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final image = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 82,
                          );
                          if (image != null && mounted) {
                            setState(() => pickedImages.add(image));
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    'Фото (${pickedImages.length + imageUrls.length}/8)',
                  ),
                ),
                const SizedBox(height: 10),
                if (imageUrls.isNotEmpty) ...[
                  ExistingImageStrip(
                    images: imageUrls,
                    onRemove: (url) => setState(() => imageUrls.remove(url)),
                  ),
                  const SizedBox(height: 10),
                ],
                ImagePreviewStrip(images: pickedImages),
                const SizedBox(height: 14),
                if (moderationMessage.isNotEmpty) ...[
                  RejectionReasonBox(reason: moderationMessage),
                  const SizedBox(height: 14),
                ],
                FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (title.text.trim().isEmpty ||
                              description.text.trim().isEmpty) {
                            setState(() {
                              moderationMessage =
                                  'Заполните название и описание.';
                              fieldErrors.clear();
                              if (title.text.trim().isEmpty) {
                                fieldErrors['title'] = 'Заполните название';
                              }
                              if (description.text.trim().isEmpty) {
                                fieldErrors['description'] =
                                    'Заполните описание';
                              }
                            });
                            return;
                          }
                          final categoryIssue = _clientCategoryMismatch(store);
                          if (categoryIssue != null) {
                            _showModerationIssue(categoryIssue);
                            return;
                          }
                          setState(() => saving = true);
                          try {
                            setState(() {
                              moderationMessage = '';
                              fieldErrors.clear();
                            });
                            final urls = <String>[...imageUrls];
                            for (final image in pickedImages) {
                              urls.add(
                                await store.uploadImage(image, 'listingImages'),
                              );
                            }
                            final listing = widget.editingListing;
                            late final ListingAd savedListing;
                            if (listing == null) {
                              savedListing = await store.createListing(
                                title: title.text.trim(),
                                description: description.text.trim(),
                                categoryId: subcategoryId.isEmpty
                                    ? categoryId
                                    : subcategoryId,
                                city: selectedCity,
                                regionId: regionId,
                                district: district.text.trim(),
                                price: negotiable
                                    ? 0
                                    : NumberParser.toInt(price.text),
                                condition: condition,
                                images: urls,
                                attributes: attributes,
                              );
                            } else {
                              savedListing = await store.updateListing(
                                listing: listing,
                                title: title.text.trim(),
                                description: description.text.trim(),
                                categoryId: subcategoryId.isEmpty
                                    ? categoryId
                                    : subcategoryId,
                                city: selectedCity,
                                regionId: regionId,
                                district: district.text.trim(),
                                price: negotiable
                                    ? 0
                                    : NumberParser.toInt(price.text),
                                condition: condition,
                                images: urls,
                                attributes: attributes,
                              );
                            }
                            if (!context.mounted) return;
                            if (savedListing.status == ListingStatus.rejected) {
                              _showModerationIssue(
                                savedListing.rejectionReasonRu.isEmpty
                                    ? 'Объявление отклонено. Исправьте отмеченные поля.'
                                    : savedListing.rejectionReasonRu,
                              );
                              return;
                            }
                            showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text(
                                  editing
                                      ? 'Объявление обновлено'
                                      : 'Объявление отправлено',
                                ),
                                content: const Text('Объявление сохранено.'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('ОК'),
                                  ),
                                ],
                              ),
                            );
                            if (!editing) {
                              title.clear();
                              description.clear();
                              price.clear();
                              attributes.clear();
                              pickedImages.clear();
                              imageUrls.clear();
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Объявление: ${cFriendlyError(error)}',
                                ),
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  icon: Icon(
                    saving
                        ? Icons.hourglass_top_rounded
                        : Icons.verified_rounded,
                  ),
                  label: Text(
                    saving
                        ? 'Отправляем...'
                        : editing
                        ? 'Сохранить изменения'
                        : 'Опубликовать',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void showLocationSheet(
  BuildContext context, {
  required String selectedRegionId,
  required String selectedCity,
  required void Function(ListingLocation region, String city) onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LocationPickerSheet(
      selectedRegionId: selectedRegionId,
      selectedCity: selectedCity,
      onSelected: onSelected,
    ),
  );
}

void showFilterCitySheet(
  BuildContext context, {
  required String selectedCity,
  required void Function(String city) onSelected,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FilterCityPickerSheet(
      selectedCity: selectedCity,
      onSelected: onSelected,
    ),
  );
}

class FilterCityPickerSheet extends StatelessWidget {
  const FilterCityPickerSheet({
    required this.selectedCity,
    required this.onSelected,
    super.key,
  });

  final String selectedCity;
  final void Function(String city) onSelected;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final locations = store.locations;
    return SheetFrame(
      title: 'Город',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              selectedCity == 'all'
                  ? Icons.radio_button_checked
                  : Icons.public_rounded,
              color: cBlue,
            ),
            title: const Text('Все города'),
            onTap: () {
              onSelected('all');
              Navigator.of(context).pop();
            },
          ),
          if (locations.isEmpty)
            const EmptyState(
              title: 'Города не загружены',
              text: 'Проверьте подключение к базе и повторите позже.',
              icon: Icons.location_city_rounded,
            ),
          ...locations.expand(
            (location) => [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(
                  location.region(store.language),
                  style: const TextStyle(
                    color: cMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ...location.cities.map(
                (city) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selectedCity == city
                        ? Icons.radio_button_checked
                        : Icons.location_city_rounded,
                    color: cBlue,
                  ),
                  title: Text(city),
                  onTap: () {
                    onSelected(city);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({
    required this.selectedRegionId,
    required this.selectedCity,
    required this.onSelected,
    super.key,
  });

  final String selectedRegionId;
  final String selectedCity;
  final void Function(ListingLocation region, String city) onSelected;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  late String selectedRegionId = widget.selectedRegionId;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final locations = store.locations;
    if (locations.isEmpty) {
      return const SheetFrame(
        title: 'Выберите город',
        child: EmptyState(
          title: 'Города не загружены',
          text: 'Проверьте подключение к базе и повторите позже.',
          icon: Icons.location_city_rounded,
        ),
      );
    }
    final selectedRegion = locations.firstWhere(
      (item) => item.id == selectedRegionId,
      orElse: () => locations.first,
    );
    return SheetFrame(
      title: 'Выберите город',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Область',
            style: TextStyle(fontWeight: FontWeight.w900, color: cMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: locations
                .map(
                  (location) => ChoiceChip(
                    selected: selectedRegion.id == location.id,
                    label: Text(location.region(store.language)),
                    onSelected: (_) =>
                        setState(() => selectedRegionId = location.id),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          Text(
            selectedRegion.region(store.language),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...selectedRegion.cities.map(
            (city) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () {
                  widget.onSelected(selectedRegion, city);
                  Navigator.of(context).pop();
                },
                borderRadius: BorderRadius.circular(18),
                child: CGlassCard(
                  child: Row(
                    children: [
                      Icon(
                        widget.selectedCity == city
                            ? Icons.radio_button_checked
                            : Icons.location_city_rounded,
                        color: cBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          city,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: cMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImagePreviewStrip extends StatelessWidget {
  const ImagePreviewStrip({required this.images, super.key});
  final List<XFile> images;
  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => FutureBuilder<Uint8List>(
          future: images[index].readAsBytes(),
          builder: (context, snapshot) => Container(
            width: 86,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cSoftBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: snapshot.data == null
                ? const Center(child: CircularProgressIndicator())
                : Image.memory(snapshot.data!, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class ExistingImageStrip extends StatelessWidget {
  const ExistingImageStrip({
    required this.images,
    required this.onRemove,
    super.key,
  });
  final List<String> images;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final image = images[index];
          return Stack(
            children: [
              Container(
                width: 86,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cSoftBlue,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: CNetworkOrAssetImage(image, fit: BoxFit.cover),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: InkWell(
                  onTap: () => onRemove(image),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cNavy,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AuthRequiredPane extends StatelessWidget {
  const AuthRequiredPane({required this.title, super.key});
  final String title;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 70, color: cBlue),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('classifiedsOpenAuthButton'),
              onPressed: () => showAuthSheet(context),
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );
  }
}

void showAuthSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AuthSheet(),
  );
}

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final name = TextEditingController();
  String selectedRegionId = '';
  String selectedCity = '';
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    if (name.text.isEmpty && store.userName != 'Пользователь') {
      name.text = store.userName;
    }
    if (selectedCity.isEmpty && store.city.isNotEmpty) {
      selectedCity = store.city;
    }
    if (selectedRegionId.isEmpty && store.locations.isNotEmpty) {
      selectedRegionId = store.locations.first.id;
    }
    final canSave =
        name.text.trim().isNotEmpty && selectedCity.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CBrandHeader(),
            const SizedBox(height: 28),
            const Text(
              'Заполните профиль',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Имя и город нужны для публикации объявлений и общения в чатах.',
              style: TextStyle(color: cMuted, fontSize: 16),
            ),
            const SizedBox(height: 22),
            CGlassCard(
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('completeProfileNameField'),
                    controller: name,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Имя'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: store.locations.isEmpty
                        ? null
                        : () => showLocationSheet(
                            context,
                            selectedRegionId: selectedRegionId,
                            selectedCity: selectedCity,
                            onSelected: (region, city) {
                              setState(() {
                                selectedRegionId = region.id;
                                selectedCity = city;
                              });
                            },
                          ),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Город'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedCity.isEmpty
                                  ? 'Выберите город'
                                  : selectedCity,
                              style: TextStyle(
                                color: selectedCity.isEmpty ? cMuted : cNavy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('completeProfileSaveButton'),
                      onPressed: !canSave || saving
                          ? null
                          : () async {
                              setState(() => saving = true);
                              try {
                                await store.completeProfile(
                                  name: name.text,
                                  city: selectedCity,
                                );
                              } catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Не удалось сохранить профиль: $error',
                                    ),
                                  ),
                                );
                              } finally {
                                if (mounted) setState(() => saving = false);
                              }
                            },
                      child: Text(saving ? 'Сохраняем...' : 'Продолжить'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});
  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class OtpCellsField extends StatelessWidget {
  const OtpCellsField({
    required this.controller,
    required this.onChanged,
    this.fieldKey,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final value = controller.text.replaceAll(RegExp(r'\D'), '');
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (index) {
            final active = value.length == index;
            final digit = index < value.length ? value[index] : '';
            return Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? cBlue : cLine, width: 1.4),
                boxShadow: const [
                  BoxShadow(
                    color: cShadow,
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: cNavy,
                ),
              ),
            );
          }),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0.01,
            child: TextField(
              key: fieldKey,
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthSheetState extends State<AuthSheet> {
  final phone = TextEditingController();
  final code = TextEditingController();
  bool codeSent = false;
  bool requestingCode = false;

  bool get phoneReady =>
      normalizePhone(phone.text).replaceAll(RegExp(r'\D'), '').length == 11;

  bool get codeReady => code.text.replaceAll(RegExp(r'\D'), '').length >= 4;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SheetFrame(
      title: codeSent ? 'Подтверждение' : 'Вход',
      child: Column(
        children: [
          if (!codeSent) ...[
            const Text(
              'Временный вход: код появится на экране, СМС не отправляется. '
              'Номер не подтверждается. Аккаунт доступен только на этом устройстве; '
              'после переустановки доступ не сохраняется.',
              style: TextStyle(color: cMuted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Нажимая «Получить код», вы принимаете правила сервиса и политику '
              'конфиденциальности. Запрещены оскорбления, мошенничество, '
              'незаконные товары и публикация чужих данных.',
              style: TextStyle(color: cMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('classifiedsPhoneField'),
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: const [KazakhstanPhoneFormatter()],
              decoration: const InputDecoration(
                labelText: 'Номер телефона',
                hintText: '+7 (___) ___-__-__',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('classifiedsRequestOtpButton'),
              onPressed: requestingCode
                  ? null
                  : () async {
                      if (!phoneReady) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Введите номер полностью'),
                          ),
                        );
                        return;
                      }
                      setState(() => requestingCode = true);
                      try {
                        await store.requestOtp(phone.text);
                        if (mounted) setState(() => codeSent = true);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Вход: ${cFriendlyError(error)}'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => requestingCode = false);
                      }
                    },
              child: const Text('Получить код'),
            ),
          ] else ...[
            Text(
              store.pendingOtpCode == null
                  ? 'Введите код подтверждения'
                  : 'Код доступа: ${store.pendingOtpCode}',
              style: const TextStyle(color: cMuted),
            ),
            const SizedBox(height: 12),
            OtpCellsField(
              fieldKey: const ValueKey('classifiedsOtpField'),
              controller: code,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('classifiedsVerifyOtpButton'),
              onPressed: () async {
                if (!codeReady) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите код полностью')),
                  );
                  return;
                }
                try {
                  final ok = await store.verifyOtp(code.text);
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Неверный код')),
                    );
                  }
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка входа: $error')),
                  );
                }
              },
              child: const Text('Войти'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()),
            ),
            icon: const Icon(Icons.policy_outlined),
            label: Text(store.tx('Правовые документы', 'Құқықтық құжаттар')),
          ),
        ],
      ),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .78,
      maxChildSize: .94,
      minChildSize: .35,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            child,
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
          ],
        ),
      ),
    );
  }
}

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    if (!store.isAuthorized) {
      return const AuthRequiredPane(
        title: 'Войдите, чтобы пользоваться чатами',
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CBrandHeader(),
          const SizedBox(height: 18),
          const Text(
            'Чаты',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (store.chats.isEmpty)
            const EmptyState(
              title: 'Чатов пока нет',
              text: 'Напишите продавцу из объявления.',
              icon: Icons.chat_bubble_outline_rounded,
            )
          else
            ...store.chats.map(
              (chat) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatDetailsScreen(chatId: chat.id),
                    ),
                  ),
                  child: CGlassCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: cBlue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            chat.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text('${chat.messages.length}'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChatDetailsScreen extends StatefulWidget {
  const ChatDetailsScreen({required this.chatId, super.key});
  final String chatId;
  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  final text = TextEditingController();
  bool sending = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final chat = store.chats.firstWhere((item) => item.id == widget.chatId);
    final otherUser = chat.buyerId == store.userId
        ? chat.sellerId
        : chat.buyerId;
    final blocked = store.blockedUserIds.contains(otherUser);
    return Scaffold(
      appBar: AppBar(
        title: Text(chat.title),
        actions: [
          if (otherUser.isNotEmpty && otherUser != store.userId)
            IconButton(
              tooltip: blocked
                  ? 'Разблокировать пользователя'
                  : 'Заблокировать пользователя',
              icon: Icon(blocked ? Icons.lock_open : Icons.block),
              onPressed: () async {
                try {
                  await store.blockMarketplaceUser(otherUser, !blocked);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          blocked
                              ? 'Пользователь разблокирован'
                              : 'Пользователь заблокирован. Новые сообщения запрещены.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(cFriendlyError(error))),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: chat.messages.isEmpty
                  ? [
                      const EmptyState(
                        title: 'Начните диалог',
                        text: 'Обсудите детали объявления с продавцом.',
                        icon: Icons.forum_outlined,
                      ),
                    ]
                  : chat.messages.map((message) {
                      final mine = message.senderId == store.userId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () => showMessageActionSheet(
                            context,
                            chat,
                            message,
                            canDelete: mine || store.isOwner,
                            canReport: !mine,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 290),
                            decoration: BoxDecoration(
                              color: mine ? cBlue : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: message.flagged ? cOrange : cLine,
                              ),
                            ),
                            child: ChatMessageBubble(
                              message: message,
                              mine: mine,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: sending
                        ? null
                        : () async {
                            setState(() => sending = true);
                            try {
                              final image = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 82,
                              );
                              if (image == null) return;
                              final url = await store.uploadImage(
                                image,
                                'chatImages',
                              );
                              await store.sendMessage(
                                chat,
                                text.text,
                                imageUrl: url,
                              );
                              text.clear();
                            } finally {
                              if (mounted) setState(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.photo_outlined),
                  ),
                  IconButton(
                    onPressed: sending
                        ? null
                        : () async {
                            setState(() => sending = true);
                            try {
                              final result = await FilePicker.platform
                                  .pickFiles(withData: true);
                              final file = result?.files.first;
                              if (file == null) return;
                              final url = await store.uploadChatFile(file);
                              await store.sendMessage(
                                chat,
                                text.text,
                                fileUrl: url,
                                fileName: file.name,
                              );
                              text.clear();
                            } finally {
                              if (mounted) setState(() => sending = false);
                            }
                          },
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: text,
                      decoration: const InputDecoration(hintText: 'Сообщение'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending
                        ? null
                        : () async {
                            setState(() => sending = true);
                            try {
                              final value = text.text;
                              text.clear();
                              await store.sendMessage(chat, value);
                            } finally {
                              if (mounted) setState(() => sending = false);
                            }
                          },
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.mine,
    super.key,
  });

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final textColor = mine ? Colors.white : cNavy;
    if (message.deleted) {
      return Text(
        'Сообщение удалено',
        style: TextStyle(color: textColor.withOpacity(.72)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: message.imageUrl.startsWith('data:image/')
                  ? MemoryImage(
                      UriData.parse(message.imageUrl).contentAsBytes(),
                    )
                  : NetworkImage(message.imageUrl),
              width: 260,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 260,
                height: 120,
                alignment: Alignment.center,
                color: cSoftBlue,
                child: const Icon(Icons.broken_image_outlined, color: cBlue),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (message.fileUrl.isNotEmpty) ...[
          InkWell(
            onTap: () => launchUrl(Uri.parse(message.fileUrl)),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: mine ? Colors.white.withOpacity(.14) : cSoftBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined, color: textColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.fileName.isEmpty ? 'Файл' : message.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (message.text.isNotEmpty)
          Text(
            message.flagged ? '${message.text}\n\nНа проверке' : message.text,
            style: TextStyle(color: textColor),
          ),
      ],
    );
  }
}

void showMessageActionSheet(
  BuildContext context,
  ChatThread chat,
  ChatMessage message, {
  required bool canDelete,
  required bool canReport,
}) {
  final store = ClassifiedsScope.of(context);
  final reason = TextEditingController();
  final deleteReason = TextEditingController();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Сообщение',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (canDelete) ...[
              if (store.isOwner) ...[
                TextField(
                  controller: deleteReason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Причина удаления',
                    hintText: 'Нарушение правил, мошенничество...',
                  ),
                ),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    await store.deleteMessage(
                      chat,
                      message,
                      reason: deleteReason.text,
                    );
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Сообщение удалено')),
                    );
                    navigator.pop();
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Удаление: $error')),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Удалить сообщение'),
              ),
            ],
            if (canReport) ...[
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Причина жалобы',
                  hintText: 'Мошенничество, оскорбление, запрещенный товар...',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = reason.text.trim();
                  if (value.isEmpty) return;
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    await store.reportMessage(chat, message, value);
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Жалоба отправлена')),
                    );
                    navigator.pop();
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Жалоба: $error')),
                    );
                  }
                },
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Пожаловаться'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class ClassifiedsProfileScreen extends StatelessWidget {
  const ClassifiedsProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    if (!store.isAuthorized) {
      return const AuthRequiredPane(
        title: 'Войдите, чтобы управлять объявлениями',
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CBrandHeader(
            trailing: IconButton(
              onPressed: store.logout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
          const SizedBox(height: 18),
          CGlassCard(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: cSoftBlue,
                  child: Icon(Icons.person_rounded, color: cBlue, size: 38),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.userName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(store.phone, style: const TextStyle(color: cMuted)),
                      Text(
                        'Объявлений: ${store.myListings.length}',
                        style: const TextStyle(
                          color: cBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ProfileAction(
            icon: Icons.inventory_2_outlined,
            title: 'Мои объявления',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MyListingsScreen())),
          ),
          ProfileAction(
            icon: Icons.favorite_border_rounded,
            title: 'Избранное',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
          ),
          ProfileAction(
            icon: Icons.bookmarks_outlined,
            title: 'Сохраненные поиски',
            subtitle: store.savedSearches.isEmpty
                ? 'Сохраняйте фильтры и запросы'
                : '${store.savedSearches.length} сохранено',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
            ),
          ),
          if (paidPromotionEnabled)
            ProfileAction(
              icon: Icons.campaign_outlined,
              title: 'Мои баннеры',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyBannersScreen()),
              ),
            ),
          ProfileAction(
            icon: Icons.notifications_none_rounded,
            title: 'Уведомления',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsLogScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.support_agent_rounded,
            title: store.tx('Поддержка', 'Қолдау'),
            onTap: () => demoAuthenticationEnabled
                ? launchUrl(
                    Uri.parse('https://pushka-help-f4e4f.web.app/#support'),
                    mode: LaunchMode.externalApplication,
                  )
                : Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SupportTicketScreen(),
                    ),
                  ),
          ),
          ProfileAction(
            icon: Icons.language_rounded,
            title: 'Язык',
            onTap: () => showLanguageSheet(context),
          ),
          ProfileAction(
            icon: Icons.policy_outlined,
            title: store.tx('Правовые документы', 'Құқықтық құжаттар'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.person_remove_outlined,
            title: store.tx('Удалить аккаунт', 'Аккаунтты жою'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

void showLanguageSheet(BuildContext context) {
  final store = ClassifiedsScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SheetFrame(
      title: 'Выбор языка',
      child: Column(
        children: [
          LanguageOptionTile(
            title: 'Русский',
            subtitle: 'Интерфейс на русском языке',
            selected: store.language == ClassifiedsLanguage.ru,
            onTap: () => selectProfileLanguage(
              context,
              ClassifiedsLanguage.ru,
              'Выбран русский язык',
            ),
          ),
          const SizedBox(height: 10),
          LanguageOptionTile(
            title: 'Қазақша',
            subtitle: 'Интерфейс қазақ тілінде',
            selected: store.language == ClassifiedsLanguage.kk,
            onTap: () => selectProfileLanguage(
              context,
              ClassifiedsLanguage.kk,
              'Қазақ тілі таңдалды',
            ),
          ),
        ],
      ),
    ),
  );
}

void selectProfileLanguage(
  BuildContext context,
  ClassifiedsLanguage language,
  String message,
) {
  final store = ClassifiedsScope.of(context);
  store.language = language;
  store.languageSelected = true;
  unawaited(store.saveSession());
  logAnalyticsEvent('language_changed', {'language': language.name});
  store.notifyListeners();
  Navigator.of(context).pop();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class LanguageOptionTile extends StatelessWidget {
  const LanguageOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: CGlassCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? cBlue : cSoftBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.language_rounded,
                color: selected ? Colors.white : cBlue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: cMuted)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.radio_button_checked, color: cBlue),
            if (!selected)
              const Icon(Icons.radio_button_unchecked, color: cMuted),
          ],
        ),
      ),
    );
  }
}

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({super.key});

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final subject = TextEditingController();
  final message = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    subject.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final store = ClassifiedsScope.of(context);
    if (subject.text.trim().isEmpty || message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.tx(
              'Заполните тему и сообщение',
              'Тақырып пен хабарды толтырыңыз',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => sending = true);
    try {
      await store.createSupportTicket(
        subject: subject.text,
        message: message.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(store.tx('Обращение отправлено', 'Өтініш жіберілді')),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${store.tx('Поддержка:', 'Қолдау:')} $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(store.tx('Поддержка', 'Қолдау'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    store.tx(
                      'Опишите вопрос, ошибку или спорную ситуацию.',
                      'Сұрақты, қатені немесе даулы жағдайды сипаттаңыз.',
                    ),
                    style: const TextStyle(color: cMuted, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: subject,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: store.tx('Тема', 'Тақырып'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: message,
                    minLines: 5,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: store.tx('Сообщение', 'Хабарлама'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: sending ? null : submit,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                sending
                    ? store.tx('Отправляем...', 'Жіберілуде...')
                    : store.tx('Отправить', 'Жіберу'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool deleting = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(store.tx('Удалить аккаунт', 'Аккаунтты жою'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            store.tx(
              'Аккаунт, объявления, переписки, фотографии и файлы будут удалены без возможности восстановления. '
                  'Обработка запроса может занять некоторое время. Обезличенные платёжные записи могут сохраняться для учёта.',
              'Аккаунт, хабарландырулар, хаттар, фотосуреттер мен файлдар қалпына келтіру мүмкіндігінсіз жойылады. '
                  'Сұрауды өңдеу біраз уақыт алуы мүмкін. Жеке деректерсіз төлем жазбалары есеп үшін сақталуы мүмкін.',
            ),
          ),
          const SizedBox(height: 24),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: deleting
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(
                          store.tx(
                            'Удалить аккаунт навсегда?',
                            'Аккаунтты біржола жою керек пе?',
                          ),
                        ),
                        content: Text(
                          store.tx(
                            'Это действие нельзя отменить.',
                            'Бұл әрекетті болдырмау мүмкін емес.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(store.tx('Отмена', 'Бас тарту')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(store.tx('Удалить', 'Жою')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    setState(() {
                      deleting = true;
                      error = null;
                    });
                    try {
                      await store.requestAccountDeletion();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            store.tx(
                              'Запрос принят. Аккаунт и связанные данные удаляются.',
                              'Сұрау қабылданды. Аккаунт пен байланысты деректер жойылуда.',
                            ),
                          ),
                        ),
                      );
                    } catch (_) {
                      if (!mounted) return;
                      setState(() {
                        deleting = false;
                        error = store.tx(
                          'Не удалось отправить запрос. Попробуйте ещё раз.',
                          'Сұрауды жіберу мүмкін болмады. Қайталап көріңіз.',
                        );
                      });
                    }
                  },
            child: Text(
              deleting
                  ? store.tx('Отправляем…', 'Жіберілуде…')
                  : store.tx(
                      'Удалить аккаунт и данные',
                      'Аккаунт пен деректерді жою',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    if (demoAuthenticationEnabled) {
      return Scaffold(
        appBar: AppBar(
          title: Text(store.tx('Правовые документы', 'Құқықтық құжаттар')),
        ),
        body: Center(
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(
              store.tx(
                'Конфиденциальность и удаление данных',
                'Құпиялылық және деректерді жою',
              ),
            ),
            onPressed: () => launchUrl(
              Uri.parse('https://pushka-help-f4e4f.web.app/#privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(store.tx('Правовые документы', 'Құқықтық құжаттар')),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('appSettings')
            .doc('legal')
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              title: store.tx('Не удалось загрузить', 'Жүктеу мүмкін болмады'),
              text: '${snapshot.error}',
              icon: Icons.cloud_off_rounded,
            );
          }
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final documents = data['documents'] is Map
              ? Map<String, dynamic>.from(data['documents'] as Map)
              : <String, dynamic>{};
          final version = '${data['currentVersion'] ?? ''}';
          final items = [
            LegalDocumentItem(
              id: 'terms',
              title: store.tx(
                'Пользовательское соглашение',
                'Пайдаланушы келісімі',
              ),
            ),
            LegalDocumentItem(
              id: 'privacy',
              title: store.tx(
                'Политика конфиденциальности',
                'Құпиялылық саясаты',
              ),
            ),
            LegalDocumentItem(
              id: 'promotion',
              title: store.tx('Условия продвижения', 'Ілгерілету шарттары'),
            ),
            LegalDocumentItem(
              id: 'payment',
              title: store.tx('Условия оплаты', 'Төлем шарттары'),
            ),
            LegalDocumentItem(
              id: 'refund',
              title: store.tx('Условия возврата', 'Қайтару шарттары'),
            ),
          ];
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (version.isNotEmpty)
                  Text(
                    store.tx('Версия: ', 'Нұсқа: ') + version,
                    style: const TextStyle(color: cMuted),
                  ),
                const SizedBox(height: 12),
                ...items.map((item) {
                  final raw = documents[item.id];
                  final text = raw is Map
                      ? '${Map<String, dynamic>.from(raw)[store.language.name] ?? Map<String, dynamic>.from(raw)['ru'] ?? ''}'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            text.isEmpty
                                ? store.tx(
                                    'Документ пока не заполнен.',
                                    'Құжат әлі толтырылмаған.',
                                  )
                                : text,
                            style: const TextStyle(color: cMuted, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LegalDocumentItem {
  const LegalDocumentItem({required this.id, required this.title});

  final String id;
  final String title;
}

class ProfileAction extends StatelessWidget {
  const ProfileAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle = '',
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: CGlassCard(
          child: Row(
            children: [
              Icon(icon, color: cBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(color: cMuted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: cMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Сохраненные поиски')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: store.savedSearches.isEmpty
            ? [
                const EmptyState(
                  title: 'Поисков нет',
                  text: 'Настройте фильтры и сохраните поиск.',
                  icon: Icons.bookmarks_outlined,
                ),
              ]
            : store.savedSearches
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SavedSearchCard(item: item),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class SavedSearchCard extends StatelessWidget {
  const SavedSearchCard({required this.item, super.key});
  final SavedSearch item;
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return CGlassCard(
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: cBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.city == 'all' ? 'Все города' : item.city} · ${cMoney(item.minPrice)} - ${cMoney(item.maxPrice)}',
                  style: const TextStyle(color: cMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              store.applySavedSearch(item);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          IconButton(
            onPressed: () => store.deleteSavedSearch(item),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class MyListingsScreen extends StatelessWidget {
  const MyListingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои объявления')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: store.myListings.isEmpty
            ? [
                const EmptyState(
                  title: 'Объявлений нет',
                  text: 'Создайте первое объявление.',
                  icon: Icons.add_box_outlined,
                ),
              ]
            : store.myListings
                  .map(
                    (listing) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          ListingRowCard(listing: listing),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ListingStatPill(
                                icon: Icons.visibility_outlined,
                                text: '${listing.views}',
                              ),
                              const SizedBox(width: 8),
                              ListingStatPill(
                                icon: Icons.favorite_border_rounded,
                                text: '${listing.favoriteCount}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ListingStatusPill(status: listing.status),
                          ),
                          if (listing.status == ListingStatus.rejected &&
                              listing.rejectionReasonRu.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            RejectionReasonBox(
                              reason: listing.rejectionReasonRu,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CreateListingScreen(
                                        editingListing: listing,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Редактировать'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      listing.status == ListingStatus.archived
                                      ? null
                                      : () => confirmArchiveListing(
                                          context,
                                          listing,
                                        ),
                                  icon: const Icon(Icons.archive_outlined),
                                  label: const Text('В архив'),
                                ),
                              ),
                            ],
                          ),
                          if (paidPromotionEnabled &&
                              listing.status == ListingStatus.active) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PromoteListingScreen(
                                    listingId: listing.id,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.trending_up_rounded),
                              label: const Text('Продвинуть'),
                            ),
                          ],
                          if (listing.canRestoreFromArchive) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: () async {
                                try {
                                  await store.restoreListing(listing);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Восстановление: $error'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.restore_rounded),
                              label: const Text('Восстановить'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

void confirmArchiveListing(BuildContext context, ListingAd listing) {
  final store = ClassifiedsScope.of(context);
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Перенести в архив?'),
      content: Text('Объявление "${listing.title}" исчезнет из каталога.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            try {
              await store.archiveListing(listing);
            } catch (error) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Архив: $error')));
            }
          },
          child: const Text('В архив'),
        ),
      ],
    ),
  );
}

class ListingStatPill extends StatelessWidget {
  const ListingStatPill({required this.icon, required this.text, super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cSoftBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: cBlue, size: 16),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class ListingStatusPill extends StatelessWidget {
  const ListingStatusPill({required this.status, super.key});
  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    final isRejected = status == ListingStatus.rejected;
    final isActive = status == ListingStatus.active;
    final color = isRejected
        ? const Color(0xFFC43D22)
        : isActive
        ? cGreen
        : cBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        listingStatusMessage(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class RejectionReasonBox extends StatelessWidget {
  const RejectionReasonBox({required this.reason, super.key});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEFEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD2C7)),
      ),
      child: Text(
        'Причина отклонения: $reason',
        style: const TextStyle(
          color: Color(0xFFC43D22),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final listings = store.listings
        .where((item) => store.favoriteIds.contains(item.id))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: listings.isEmpty
            ? [
                const EmptyState(
                  title: 'Пусто',
                  text: 'Добавляйте объявления в избранное.',
                  icon: Icons.favorite_border_rounded,
                ),
              ]
            : listings
                  .map(
                    (listing) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ListingRowCard(listing: listing),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class PromoteListingScreen extends StatefulWidget {
  const PromoteListingScreen({required this.listingId, super.key});
  final String listingId;
  @override
  State<PromoteListingScreen> createState() => _PromoteListingScreenState();
}

class _PromoteListingScreenState extends State<PromoteListingScreen> {
  String? loadingPlanId;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final listing = store.listings.firstWhere(
      (item) => item.id == widget.listingId,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Продвижение')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListingRowCard(listing: listing),
          const SizedBox(height: 16),
          if (store.promotionPlans.isEmpty)
            const EmptyState(
              title: 'Тарифов нет',
              text: 'Владелец должен добавить тарифы продвижения в админке.',
              icon: Icons.trending_up_rounded,
            ),
          ...store.promotionPlans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CGlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.trending_up_rounded, color: cBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.localizedTitle(store.language),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            plan.localizedCaption(store.language),
                            style: const TextStyle(color: cMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      cMoney(plan.price),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    IconButton(
                      onPressed: loadingPlanId == null
                          ? () async {
                              setState(() => loadingPlanId = plan.id);
                              try {
                                await store.purchasePromotion(listing, plan);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${plan.localizedTitle(store.language)}: оплата прошла',
                                      ),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Не удалось оплатить тариф: $error',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => loadingPlanId = null);
                                }
                              }
                            }
                          : null,
                      icon: loadingPlanId == plan.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payment_rounded, color: cBlue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyBannersScreen extends StatelessWidget {
  const MyBannersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои баннеры')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const BannerCreateSheet(),
            ),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Создать баннер'),
          ),
          const SizedBox(height: 14),
          ...store.banners
              .where((b) => b.ownerId == store.userId || store.isOwner)
              .map(
                (banner) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 120,
                          width: double.infinity,
                          child: CNetworkOrAssetImage(
                            banner.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          banner.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Статус: ${listingStatusMessage(banner.status)}',
                          style: const TextStyle(color: cMuted),
                        ),
                        if (banner.status == ListingStatus.pendingPayment)
                          if (store.bannerPlans.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Тарифы баннеров ещё не настроены.',
                                style: TextStyle(color: cMuted),
                              ),
                            )
                          else
                            ...store.bannerPlans.map(
                              (plan) => OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await store.purchaseBannerPlacement(
                                      banner,
                                      plan,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${plan.localizedTitle(store.language)}: оплата прошла',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Не удалось оплатить баннер: $error',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(
                                  '${plan.localizedTitle(store.language)} • ${cMoney(plan.price)}',
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class BannerCreateSheet extends StatefulWidget {
  const BannerCreateSheet({this.editingBanner, super.key});

  final UserBannerAd? editingBanner;

  @override
  State<BannerCreateSheet> createState() => _BannerCreateSheetState();
}

class _BannerCreateSheetState extends State<BannerCreateSheet> {
  XFile? image;
  Uint8List? imageBytes;
  bool saving = false;

  bool get editing => widget.editingBanner != null;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SheetFrame(
      title: editing ? 'Редактировать баннер' : 'Пользовательский баннер',
      child: Column(
        children: [
          const Text(
            'Загрузите готовый баннер одним изображением. Рекомендуемый размер: 1200x450 px, формат JPG/PNG/WebP, до 10 МБ. Весь текст и дизайн должны быть внутри изображения.',
            style: TextStyle(color: cMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: Image.memory(imageBytes!, fit: BoxFit.cover),
              ),
            )
          else if (editing && image == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: CNetworkOrAssetImage(
                  widget.editingBanner!.imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (imageBytes != null || (editing && image == null))
            const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final picked = kIsWeb
                    ? await pickWebImage()
                    : await pickNativeImage();
                if (picked == null) return;
                final bytes = picked.bytes;
                if (bytes.isEmpty) throw StateError('empty_image');
                if (!mounted) return;
                setState(() {
                  image = XFile.fromData(
                    bytes,
                    name: picked.name,
                    mimeType: picked.mimeType,
                  );
                  imageBytes = bytes;
                });
              } catch (error) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text(uploadErrorMessage(error))),
                );
              }
            },
            icon: const Icon(Icons.image_outlined),
            label: Text(image == null ? 'Выбрать фото' : 'Фото выбрано'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!editing && image == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Выберите фото баннера')),
                      );
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      final autoTitle =
                          widget.editingBanner?.title ??
                          'Баннер ${DateTime.now().millisecondsSinceEpoch}';
                      final url = image == null
                          ? widget.editingBanner!.imageUrl
                          : await store.uploadImage(image!, 'bannerAds');
                      final banner = widget.editingBanner;
                      if (banner == null) {
                        final created = await store.createBanner(
                          title: autoTitle,
                          caption: 'Пользовательский баннер',
                          imageUrl: url,
                        );
                        if (context.mounted) {
                          final message =
                              created.status == ListingStatus.pendingPayment
                              ? 'Баннер одобрен. Выберите тариф и оплатите размещение.'
                              : created.status == ListingStatus.rejected
                              ? (created.rejectionReasonRu.isEmpty
                                    ? 'Баннер отклонён.'
                                    : created.rejectionReasonRu)
                              : 'Баннер отправлен на проверку.';
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        }
                      } else {
                        final updated = await store.updateBanner(
                          banner: banner,
                          title: autoTitle,
                          caption: banner.caption.isEmpty
                              ? 'Пользовательский баннер'
                              : banner.caption,
                          imageUrl: url,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                updated.status == ListingStatus.rejected
                                    ? (updated.rejectionReasonRu.isEmpty
                                          ? 'Баннер отклонён.'
                                          : updated.rejectionReasonRu)
                                    : 'Баннер обновлён.',
                              ),
                            ),
                          );
                        }
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(uploadErrorMessage(error))),
                      );
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            child: Text(
              saving
                  ? 'Проверяем...'
                  : editing
                  ? 'Сохранить'
                  : 'Продолжить',
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationsLogScreen extends StatefulWidget {
  const NotificationsLogScreen({super.key});

  @override
  State<NotificationsLogScreen> createState() => _NotificationsLogScreenState();
}

class _NotificationsLogScreenState extends State<NotificationsLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ClassifiedsScope.of(context).markNotificationsRead());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: store.notifications.isEmpty
            ? [
                const EmptyState(
                  title: 'Уведомлений нет',
                  text: 'Здесь будут статусы модерации и оплат.',
                  icon: Icons.notifications_none_rounded,
                ),
              ]
            : store.notifications
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              item.text,
                              style: TextStyle(
                                fontWeight: item.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w900,
                              ),
                            ),
                            if (item.type == 'listing_call_check' &&
                                !item.resolved) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        await store
                                            .resolveListingCallNotification(
                                              item,
                                              false,
                                            );
                                      },
                                      child: const Text('Нет'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () async {
                                        await store
                                            .resolveListingCallNotification(
                                              item,
                                              true,
                                            );
                                      },
                                      child: const Text('Да'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.text,
    required this.icon,
    super.key,
  });
  final String title;
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: cMuted),
          ),
        ],
      ),
    );
  }
}

void showReportSheet(BuildContext context, ListingAd listing) {
  final reason = TextEditingController(text: 'Нарушение правил площадки');
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      final store = ClassifiedsScope.of(context);
      return SheetFrame(
        title: 'Пожаловаться',
        child: Column(
          children: [
            TextField(
              controller: reason,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Причина'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final value = reason.text.trim();
                if (value.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                try {
                  await store.reportListing(listing, value);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Жалоба отправлена')),
                  );
                  navigator.pop();
                } catch (error) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Жалоба: $error')),
                  );
                }
              },
              child: const Text('Отправить владельцу'),
            ),
          ],
        ),
      );
    },
  );
}

class OwnerShell extends StatelessWidget {
  const OwnerShell({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const CBrandHeader(),
        actions: [
          IconButton(
            onPressed: store.logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Панель владельца',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Объявления',
                  value: '${store.listings.length}',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Модерация',
                  value:
                      '${store.moderationCases.where((c) => !c.resolved).length}',
                  icon: Icons.verified_user_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Баннеры',
                  value: '${store.banners.length}',
                  icon: Icons.campaign_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Чаты',
                  value: '${store.chats.length}',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          CGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Повторная модерация',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Автопроверка всех активных объявлений также запускается каждые 2 часа.',
                  style: TextStyle(color: cMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final result = await store
                          .ownerRunListingModerationSweep();
                      messenger.showSnackBar(SnackBar(content: Text(result)));
                    } catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Проверка: $error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Проверить объявления сейчас'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final result = await store.ownerRunListingModerationSweep(
                        rejectAll: true,
                      );
                      messenger.showSnackBar(SnackBar(content: Text(result)));
                    } catch (error) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Отклонение: $error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Отклонить все текущие объявления'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Очередь модерации', action: ''),
          const SizedBox(height: 10),
          if (store.moderationCases.where((c) => !c.resolved).isEmpty)
            const EmptyState(
              title: 'Очередь пуста',
              text: 'Спорные объявления, баннеры и чаты появятся здесь.',
              icon: Icons.task_alt_rounded,
            )
          else
            ...store.moderationCases
                .where((c) => !c.resolved)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '${item.type} • риск ${(item.riskScore * 100).round()}%',
                            style: const TextStyle(color: cMuted),
                          ),
                          const SizedBox(height: 8),
                          Text(item.reasonRu),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      store.ownerResolveCase(item, false),
                                  child: const Text('Отклонить'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      store.ownerResolveCase(item, true),
                                  child: const Text('Одобрить'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 18),
          ProfileAction(
            icon: Icons.list_alt_rounded,
            title: 'Все объявления',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerListingsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.report_gmailerrorred_rounded,
            title: 'Жалобы',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerReportsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.analytics_outlined,
            title: 'Аналитика',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerAnalyticsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.notifications_active_outlined,
            title: 'Отправить push RU/KK',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerPushScreen())),
          ),
          ProfileAction(
            icon: Icons.payments_outlined,
            title: 'Платежи Kassa24',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerPaymentsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.history_rounded,
            title: 'Журнал действий',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerAuditScreen())),
          ),
          ProfileAction(
            icon: Icons.tune_rounded,
            title: 'Настройки приложения',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerAppSettingsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.people_outline_rounded,
            title: 'Пользователи',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerUsersScreen())),
          ),
          ProfileAction(
            icon: Icons.support_agent_rounded,
            title: 'Поддержка',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const OwnerSupportTicketsScreen(),
              ),
            ),
          ),
          ProfileAction(
            icon: Icons.category_outlined,
            title: 'Категории',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerCategoriesScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.location_city_outlined,
            title: 'Регионы и города',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerLocationsScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.policy_outlined,
            title: 'Правовые документы',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerLegalScreen())),
          ),
          ProfileAction(
            icon: Icons.trending_up_rounded,
            title: 'Тарифы продвижения',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PromotionPlansScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.campaign_outlined,
            title: 'Баннеры пользователей',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OwnerBannersScreen()),
            ),
          ),
          ProfileAction(
            icon: Icons.forum_outlined,
            title: 'Все чаты',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerChatsScreen())),
          ),
        ],
      ),
    );
  }
}

class OwnerPushScreen extends StatefulWidget {
  const OwnerPushScreen({super.key});

  @override
  State<OwnerPushScreen> createState() => _OwnerPushScreenState();
}

class _OwnerPushScreenState extends State<OwnerPushScreen> {
  final titleRu = TextEditingController();
  final titleKk = TextEditingController();
  final bodyRu = TextEditingController();
  final bodyKk = TextEditingController();
  final userId = TextEditingController();
  bool saving = false;
  bool singleUser = false;

  @override
  void dispose() {
    titleRu.dispose();
    titleKk.dispose();
    bodyRu.dispose();
    bodyKk.dispose();
    userId.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final store = ClassifiedsScope.of(context);
    if (titleRu.text.trim().isEmpty || bodyRu.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните заголовок и текст RU')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await store.ownerSendPush(
        titleRu: titleRu.text,
        titleKk: titleKk.text.trim().isEmpty ? titleRu.text : titleKk.text,
        bodyRu: bodyRu.text,
        bodyKk: bodyKk.text.trim().isEmpty ? bodyRu.text : bodyKk.text,
        userId: singleUser ? userId.text : '',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Push отправлен')));
        titleRu.clear();
        titleKk.clear();
        bodyRu.clear();
        bodyKk.clear();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Отправить push RU/KK')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            value: singleUser,
            onChanged: (value) => setState(() => singleUser = value),
            title: const Text('Отправить одному пользователю'),
            subtitle: const Text('Иначе отправка всем пользователям'),
          ),
          if (singleUser) ...[
            const SizedBox(height: 10),
            TextField(
              controller: userId,
              decoration: const InputDecoration(labelText: 'User ID'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: titleRu,
            decoration: const InputDecoration(labelText: 'Заголовок RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: titleKk,
            decoration: const InputDecoration(labelText: 'Заголовок KK'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: bodyRu,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Текст RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: bodyKk,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Текст KK'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saving ? null : _send,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: Text(saving ? 'Отправка...' : 'Отправить'),
          ),
        ],
      ),
    );
  }
}

class OwnerLegalScreen extends StatefulWidget {
  const OwnerLegalScreen({super.key});

  @override
  State<OwnerLegalScreen> createState() => _OwnerLegalScreenState();
}

class _OwnerLegalScreenState extends State<OwnerLegalScreen> {
  final version = TextEditingController();
  final controllers =
      <String, ({TextEditingController ru, TextEditingController kk})>{};
  bool loading = true;
  bool saving = false;

  static const docs = [
    LegalDocumentItem(id: 'terms', title: 'Пользовательское соглашение'),
    LegalDocumentItem(id: 'privacy', title: 'Политика конфиденциальности'),
    LegalDocumentItem(id: 'promotion', title: 'Условия продвижения'),
    LegalDocumentItem(id: 'payment', title: 'Условия оплаты'),
    LegalDocumentItem(id: 'refund', title: 'Условия возврата'),
  ];

  @override
  void initState() {
    super.initState();
    for (final item in docs) {
      controllers[item.id] = (
        ru: TextEditingController(),
        kk: TextEditingController(),
      );
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appSettings')
          .doc('legal')
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      version.text = '${data['currentVersion'] ?? ''}';
      final documents = data['documents'] is Map
          ? Map<String, dynamic>.from(data['documents'] as Map)
          : <String, dynamic>{};
      for (final item in docs) {
        final raw = documents[item.id];
        final map = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        controllers[item.id]?.ru.text = '${map['ru'] ?? ''}';
        controllers[item.id]?.kk.text = '${map['kk'] ?? ''}';
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    version.dispose();
    for (final pair in controllers.values) {
      pair.ru.dispose();
      pair.kk.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final store = ClassifiedsScope.of(context);
    setState(() => saving = true);
    try {
      await store.ownerSaveLegalDocuments(
        version: version.text.trim().isEmpty
            ? DateTime.now().toIso8601String().substring(0, 10)
            : version.text.trim(),
        documents: {
          for (final item in docs)
            item.id: {
              'ru': controllers[item.id]?.ru.text.trim() ?? '',
              'kk': controllers[item.id]?.kk.text.trim() ?? '',
            },
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Документы сохранены')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Правовые документы')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: version,
            decoration: const InputDecoration(labelText: 'Версия документов'),
          ),
          const SizedBox(height: 14),
          ...docs.map((item) {
            final pair = controllers[item.id]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pair.ru,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(labelText: 'RU'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pair.kk,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(labelText: 'KK'),
                    ),
                  ],
                ),
              ),
            );
          }),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Сохранение...' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class OwnerAppSettingsScreen extends StatefulWidget {
  const OwnerAppSettingsScreen({super.key});

  @override
  State<OwnerAppSettingsScreen> createState() => _OwnerAppSettingsScreenState();
}

class _OwnerAppSettingsScreenState extends State<OwnerAppSettingsScreen> {
  final supportPhone = TextEditingController();
  final supportWhatsApp = TextEditingController();
  final maxListingPhotos = TextEditingController(text: '10');
  final maxBannerDays = TextEditingController(text: '30');
  bool loading = true;
  bool saving = false;
  bool moderationEnabled = true;
  double autoApproveBelow = .25;
  double ownerReviewAbove = .55;
  double autoRejectAbove = .9;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appSettings')
          .doc('general')
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      supportPhone.text = '${data['supportPhone'] ?? ''}';
      supportWhatsApp.text = '${data['supportWhatsApp'] ?? ''}';
      maxListingPhotos.text = '${data['maxListingPhotos'] ?? 10}';
      maxBannerDays.text = '${data['maxBannerDays'] ?? 30}';
      moderationEnabled = data['moderationEnabled'] != false;
      autoApproveBelow = NumberParser.toDouble(data['autoApproveBelow']);
      if (autoApproveBelow <= 0) autoApproveBelow = .25;
      ownerReviewAbove = NumberParser.toDouble(data['ownerReviewAbove']);
      if (ownerReviewAbove <= 0) ownerReviewAbove = .55;
      autoRejectAbove = NumberParser.toDouble(data['autoRejectAbove']);
      if (autoRejectAbove <= 0) autoRejectAbove = .9;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    supportPhone.dispose();
    supportWhatsApp.dispose();
    maxListingPhotos.dispose();
    maxBannerDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ClassifiedsScope.of(context);
    setState(() => saving = true);
    try {
      await store.ownerSaveAppSettings(
        supportPhone: supportPhone.text,
        supportWhatsApp: supportWhatsApp.text,
        moderationEnabled: moderationEnabled,
        autoApproveBelow: autoApproveBelow,
        ownerReviewAbove: ownerReviewAbove,
        autoRejectAbove: autoRejectAbove,
        maxListingPhotos: int.tryParse(maxListingPhotos.text) ?? 10,
        maxBannerDays: int.tryParse(maxBannerDays.text) ?? 30,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _riskSlider({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return CGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ${(value * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки приложения')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: supportPhone,
            decoration: const InputDecoration(labelText: 'Телефон поддержки'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: supportWhatsApp,
            decoration: const InputDecoration(labelText: 'WhatsApp поддержки'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: maxListingPhotos,
            decoration: const InputDecoration(
              labelText: 'Макс. фото объявления',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: maxBannerDays,
            decoration: const InputDecoration(labelText: 'Макс. дней баннера'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: moderationEnabled,
            onChanged: (value) => setState(() => moderationEnabled = value),
            title: const Text('Модерация включена'),
          ),
          const SizedBox(height: 10),
          _riskSlider(
            title: 'Автоодобрение ниже риска',
            value: autoApproveBelow,
            onChanged: (value) => setState(() => autoApproveBelow = value),
          ),
          const SizedBox(height: 10),
          _riskSlider(
            title: 'Ручная проверка выше риска',
            value: ownerReviewAbove,
            onChanged: (value) => setState(() => ownerReviewAbove = value),
          ),
          const SizedBox(height: 10),
          _riskSlider(
            title: 'Автоотклонение выше риска',
            value: autoRejectAbove,
            onChanged: (value) => setState(() => autoRejectAbove = value),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(saving ? 'Сохранение...' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class OwnerListingsScreen extends StatefulWidget {
  const OwnerListingsScreen({super.key});

  @override
  State<OwnerListingsScreen> createState() => _OwnerListingsScreenState();
}

class _OwnerListingsScreenState extends State<OwnerListingsScreen> {
  final search = TextEditingController();
  ListingStatus? status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadFromFirebase();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _setStatus(
    ListingAd listing,
    ListingStatus nextStatus, {
    String reason = '',
  }) async {
    final store = ClassifiedsScope.of(context);
    try {
      await store.setOwnerListingStatus(listing, nextStatus, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(listingStatusMessage(nextStatus))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final query = search.text.trim().toLowerCase();
    final items = store.listings.where((listing) {
      if (status != null && listing.status != status) return false;
      if (query.isEmpty) return true;
      return '${listing.title} ${listing.ownerName} ${listing.phone} ${listing.city} ${listing.categoryId} ${listing.status.name}'
          .toLowerCase()
          .contains(query);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Все объявления')),
      body: RefreshIndicator(
        onRefresh: store.loadFromFirebase,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateListingScreen()),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Добавить объявление'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Поиск по названию, владельцу, городу',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ListingStatus?>(
              value: status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Все')),
                ...ListingStatus.values.map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(listingStatusMessage(item)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => status = value),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const EmptyState(
                title: 'Объявлений нет',
                text: 'Созданные пользователями объявления появятся здесь.',
                icon: Icons.list_alt_rounded,
              )
            else
              ...items.map(
                (listing) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: listing.images.isEmpty
                                ? Container(
                                    width: 58,
                                    height: 58,
                                    color: cSoftBlue,
                                    child: const Icon(
                                      Icons.image_outlined,
                                      color: cBlue,
                                    ),
                                  )
                                : Image.network(
                                    listing.images.first,
                                    width: 58,
                                    height: 58,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: 58,
                                              height: 58,
                                              color: cSoftBlue,
                                              child: const Icon(
                                                Icons.broken_image,
                                              ),
                                            ),
                                  ),
                          ),
                          title: Text(
                            listing.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${cMoney(listing.price)} • ${listing.city}\n${listing.ownerName} • ${listing.phone}',
                          ),
                          trailing: ListingStatusPill(status: listing.status),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ListingDetailsScreen(listingId: listing.id),
                            ),
                          ),
                        ),
                        if (listing.status == ListingStatus.rejected) ...[
                          const SizedBox(height: 8),
                          RejectionReasonBox(
                            reason: listing.rejectionReasonRu.isEmpty
                                ? 'Объявление нарушает правила публикации сервиса.'
                                : listing.rejectionReasonRu,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _setStatus(
                                listing,
                                ListingStatus.active,
                                reason: 'Одобрено владельцем приложения',
                              ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Опубликовать'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CreateListingScreen(
                                    editingListing: listing,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Редактировать'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина проверки',
                                initialReason:
                                    'Требуется дополнительная проверка',
                                onSubmit: (reason) => _setStatus(
                                  listing,
                                  ListingStatus.ownerReview,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('На проверку'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина архивации',
                                initialReason: 'Перенесено владельцем в архив',
                                onSubmit: (reason) => _setStatus(
                                  listing,
                                  ListingStatus.archived,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.archive_outlined),
                              label: const Text('Архив'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина отклонения',
                                initialReason:
                                    'Объявление нарушает правила сервиса',
                                onSubmit: (reason) => _setStatus(
                                  listing,
                                  ListingStatus.rejected,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.block_rounded),
                              label: const Text('Отклонить'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина удаления',
                                initialReason: 'Удалено владельцем приложения',
                                onSubmit: (reason) => _setStatus(
                                  listing,
                                  ListingStatus.deleted,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Удалить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void showOwnerReasonSheet(
  BuildContext context, {
  required String title,
  required String initialReason,
  required Future<void> Function(String reason) onSubmit,
}) {
  final reason = TextEditingController(text: initialReason);
  var saving = false;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: CGlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Текст для пользователя и журнала',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final value = reason.text.trim();
                        if (value.isEmpty) return;
                        setSheetState(() => saving = true);
                        try {
                          await onSubmit(value);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => saving = false);
                          }
                        }
                      },
                child: Text(saving ? 'Сохраняем...' : 'Применить'),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(reason.dispose);
}

class OwnerReportsScreen extends StatefulWidget {
  const OwnerReportsScreen({super.key});

  @override
  State<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends State<OwnerReportsScreen> {
  String status = 'open';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadOwnerData();
    });
  }

  Future<void> _resolve(OwnerReport report, String nextStatus) async {
    final store = ClassifiedsScope.of(context);
    try {
      await store.resolveOwnerReport(
        report,
        nextStatus,
        reason: nextStatus == 'resolved'
            ? 'Жалоба обработана владельцем'
            : 'Жалоба отклонена владельцем',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Жалоба: $nextStatus')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    }
  }

  Future<void> _archiveListing(OwnerReport report) async {
    final store = ClassifiedsScope.of(context);
    final listing = store.listings
        .where((item) => item.id == report.listingId)
        .firstOrNullC;
    if (listing == null) return;
    await store.setOwnerListingStatus(
      listing,
      ListingStatus.archived,
      reason: 'Архивировано по жалобе ${report.id}',
    );
    await store.resolveOwnerReport(
      report,
      'resolved',
      reason: 'Объявление архивировано по жалобе',
    );
  }

  Future<void> _deleteListing(OwnerReport report) async {
    final store = ClassifiedsScope.of(context);
    final listing = store.listings
        .where((item) => item.id == report.listingId)
        .firstOrNullC;
    if (listing == null) return;
    await store.setOwnerListingStatus(
      listing,
      ListingStatus.deleted,
      reason: 'Удалено по жалобе ${report.id}',
    );
    await store.resolveOwnerReport(
      report,
      'resolved',
      reason: 'Объявление удалено по жалобе',
    );
  }

  Future<void> _banReportedUser(OwnerReport report) async {
    final store = ClassifiedsScope.of(context);
    final targetId = report.reportedUserId.isNotEmpty
        ? report.reportedUserId
        : store.listings
                  .where((item) => item.id == report.listingId)
                  .firstOrNullC
                  ?.ownerId ??
              '';
    final user = store.ownerUsers
        .where((item) => item.id == targetId)
        .firstOrNullC;
    if (user == null) return;
    await store.setUserBlocked(user, true);
    await store.resolveOwnerReport(
      report,
      'resolved',
      reason: 'Пользователь заблокирован по жалобе',
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Действие выполнено')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final reports = store.ownerReports
        .where((report) => status == 'all' || report.status == status)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Жалобы')),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Открытые')),
                ButtonSegment(value: 'resolved', label: Text('Решённые')),
                ButtonSegment(value: 'all', label: Text('Все')),
              ],
              selected: {status},
              onSelectionChanged: (value) =>
                  setState(() => status = value.first),
            ),
            const SizedBox(height: 14),
            if (reports.isEmpty)
              const EmptyState(
                title: 'Жалоб нет',
                text: 'Жалобы на объявления и сообщения появятся здесь.',
                icon: Icons.report_gmailerrorred_rounded,
              )
            else
              ...reports.map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${report.type} • ${report.status}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(report.reason),
                        const SizedBox(height: 8),
                        Text(
                          [
                            'reporter ${report.reporterId}',
                            if (report.listingId.isNotEmpty)
                              'listing ${report.listingId}',
                            if (report.chatId.isNotEmpty)
                              'chat ${report.chatId}',
                            if (report.messageId.isNotEmpty)
                              'message ${report.messageId}',
                          ].join(' • '),
                          style: const TextStyle(color: cMuted, fontSize: 12),
                        ),
                        if (report.status == 'open') ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (report.listingId.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ListingDetailsScreen(
                                        listingId: report.listingId,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text('Открыть объявление'),
                                ),
                              if (report.chatId.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatDetailsScreen(
                                        chatId: report.chatId,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.forum_outlined),
                                  label: const Text('Открыть чат'),
                                ),
                              if (report.listingId.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _runAction(
                                      () => _archiveListing(report),
                                    );
                                  },
                                  icon: const Icon(Icons.archive_outlined),
                                  label: const Text('Архивировать'),
                                ),
                              if (report.listingId.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _runAction(
                                      () => _deleteListing(report),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  label: const Text('Удалить объявление'),
                                ),
                              if (report.reportedUserId.isNotEmpty ||
                                  report.listingId.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _runAction(
                                      () => _banReportedUser(report),
                                    );
                                  },
                                  icon: const Icon(Icons.block_rounded),
                                  label: const Text('Заблокировать автора'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _resolve(report, 'rejected'),
                                  child: const Text('Отклонить жалобу'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _resolve(report, 'resolved'),
                                  child: const Text('Закрыть'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OwnerBannersScreen extends StatefulWidget {
  const OwnerBannersScreen({super.key});

  @override
  State<OwnerBannersScreen> createState() => _OwnerBannersScreenState();
}

class _OwnerBannersScreenState extends State<OwnerBannersScreen> {
  ListingStatus? status;

  Future<void> _setStatus(
    UserBannerAd banner,
    ListingStatus nextStatus, {
    String reason = '',
  }) async {
    final store = ClassifiedsScope.of(context);
    try {
      await store.setOwnerBannerStatus(banner, nextStatus, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Баннер: ${listingStatusMessage(nextStatus)}'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final banners =
        store.banners
            .where((banner) => status == null || banner.status == status)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Баннеры пользователей')),
      body: RefreshIndicator(
        onRefresh: store.loadFromFirebase,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<ListingStatus?>(
              value: status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Все')),
                ...ListingStatus.values.map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(listingStatusMessage(item)),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => status = value),
            ),
            const SizedBox(height: 14),
            if (banners.isEmpty)
              const EmptyState(
                title: 'Баннеров нет',
                text: 'Пользовательские баннеры появятся здесь.',
                icon: Icons.campaign_outlined,
              )
            else
              ...banners.map(
                (banner) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: 130,
                            width: double.infinity,
                            child: CNetworkOrAssetImage(
                              banner.imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          banner.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(banner.caption),
                        const SizedBox(height: 6),
                        Text(
                          '${banner.ownerId} • ${listingStatusMessage(banner.status)}',
                          style: const TextStyle(color: cMuted, fontSize: 12),
                        ),
                        if (banner.rejectionReasonRu.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            banner.rejectionReasonRu,
                            style: const TextStyle(color: Color(0xFFC43D22)),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _setStatus(
                                banner,
                                ListingStatus.pendingPayment,
                                reason: 'Баннер одобрен, ожидает оплату',
                              ),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Одобрить'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) =>
                                    BannerCreateSheet(editingBanner: banner),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Редактировать'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _setStatus(
                                banner,
                                ListingStatus.active,
                                reason: 'Баннер опубликован владельцем',
                              ),
                              icon: const Icon(Icons.campaign_outlined),
                              label: const Text('Опубликовать'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина отклонения',
                                initialReason:
                                    'Баннер нарушает правила сервиса',
                                onSubmit: (reason) => _setStatus(
                                  banner,
                                  ListingStatus.rejected,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.block_rounded),
                              label: const Text('Отклонить'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => showOwnerReasonSheet(
                                context,
                                title: 'Причина удаления',
                                initialReason: 'Удалено владельцем приложения',
                                onSubmit: (reason) => _setStatus(
                                  banner,
                                  ListingStatus.deleted,
                                  reason: reason,
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Удалить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OwnerChatsScreen extends StatefulWidget {
  const OwnerChatsScreen({super.key});

  @override
  State<OwnerChatsScreen> createState() => _OwnerChatsScreenState();
}

class _OwnerChatsScreenState extends State<OwnerChatsScreen> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadChatsFromFirebase();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final query = search.text.trim().toLowerCase();
    final chats = store.chats.where((chat) {
      if (query.isEmpty) return true;
      return '${chat.title} ${chat.buyerId} ${chat.sellerId} ${chat.listingId}'
          .toLowerCase()
          .contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Все чаты')),
      body: RefreshIndicator(
        onRefresh: store.loadChatsFromFirebase,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Поиск по объявлению или участнику',
              ),
            ),
            const SizedBox(height: 14),
            if (chats.isEmpty)
              const EmptyState(
                title: 'Чатов нет',
                text: 'Диалоги пользователей появятся здесь.',
                icon: Icons.forum_outlined,
              )
            else
              ...chats.map(
                (chat) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CGlassCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: cBlue,
                      ),
                      title: Text(
                        chat.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${chat.buyerId} ↔ ${chat.sellerId}\n${chat.messages.length} сообщений',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatDetailsScreen(chatId: chat.id),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OwnerSupportTicketsScreen extends StatefulWidget {
  const OwnerSupportTicketsScreen({super.key});

  @override
  State<OwnerSupportTicketsScreen> createState() =>
      _OwnerSupportTicketsScreenState();
}

class _OwnerSupportTicketsScreenState extends State<OwnerSupportTicketsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadSupportTicketsFromFirebase();
    });
  }

  Future<void> _setStatus(
    SupportTicket ticket,
    String status, {
    String reply = '',
  }) async {
    final store = ClassifiedsScope.of(context);
    try {
      await store.setSupportTicketStatus(ticket, status, reply: reply);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Обращение: $status')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка')),
      body: RefreshIndicator(
        onRefresh: store.loadSupportTicketsFromFirebase,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (store.supportTickets.isEmpty)
              const EmptyState(
                title: 'Обращений нет',
                text: 'Новые обращения пользователей появятся здесь.',
                icon: Icons.support_agent_rounded,
              )
            else
              ...store.supportTickets.map(
                (ticket) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ticket.subject,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (ticket.status == 'open' ? cOrange : cGreen)
                                        .withOpacity(.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                ticket.status,
                                style: TextStyle(
                                  color: ticket.status == 'open'
                                      ? cOrange
                                      : cGreen,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${ticket.userName} • ${ticket.phone}',
                          style: const TextStyle(color: cMuted),
                        ),
                        const SizedBox(height: 10),
                        Text(ticket.message),
                        if (ticket.ownerReply.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cSoftBlue,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Ответ владельца: ${ticket.ownerReply}',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: ticket.status == 'open'
                                    ? null
                                    : () => _setStatus(ticket, 'open'),
                                child: const Text('Открыть'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: ticket.status == 'resolved'
                                    ? null
                                    : () => _setStatus(ticket, 'resolved'),
                                child: const Text('Закрыть'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => showSupportReplySheet(
                              context,
                              ticket,
                              onSubmit: (reply) =>
                                  _setStatus(ticket, 'resolved', reply: reply),
                            ),
                            icon: const Icon(Icons.reply_outlined),
                            label: const Text('Ответить и закрыть'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void showSupportReplySheet(
  BuildContext context,
  SupportTicket ticket, {
  required Future<void> Function(String reply) onSubmit,
}) {
  final reply = TextEditingController(text: ticket.ownerReply);
  var saving = false;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: CGlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ответ пользователю',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(ticket.subject, style: const TextStyle(color: cMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: reply,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Текст ответа',
                  hintText: 'Напишите решение или уточнение для пользователя',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final value = reply.text.trim();
                        if (value.isEmpty) return;
                        setSheetState(() => saving = true);
                        await onSubmit(value);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                child: Text(saving ? 'Отправляем...' : 'Отправить ответ'),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(reply.dispose);
}

class OwnerAnalyticsScreen extends StatefulWidget {
  const OwnerAnalyticsScreen({super.key});

  @override
  State<OwnerAnalyticsScreen> createState() => _OwnerAnalyticsScreenState();
}

class _OwnerAnalyticsScreenState extends State<OwnerAnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadOwnerData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final stats = store.ownerStats;
    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Пользователи',
                    value: '${stats.users}',
                    icon: Icons.people_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Выручка',
                    value: cMoney(stats.revenue),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Активные',
                    value: '${stats.activeListings}',
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'На проверке',
                    value: '${stats.moderationCases}',
                    icon: Icons.verified_user_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Баннеры',
                    value: '${stats.banners}',
                    icon: Icons.campaign_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Платежи',
                    value: '${stats.payments}',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Статусы объявлений', action: ''),
            const SizedBox(height: 10),
            ...ListingStatus.values.map((status) {
              final count = store.listings
                  .where((listing) => listing.status == status)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CGlassCard(
                  child: Row(
                    children: [
                      Expanded(child: Text(listingStatusMessage(status))),
                      Text(
                        '$count',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class OwnerPaymentsScreen extends StatefulWidget {
  const OwnerPaymentsScreen({super.key});

  @override
  State<OwnerPaymentsScreen> createState() => _OwnerPaymentsScreenState();
}

class _OwnerPaymentsScreenState extends State<OwnerPaymentsScreen> {
  String status = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadOwnerData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final payments = store.ownerPayments
        .where((payment) => status == 'all' || payment.status == status)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Платежи Kassa24')),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Все')),
                ButtonSegment(value: 'paid', label: Text('Paid')),
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'failed', label: Text('Failed')),
              ],
              selected: {status},
              onSelectionChanged: (value) =>
                  setState(() => status = value.first),
            ),
            const SizedBox(height: 14),
            if (payments.isEmpty)
              const EmptyState(
                title: 'Платежей нет',
                text: 'Платежи продвижений и баннеров появятся здесь.',
                icon: Icons.payments_outlined,
              )
            else
              ...payments.map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${payment.type} • ${payment.status}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            Text(
                              cMoney(payment.amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            payment.provider,
                            payment.userId,
                            if (payment.listingId.isNotEmpty)
                              'объявление ${payment.listingId}',
                            if (payment.bannerId.isNotEmpty)
                              'баннер ${payment.bannerId}',
                          ].join(' • '),
                          style: const TextStyle(color: cMuted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          payment.id,
                          style: const TextStyle(color: cMuted, fontSize: 12),
                        ),
                        if (payment.provider == 'kassa24' &&
                            payment.status != 'paid') ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  final status = await store.ownerSyncPayment(
                                    payment,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Kassa24: $status'),
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Ошибка: $error')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Проверить Kassa24'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OwnerAuditScreen extends StatefulWidget {
  const OwnerAuditScreen({super.key});

  @override
  State<OwnerAuditScreen> createState() => _OwnerAuditScreenState();
}

class _OwnerAuditScreenState extends State<OwnerAuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadOwnerData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Журнал действий')),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: store.ownerAuditEvents.isEmpty
              ? const [
                  EmptyState(
                    title: 'Журнал пуст',
                    text: 'Действия владельца появятся после изменений.',
                    icon: Icons.history_rounded,
                  ),
                ]
              : store.ownerAuditEvents
                    .map(
                      (event) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.action,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${event.targetType} • ${event.targetId}',
                                style: const TextStyle(color: cMuted),
                              ),
                              if (event.details.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  event.details.entries
                                      .map(
                                        (entry) =>
                                            '${entry.key}: ${entry.value}',
                                      )
                                      .join('\n'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return CGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cBlue),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          Text(label, style: const TextStyle(color: cMuted)),
        ],
      ),
    );
  }
}

class OwnerUsersScreen extends StatefulWidget {
  const OwnerUsersScreen({super.key});
  @override
  State<OwnerUsersScreen> createState() => _OwnerUsersScreenState();
}

class _OwnerUsersScreenState extends State<OwnerUsersScreen> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ClassifiedsScope.of(context).loadOwnerData();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final query = search.text.trim().toLowerCase();
    final users = store.ownerUsers.where((user) {
      if (query.isEmpty) return true;
      return '${user.name} ${user.phone} ${user.city} ${user.role} ${user.status}'
          .toLowerCase()
          .contains(query);
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Поиск по имени, телефону, городу, роли',
              ),
            ),
            const SizedBox(height: 14),
            if (users.isEmpty)
              const EmptyState(
                title: 'Пользователей пока нет',
                text: 'После авторизации пользователей список появится здесь.',
                icon: Icons.people_outline_rounded,
              )
            else
              ...users.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CGlassCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: cSoftBlue,
                        child: Icon(
                          user.role == 'owner'
                              ? Icons.admin_panel_settings_outlined
                              : Icons.person_outline_rounded,
                          color: cBlue,
                        ),
                      ),
                      title: Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        [
                          user.phone,
                          if (user.city.isNotEmpty) user.city,
                          'статус: ${user.status}',
                          'нарушений: ${user.violationCount}',
                          if (user.bannedReasonRu.isNotEmpty)
                            user.bannedReasonRu,
                        ].join(' • '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OwnerUserDetailsScreen(user: user),
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value.startsWith('role:')) {
                            await store.setUserRole(
                              user,
                              value.replaceFirst('role:', ''),
                            );
                          }
                          if (value == 'ban') {
                            await store.setUserBlocked(user, true);
                          }
                          if (value == 'unban') {
                            await store.setUserBlocked(user, false);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'role:user',
                            child: Text('Роль: user'),
                          ),
                          const PopupMenuItem(
                            value: 'role:admin',
                            child: Text('Роль: admin'),
                          ),
                          const PopupMenuItem(
                            value: 'role:owner',
                            child: Text('Роль: owner'),
                          ),
                          PopupMenuItem(
                            value: user.status == 'banned' ? 'unban' : 'ban',
                            child: Text(
                              user.status == 'banned'
                                  ? 'Разблокировать'
                                  : 'Заблокировать',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class OwnerUserDetailsScreen extends StatelessWidget {
  const OwnerUserDetailsScreen({required this.user, super.key});

  final AppUserProfile user;

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final activeUser = store.ownerUsers.firstWhere(
      (item) => item.id == user.id,
      orElse: () => user,
    );
    final listings =
        store.listings.where((item) => item.ownerId == activeUser.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final banners =
        store.banners.where((item) => item.ownerId == activeUser.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final payments = store.ownerPayments
        .where((item) => item.userId == activeUser.id)
        .toList();
    final reports = store.ownerReports
        .where(
          (item) =>
              item.reporterId == activeUser.id ||
              item.reportedUserId == activeUser.id,
        )
        .toList();
    final revenue = payments
        .where((item) => item.status == 'paid')
        .fold<int>(0, (total, item) => total + item.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(activeUser.name),
        actions: [
          IconButton(
            tooltip: 'Редактировать',
            onPressed: () => showOwnerUserEditSheet(context, activeUser),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.loadOwnerData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            CGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeUser.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      activeUser.phone,
                      if (activeUser.city.isNotEmpty) activeUser.city,
                      activeUser.sellerType == 'business'
                          ? 'бизнес'
                          : 'частное лицо',
                      'роль: ${activeUser.role}',
                      'статус: ${activeUser.status}',
                      'нарушений: ${activeUser.violationCount}',
                    ].join(' • '),
                    style: const TextStyle(color: cMuted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        showOwnerUserEditSheet(context, activeUser),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Изменить профиль'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Объявления',
                    value: '${listings.length}',
                    icon: Icons.list_alt_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Платежи',
                    value: cMoney(revenue),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Объявления пользователя', action: ''),
            const SizedBox(height: 8),
            if (listings.isEmpty)
              const EmptyState(
                title: 'Объявлений нет',
                text: 'У этого пользователя пока нет объявлений.',
                icon: Icons.list_alt_rounded,
              )
            else
              ...listings
                  .take(10)
                  .map(
                    (listing) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CGlassCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            listing.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            '${cMoney(listing.price)} • ${listing.city} • ${listingStatusMessage(listing.status)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ListingDetailsScreen(listingId: listing.id),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Баннеры', action: ''),
            const SizedBox(height: 8),
            ...banners
                .take(6)
                .map(
                  (banner) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CGlassCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          banner.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(listingStatusMessage(banner.status)),
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Платежи', action: ''),
            const SizedBox(height: 8),
            ...payments
                .take(8)
                .map(
                  (payment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CGlassCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${payment.type} • ${payment.status}'),
                        subtitle: Text(payment.id),
                        trailing: Text(cMoney(payment.amount)),
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Жалобы', action: ''),
            const SizedBox(height: 8),
            ...reports
                .take(8)
                .map(
                  (report) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CGlassCard(
                      child: Text('${report.status}: ${report.reason}'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

void showOwnerUserEditSheet(BuildContext context, AppUserProfile user) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OwnerUserEditSheet(user: user),
  );
}

class OwnerUserEditSheet extends StatefulWidget {
  const OwnerUserEditSheet({required this.user, super.key});
  final AppUserProfile user;

  @override
  State<OwnerUserEditSheet> createState() => _OwnerUserEditSheetState();
}

class _OwnerUserEditSheetState extends State<OwnerUserEditSheet> {
  late final name = TextEditingController(text: widget.user.name);
  late final phone = TextEditingController(text: widget.user.phone);
  late final city = TextEditingController(text: widget.user.city);
  late String sellerType = widget.user.sellerType == 'business'
      ? 'business'
      : 'private';
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    city.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await ClassifiedsScope.of(context).updateOwnerUserProfile(
        user: widget.user,
        name: name.text,
        city: city.text,
        phone: phone.text,
        sellerType: sellerType,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Профиль: $error')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: CGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Профиль пользователя',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Имя'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              inputFormatters: const [KazakhstanPhoneFormatter()],
              decoration: const InputDecoration(
                labelText: 'Телефон',
                hintText: '+7 (___) ___-__-__',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: city,
              decoration: const InputDecoration(labelText: 'Город'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: sellerType,
              decoration: const InputDecoration(labelText: 'Тип аккаунта'),
              items: const [
                DropdownMenuItem(value: 'private', child: Text('Частное лицо')),
                DropdownMenuItem(value: 'business', child: Text('Бизнес')),
              ],
              onChanged: (value) =>
                  setState(() => sellerType = value ?? 'private'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerCategoriesScreen extends StatelessWidget {
  const OwnerCategoriesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    final categories = store.categories.where((item) => item.id != 'all');
    return Scaffold(
      appBar: AppBar(title: const Text('Категории')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategorySheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CGlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(category.icon, color: cBlue),
                  title: Text(
                    category.titleRu,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${category.titleKk}\n${category.subcategories.length} подкатегорий, ${category.filters.length} фильтров',
                  ),
                  trailing: IconButton(
                    onPressed: () => showCategorySheet(context, category),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class OwnerLocationsScreen extends StatelessWidget {
  const OwnerLocationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Регионы и города')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLocationEditSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить'),
      ),
      body: RefreshIndicator(
        onRefresh: store.loadFromFirebase,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (store.locations.isEmpty)
              const EmptyState(
                title: 'Локаций нет',
                text: 'Добавьте области и города для публикации объявлений.',
                icon: Icons.location_city_outlined,
              )
            else
              ...store.locations.map(
                (location) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CGlassCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.location_city_outlined,
                        color: cBlue,
                      ),
                      title: Text(
                        location.regionRu,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        '${location.regionKk}\n${location.cities.take(8).join(', ')}',
                      ),
                      trailing: IconButton(
                        onPressed: () =>
                            showLocationEditSheet(context, location),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

void showLocationEditSheet(BuildContext context, [ListingLocation? location]) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LocationEditSheet(location: location),
  );
}

class LocationEditSheet extends StatefulWidget {
  const LocationEditSheet({this.location, super.key});
  final ListingLocation? location;
  @override
  State<LocationEditSheet> createState() => _LocationEditSheetState();
}

class _LocationEditSheetState extends State<LocationEditSheet> {
  late final id = TextEditingController(text: widget.location?.id ?? '');
  late final ru = TextEditingController(text: widget.location?.regionRu ?? '');
  late final kk = TextEditingController(text: widget.location?.regionKk ?? '');
  late final cities = TextEditingController(
    text: widget.location?.cities.join('\n') ?? '',
  );
  bool active = true;
  bool saving = false;

  @override
  void dispose() {
    id.dispose();
    ru.dispose();
    kk.dispose();
    cities.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SheetFrame(
      title: widget.location == null ? 'Новая область' : 'Область',
      child: Column(
        children: [
          TextField(
            controller: id,
            enabled: widget.location == null,
            decoration: const InputDecoration(labelText: 'ID области'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ru,
            decoration: const InputDecoration(labelText: 'Название RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: kk,
            decoration: const InputDecoration(labelText: 'Название KK'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cities,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Города',
              hintText: 'Алматы\nКаскелен\nТалгар',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: active,
            onChanged: (value) => setState(() => active = value),
            title: const Text('Активна'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await store.saveLocation(
                          ListingLocation(
                            id: id.text.trim(),
                            regionRu: ru.text.trim(),
                            regionKk: kk.text.trim().isEmpty
                                ? ru.text.trim()
                                : kk.text.trim(),
                            cities: cities.text
                                .split('\n')
                                .map((item) => item.trim())
                                .where((item) => item.isNotEmpty)
                                .toList(),
                          ),
                          active,
                        );
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка: $error')),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Сохранение...' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}

void showCategorySheet(BuildContext context, [ListingCategory? category]) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CategoryEditSheet(category: category),
  );
}

class CategoryEditSheet extends StatefulWidget {
  const CategoryEditSheet({this.category, super.key});
  final ListingCategory? category;
  @override
  State<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<CategoryEditSheet> {
  late final id = TextEditingController(text: widget.category?.id ?? '');
  late final ru = TextEditingController(text: widget.category?.titleRu ?? '');
  late final kk = TextEditingController(text: widget.category?.titleKk ?? '');
  late String selectedIconKey = widget.category?.iconKey ?? 'grid';
  late final subcategories = TextEditingController(
    text: widget.category == null
        ? ''
        : widget.category!.subcategories
              .map((item) => '${item.id}:${item.titleRu}:${item.titleKk}')
              .join('\n'),
  );
  late final filters = TextEditingController(
    text: widget.category == null
        ? ''
        : widget.category!.filters
              .map(
                (item) =>
                    '${item.id}|${item.titleRu}|${item.titleKk}|${item.options.join(', ')}',
              )
              .join('\n'),
  );
  late bool active = widget.category?.isActive ?? true;
  bool saving = false;

  @override
  void dispose() {
    id.dispose();
    ru.dispose();
    kk.dispose();
    subcategories.dispose();
    filters.dispose();
    super.dispose();
  }

  List<ListingSubcategory> parseSubcategories() {
    return subcategories.text
        .split('\n')
        .map((line) {
          final parts = line.split(':').map((part) => part.trim()).toList();
          if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) {
            return null;
          }
          return ListingSubcategory(
            id: parts[0],
            titleRu: parts[1],
            titleKk: parts.length > 2 && parts[2].isNotEmpty
                ? parts[2]
                : parts[1],
          );
        })
        .whereType<ListingSubcategory>()
        .toList();
  }

  List<ListingAttributeFilter> parseFilters() {
    return filters.text
        .split('\n')
        .map((line) {
          final parts = line.split('|').map((part) => part.trim()).toList();
          if (parts.length < 4 ||
              parts[0].isEmpty ||
              parts[1].isEmpty ||
              parts[3].isEmpty) {
            return null;
          }
          final options = parts[3]
              .split(',')
              .map((option) => option.trim())
              .where((option) => option.isNotEmpty)
              .toList();
          if (options.isEmpty) return null;
          return ListingAttributeFilter(
            id: parts[0],
            titleRu: parts[1],
            titleKk: parts[2].isEmpty ? parts[1] : parts[2],
            options: options,
          );
        })
        .whereType<ListingAttributeFilter>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SheetFrame(
      title: widget.category == null ? 'Новая категория' : 'Категория',
      child: Column(
        children: [
          TextField(
            controller: id,
            enabled: widget.category == null,
            decoration: const InputDecoration(labelText: 'ID категории'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ru,
            decoration: const InputDecoration(labelText: 'Название RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: kk,
            decoration: const InputDecoration(labelText: 'Название KK'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: categoryIconOptions.containsKey(selectedIconKey)
                ? selectedIconKey
                : 'grid',
            decoration: const InputDecoration(labelText: 'Иконка'),
            items: categoryIconOptions.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Row(
                      children: [
                        Icon(entry.value, color: cBlue),
                        const SizedBox(width: 10),
                        Text(entry.key),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => selectedIconKey = value ?? selectedIconKey),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: subcategories,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Подкатегории',
              hintText: 'phones:Телефоны:Телефондар',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: filters,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Фильтры',
              hintText: 'brand|Бренд|Бренд|Apple, Samsung, Xiaomi',
            ),
          ),
          SwitchListTile(
            value: active,
            onChanged: (value) => setState(() => active = value),
            title: const Text('Показывать в каталоге'),
            contentPadding: EdgeInsets.zero,
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await store.saveCategory(
                        id: id.text,
                        titleRu: ru.text,
                        titleKk: kk.text,
                        iconKey: selectedIconKey,
                        isActive: active,
                        subcategories: parseSubcategories(),
                        filters: parseFilters(),
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            child: Text(saving ? 'Сохраняем...' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class PromotionPlansScreen extends StatelessWidget {
  const PromotionPlansScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Тарифы продвижения')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => showPlanSheet(
              context,
              PromotionPlan(
                id: 'promotion_${DateTime.now().millisecondsSinceEpoch}',
                title: '',
                caption: '',
                price: 0,
                days: 7,
              ),
              false,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить тариф продвижения'),
          ),
          const SizedBox(height: 12),
          if (store.promotionPlans.isEmpty)
            const EmptyState(
              title: 'Тарифов продвижения нет',
              text:
                  'Добавьте тариф, чтобы пользователи могли продвигать объявления.',
              icon: Icons.trending_up_rounded,
            ),
          ...store.promotionPlans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CGlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    plan.localizedTitle(store.language),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${plan.localizedCaption(store.language)}\n${plan.price} ₸, ${plan.days} дней${plan.isActive ? '' : ' · отключен'}',
                  ),
                  trailing: IconButton(
                    onPressed: () => showPlanSheet(context, plan, false),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const SectionHeader(title: 'Баннеры', action: ''),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => showPlanSheet(
              context,
              PromotionPlan(
                id: 'banner_${DateTime.now().millisecondsSinceEpoch}',
                title: '',
                caption: '',
                price: 0,
                days: 7,
              ),
              true,
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить тариф баннера'),
          ),
          const SizedBox(height: 12),
          if (store.bannerPlans.isEmpty)
            const EmptyState(
              title: 'Тарифов баннеров нет',
              text:
                  'Добавьте тариф, чтобы пользователи могли оплачивать баннеры.',
              icon: Icons.campaign_outlined,
            ),
          ...store.bannerPlans.map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CGlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    plan.localizedTitle(store.language),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${plan.localizedCaption(store.language)}\n${plan.price} ₸, ${plan.days} дней${plan.isActive ? '' : ' · отключен'}',
                  ),
                  trailing: IconButton(
                    onPressed: () => showPlanSheet(context, plan, true),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showPlanSheet(BuildContext context, PromotionPlan plan, bool banner) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PlanEditSheet(plan: plan, banner: banner),
  );
}

class PlanEditSheet extends StatefulWidget {
  const PlanEditSheet({required this.plan, required this.banner, super.key});
  final PromotionPlan plan;
  final bool banner;
  @override
  State<PlanEditSheet> createState() => _PlanEditSheetState();
}

class _PlanEditSheetState extends State<PlanEditSheet> {
  late final title = TextEditingController(text: widget.plan.title);
  late final titleKk = TextEditingController(text: widget.plan.titleKk);
  late final caption = TextEditingController(text: widget.plan.caption);
  late final captionKk = TextEditingController(text: widget.plan.captionKk);
  late final price = TextEditingController(text: '${widget.plan.price}');
  late final days = TextEditingController(text: '${widget.plan.days}');
  late bool active = widget.plan.isActive;
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    titleKk.dispose();
    caption.dispose();
    captionKk.dispose();
    price.dispose();
    days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ClassifiedsScope.of(context);
    return SheetFrame(
      title: widget.banner ? 'Тариф баннера' : 'Тариф продвижения',
      child: Column(
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Название RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: titleKk,
            decoration: const InputDecoration(labelText: 'Название KK'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: caption,
            decoration: const InputDecoration(labelText: 'Описание RU'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: captionKk,
            decoration: const InputDecoration(labelText: 'Описание KK'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Цена, ₸'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Дней'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            value: active,
            onChanged: (value) => setState(() => active = value),
            title: const Text('Тариф активен'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      await store.savePlan(
                        banner: widget.banner,
                        plan: PromotionPlan(
                          id: widget.plan.id,
                          title: title.text.trim(),
                          titleKk: titleKk.text.trim(),
                          caption: caption.text.trim(),
                          captionKk: captionKk.text.trim(),
                          price: NumberParser.toInt(price.text),
                          days: NumberParser.toInt(days.text),
                          isActive: active,
                        ),
                      );
                      if (context.mounted) Navigator.of(context).pop();
                    } finally {
                      if (mounted) setState(() => saving = false);
                    }
                  },
            child: Text(saving ? 'Сохраняем...' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

Future<void> openClassifiedsPayment(BuildContext context, String url) async {
  final store = ClassifiedsScope.of(context);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ClassifiedsPaymentScreen(url: url, store: store),
    ),
  );
}

class ClassifiedsPaymentScreen extends StatefulWidget {
  const ClassifiedsPaymentScreen({
    required this.url,
    required this.store,
    super.key,
  });
  final String url;
  final ClassifiedsStore store;

  @override
  State<ClassifiedsPaymentScreen> createState() =>
      _ClassifiedsPaymentScreenState();
}

class _ClassifiedsPaymentScreenState extends State<ClassifiedsPaymentScreen> {
  bool syncing = false;
  String status = '';

  Future<void> syncAndClose() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      final result = await widget.store.syncPendingPaymentStatus();
      if (!mounted) return;
      setState(() {
        syncing = false;
        status = switch (result) {
          'paid' => 'Оплата подтверждена',
          'failed' => 'Оплата не прошла',
          'none' => 'Платеж не найден',
          _ =>
            'Оплата еще не подтверждена. Нажмите проверку через несколько секунд.',
        };
      });
      if (result == 'paid' || result == 'failed') {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        syncing = false;
        status = 'Ошибка проверки оплаты';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось проверить оплату: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Оплата Kassa24')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PushkaPaymentView(
                url: widget.url,
                onPaymentFinished: syncAndClose,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        status,
                        style: const TextStyle(color: cMuted),
                      ),
                    ),
                  FilledButton(
                    onPressed: syncing ? null : syncAndClose,
                    child: Text(
                      syncing
                          ? 'Проверяем оплату...'
                          : 'Вернуться в приложение',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
