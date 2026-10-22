# PUSHKA Integrations

Live integration state and values that must remain outside source control.

## Firebase

Connected project: `pushkaapp-f4e4f`

Configured locally:

- Android Firebase config: `android/app/google-services.json`
- iOS Firebase config: `ios/Runner/GoogleService-Info.plist`
- Flutter options: `lib/firebase_options.dart`
- Firestore rules: `firebase/firestore.rules`
- Firestore indexes: `firebase/firestore.indexes.json`
- Storage rules: `firebase/storage.rules`
- Cloud Functions: `firebase/functions/index.ts`
- Seed script: `firebase/functions/seed.ts`

Core backend entry points:

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

Critical backend rules:

- Listings and banners become public only after moderation approval.
- User-created listing/banner/chat writes go through Cloud Functions.
- Firestore blocks direct public writes to `listings`, `bannerAds`, `messages`, `payments`.
- Chat rooms/messages are readable only by participants or owner/admin.

## Wappi.pro

Flutter calls `requestWhatsAppOtp` and `verifyWhatsAppOtp`.

```bash
printf '%s' '<WAPPI_TOKEN>' | firebase functions:secrets:set WAPPI_TOKEN --project pushkaapp-f4e4f --force
printf '%s' '<WAPPI_PROFILE_ID>' | firebase functions:secrets:set WAPPI_PROFILE_ID --project pushkaapp-f4e4f --force
firebase deploy --only functions --project pushkaapp-f4e4f --non-interactive
```

When Wappi secrets are present, OTP code is not returned to the Flutter client.

Owner login uses the same OTP screen:

- Phone: `+7 000 000 00 00`
- Code: controlled by backend/local test fallback

## Kassa24

Configured callback URL:

```text
https://kassa24callback-dt3st37u6q-uc.a.run.app
```

Kassa24 credentials are stored as Firebase Functions secrets:

- `KASSA24_LOGIN`
- `KASSA24_KEY`
- `KASSA24_WEBHOOK_SECRET`

Implemented backend flows:

- listing promotion payment URL creation;
- user banner placement payment URL creation;
- callback processing;
- activation of `boostUntil`, `topUntil`, `vipUntil`, `activeUntil`.

Required real-cabinet checks:

- Set the callback URL in Kassa24 cabinet.
- Run real test payments for each promotion plan and banner plan.
- Confirm exact callback field names in Firebase logs.
- If Kassa24 returns different field names, adjust parser helpers in `firebase/functions/index.ts`.

## AI Moderation

Cloud Functions use the Firebase/Google Vertex AI adapter.

Moderated content:

- listing text and images;
- banner text and image;
- chat message text, images and files metadata.

Decisions:

- `approved`
- `rejected`
- `needs_owner_review`

Escalated cases are written to `moderationCases` and shown to the owner.
