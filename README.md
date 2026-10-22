# PUSHKA

Flutter + Firebase доска объявлений в стиле PUSHKA.

## Current State

- App brand: `PUSHKA`
- Platforms: Android, iOS, Web
- Backend: Firebase project `pushkaapp-f4e4f`
- Data source: Firestore/Storage/Cloud Functions
- Payments: disabled in the first store release
- Login: server-backed installation access with a displayed code and unverified phone; Wappi adapter retained for a future verified-phone flow
- AI moderation: Vertex AI adapter in Cloud Functions
- Languages: Russian and Kazakh
- Owner access: existing privileged Firebase accounts only; displayed-code access never grants an owner role

## Build

Тестовый вход без WhatsApp включается только отдельным флагом:

```bash
/Volumes/PD1000/job/flutter/bin/flutter build appbundle --release --dart-define=PUSHKA_DEMO_AUTH=true
/Volumes/PD1000/job/flutter/bin/flutter build ipa --release --dart-define=PUSHKA_DEMO_AUTH=true
```

Флаг выше включает изолированные локальные данные только для разработки. Для публикации собирайте без `PUSHKA_DEMO_AUTH`: обычная сборка использует живой Firebase и серверный код доступа на экране. Профиль привязан к случайному секрету установки, номер не подтверждён, восстановление по номеру после переустановки невозможно. Один номер на разных устройствах не даёт доступ к чужому профилю. Проверяющим выделен отдельный обычный аккаунт с постоянным кодом; данные сохранены локально в `.release-private/store-review-account.json`, в Firestore хранится только хеш кода. Покупки продвижения отключены.

```bash
/Volumes/PD1000/job/flutter/bin/flutter pub get
/Volumes/PD1000/job/flutter/bin/flutter analyze
/Volumes/PD1000/job/flutter/bin/flutter test
/Volumes/PD1000/job/flutter/bin/flutter build web --release
/Volumes/PD1000/job/flutter/bin/flutter build apk --release
/Volumes/PD1000/job/flutter/bin/flutter build appbundle --release
```

Android release artifacts:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

iOS compile check without Apple signing:

```bash
/Volumes/PD1000/job/flutter/bin/flutter build ios --release --no-codesign
```

App Store release requires Apple Developer signing and provisioning.

## Firebase

```bash
cd firebase/functions
npm install
npm run build
cd ../..
firebase deploy --only functions,firestore:rules,firestore:indexes,storage --project pushkaapp-f4e4f --non-interactive
```

Seed data:

```bash
cd firebase/functions
npm run seed
```

## Production Notes

See `PRODUCTION_READY.md` for callback URL, release signing data and final external QA items.
