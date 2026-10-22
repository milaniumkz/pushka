# PUSHKA Production Checklist

## 1.0.1 (5), 22 October 2026

- Private source repository: https://github.com/milaniumkz/pushka
- Added a local inspection notebook: up to ten listing snapshots or manually entered personal items, six inspection checks, private notes and comparison of two or three candidates. Guest access; no cloud transmission of notebook data.
- Verified: 15 Flutter tests, clean static analysis, browser checks at phone and iPad sizes, signed IPA archive/export with version 1.0.1 and build 5.
- New iPhone/iPad screenshots and app description saved in App Store Connect; factual response to 4.3/4.2.6 sent. Detailed response: `APP_REVIEW_1.0.1.md`.
- Existing signing material and reviewer account retained outside Git. No passwords or signing keys are stored in the repository.
- IPA upload succeeded without errors, delivery UUID `085fdd28-d4e8-4dd6-8056-7b1c8fb133c6`. On 2026-10-22, version 1.0.1 build 5 was selected and resubmitted to App Review. App Store Connect confirms Waiting for Review (Ожидание проверки), submission `ab25beaa-fcf5-495c-b9b6-55facdace32f`. Automatic release after approval remains enabled. Evidence: local `output/apple-1.0.1-submitted.png`.

## Firebase

- Project: `pushkaapp-f4e4f`
- Hosting URL: `https://pushkaapp-f4e4f.web.app`
- Kassa24 callback URL: `https://kassa24callback-dt3st37u6q-uc.a.run.app`
- Firestore seed loaded: `listingCategories`, `locations`, `listings`, `promotionPlans`, `bannerPlans`, legal docs and owner profile.
- Production app entrypoint: `lib/main.dart` launches `ClassifiedsApp`.
- Production store uses Firebase-first data; local seeded data is test-only through `ClassifiedsStore.seeded()`.

## Backend

Core Cloud Functions:

- `requestWhatsAppOtp`
- `verifyWhatsAppOtp`
- `createListing`
- `updateListing`
- `createBannerAd`
- `sendMessage`
- `deleteMessage`
- `reportListing`
- `reportMessage`
- `trackListingView`
- `setListingFavorite`
- `purchasePromotion`
- `purchaseBannerPlacement`
- `ownerResolveModerationCase`
- `ownerSetUserStatus`
- `sendPushNotification`
- `kassa24Callback`

Security:

- Direct client writes to public `listings`, `bannerAds`, `messages`, `payments` are blocked.
- User content is written through Cloud Functions.
- Chat data is visible only to participants or owner/admin.
- Owner/admin actions require user role in Firestore.

## Payments

Kassa24 is used only for:

- listing boost/top/vip promotion;
- user banner placement.

Real-cabinet QA still required:

- payment success callback activates the selected service;
- payment failure keeps service inactive;
- return button opens the app/payment result screen correctly;
- callback fields match parser helpers in `firebase/functions/index.ts`.

## Wappi.pro

Публичная сборка 1.0.0 (4) собирается без `PUSHKA_DEMO_AUTH`. По решению владельца временно используется код доступа на экране без СМС. `requestDeviceAccessCode` / `verifyDeviceAccessCode` привязывают обычный профиль к случайному секрету установки, а не к номеру телефона. Номер не подтверждён; доступ после переустановки не восстанавливается. Отдельный аккаунт проверяющих использует постоянный код, обычную роль и общий лимит попыток. Покупки продвижения отключены на клиенте и сервере. Отдельный флаг `PUSHKA_DEMO_AUTH=true` остаётся только для локальных демонстраций.

Перед включением Wappi необходимо вернуть привязку `WAPPI_TOKEN` и `WAPPI_PROFILE_ID` к `requestWhatsAppOtp` через параметр `secrets` в `onCall`. Без привязки секретов сервер отклоняет вход. Затем настроить секреты:

```bash
printf '%s' '<WAPPI_TOKEN>' | firebase functions:secrets:set WAPPI_TOKEN --project pushkaapp-f4e4f --force
printf '%s' '<WAPPI_PROFILE_ID>' | firebase functions:secrets:set WAPPI_PROFILE_ID --project pushkaapp-f4e4f --force
firebase deploy --only functions --project pushkaapp-f4e4f --non-interactive
```

Будущий проверенный WhatsApp-вход не возвращает OTP клиенту и не использует постоянный код владельца. Он отделён от временного доступа по секрету установки. Перед включением доставки и переноса профилей между устройствами требуется отдельная проверка миграции; номера временных профилей не являются доказательством владения номером.

## Android Release Signing

Release keystore has been generated locally:

- Keystore: `android/app/pushka-release-key.jks`
- Properties: `android/key.properties`
- Alias: `pushka`

Build Google Play artifact:

```bash
/Volumes/PD1000/job/flutter/bin/flutter build appbundle --release
```

## iOS Release

Firebase SDK requires iOS 15.0 or newer. App Store release still requires Apple Developer signing and provisioning.

```bash
/Volumes/PD1000/job/flutter/bin/flutter build ipa --release
```

## Final QA

- Install release APK on a real Android device.
- Login through Wappi OTP.
- Create listing with photos and city from database list.
- Verify AI moderation statuses for listing, banner and chat.
- Buy each promotion type through Kassa24 and confirm activation.
- Create user banner, pass moderation, pay placement and confirm it appears on home.
- Test chat text, image/file sending, deletion and reporting.
- Verify push notifications on physical devices.
- Compare key screens with reference PUSHKA style on Android and iOS.
