import * as admin from "firebase-admin";
import { createHash, randomInt } from "node:crypto";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { deleteAccountData } from "./account_deletion";

admin.initializeApp();

setGlobalOptions({ cpu: "gcf_gen1", maxInstances: 1, region: "us-central1" });

const db = admin.firestore();
const messaging = admin.messaging();
const timestamp = admin.firestore.FieldValue.serverTimestamp;
const vertexAiLocation = process.env.FUNCTION_REGION ?? "us-central1";
const vertexAiProject = process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? "pushkaapp-f4e4f";
const vertexAiModel = "gemini-1.5-flash";
const adminPhone = "+70000000000";
const kassa24Login = defineSecret("KASSA24_LOGIN");
const kassa24Key = defineSecret("KASSA24_KEY");
const kassa24WebhookSecret = defineSecret("KASSA24_WEBHOOK_SECRET");
const kassa24PaymentApiBaseUrl = "https://ecommerce.pult24.kz/payment";
const kassa24ApiUrl = `${kassa24PaymentApiBaseUrl}/create`;
const kassa24StatusApiUrl = `${kassa24PaymentApiBaseUrl}/status`;
const kassa24CallbackBaseUrl = "https://kassa24callback-dt3st37u6q-uc.a.run.app";

type LocalizedText = {
  ru: string;
  kk: string;
};

type RequestOtpInput = {
  phone: string;
  name?: string;
  city?: string;
  language?: "ru" | "kk";
  acceptedLegalVersion?: string;
};

type VerifyOtpInput = {
  phone: string;
  code: string;
};

type CompleteUserProfileInput = {
  name: string;
  city: string;
};

type UpdateUserLanguageInput = {
  language: "ru" | "kk";
};

type RegisterFcmTokenInput = {
  token: string;
};

type MarkNotificationsReadInput = {
  notificationIds?: string[];
};

type SendPushInput = {
  userId?: string;
  topic?: string;
  title: LocalizedText;
  body: LocalizedText;
  data?: Record<string, string>;
};

type SyncPaymentStatusInput = {
  paymentId: string;
};

type CreateListingInput = {
  id?: string;
  title: string;
  description: string;
  categoryId: string;
  regionId?: string;
  price?: number;
  negotiable?: boolean;
  condition: string;
  city: string;
  district?: string;
  address?: string;
  phone?: string;
  images?: string[];
  sellerType?: string;
  attributes?: Record<string, string>;
  skipModeration?: boolean;
};

type UpdateListingInput = CreateListingInput & {
  listingId: string;
};

type SubmitListingInput = {
  listingId: string;
};

type ArchiveListingInput = {
  listingId: string;
};

type RestoreListingInput = {
  listingId: string;
};

type TrackListingCallInput = {
  listingId: string;
};

type ResolveListingCallInput = {
  listingId: string;
  notificationId?: string;
  agreed: boolean;
};

type CreateBannerAdInput = {
  id?: string;
  title: string;
  caption: string;
  imageUrl: string;
  targetUrl?: string;
};

type CreateChatRoomInput = {
  listingId: string;
};

type SendMessageInput = {
  chatId: string;
  text: string;
  imageUrl?: string;
  fileUrl?: string;
  fileName?: string;
};

type DeleteMessageInput = {
  chatId: string;
  messageId: string;
  reason?: string;
};

type ReportListingInput = {
  listingId: string;
  reason: string;
};

type ReportMessageInput = {
  chatId: string;
  messageId: string;
  reason: string;
};

type TrackListingViewInput = {
  listingId: string;
};

type SetListingFavoriteInput = {
  listingId: string;
  favorite: boolean;
};

type SaveSearchInput = {
  id?: string;
  title: string;
  query?: string;
  categoryId?: string;
  subcategoryId?: string;
  city?: string;
  minPrice?: number;
  maxPrice?: number;
  condition?: string;
  sortMode?: string;
  attributes?: Record<string, string>;
};

type DeleteSavedSearchInput = {
  searchId: string;
};

type CreateSupportTicketInput = {
  subject: string;
  message: string;
};

type PurchasePromotionInput = {
  listingId: string;
  planId: string;
};

type PurchaseBannerPlacementInput = {
  bannerId: string;
  planId: string;
};

type OwnerResolveModerationInput = {
  caseId?: string;
  targetId: string;
  type: "listing" | "banner" | "message";
  decision: "approved" | "rejected";
  reason?: string;
};

type OwnerSetUserStatusInput = {
  userId: string;
  status: "active" | "banned";
  reason?: string;
};

type OwnerSetUserRoleInput = {
  userId: string;
  role: "user" | "admin" | "owner";
};

type OwnerUpdateUserProfileInput = {
  userId: string;
  name?: string;
  city?: string;
  phone?: string;
  sellerType?: "private" | "business";
};

type OwnerModerationSweepInput = {
  limit?: number;
  rejectAll?: boolean;
};

type OwnerSetListingStatusInput = {
  listingId: string;
  status: "active" | "rejected" | "owner_review" | "archived" | "deleted";
  reason?: string;
};

type OwnerSetBannerStatusInput = {
  bannerId: string;
  status: "active" | "rejected" | "owner_review" | "pending_payment" | "archived" | "deleted";
  reason?: string;
};

type OwnerUpdateBannerInput = {
  bannerId: string;
  title: string;
  caption: string;
  imageUrl: string;
  targetUrl?: string;
};

type OwnerSetSupportTicketStatusInput = {
  ticketId: string;
  status: "open" | "closed" | "resolved";
  reply?: string;
};

type OwnerResolveReportInput = {
  reportId: string;
  status: "resolved" | "rejected";
  reason?: string;
};

type OwnerSaveCategoryInput = {
  id: string;
  titleRu: string;
  titleKk?: string;
  iconKey?: string;
  isActive: boolean;
  subcategories?: Array<{ id?: string; titleRu?: string; titleKk?: string }>;
  filters?: Array<{
    id?: string;
    titleRu?: string;
    titleKk?: string;
    options?: string[];
  }>;
};

type OwnerSavePlanInput = {
  id: string;
  title: string;
  titleKk?: string;
  caption: string;
  captionKk?: string;
  price: number;
  days: number;
  banner: boolean;
  isActive?: boolean;
};

type OwnerSaveLocationInput = {
  id: string;
  titleRu: string;
  titleKk?: string;
  cities: string[];
  isActive?: boolean;
};

type OwnerSaveLegalInput = {
  currentVersion?: string;
  documents: Record<string, LocalizedText>;
};

type OwnerSaveAppSettingsInput = {
  supportPhone?: string;
  supportWhatsApp?: string;
  moderationEnabled?: boolean;
  autoApproveBelow?: number;
  ownerReviewAbove?: number;
  autoRejectAbove?: number;
  maxListingPhotos?: number;
  maxBannerDays?: number;
};

type AiModerationResult = {
  decision: "approved" | "rejected" | "needs_owner_review";
  reason: LocalizedText;
  riskScore: number;
  flags: string[];
  provider?: string;
};

type ModerationTargetType = "listing" | "banner" | "message";

type Kassa24PaymentResult = {
  providerPaymentId?: string;
  paymentUrl?: string;
  raw: FirebaseFirestore.DocumentData;
};

function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("8")) {
    return `+7${digits.slice(1)}`;
  }
  if (digits.length === 11 && digits.startsWith("7")) {
    return `+${digits}`;
  }
  if (digits.length === 10) {
    return `+7${digits}`;
  }
  return phone.startsWith("+") ? phone : `+${digits}`;
}

function uidFromPhone(phone: string): string {
  return `phone_${normalizePhone(phone).replace(/\D/g, "")}`;
}

function assertSignedIn(request: { auth?: { uid: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "auth_required");
  }
  return uid;
}

async function assertAdmin(uid: string): Promise<void> {
  const userSnap = await db.collection("users").doc(uid).get();
  const role = userSnap.data()?.role;
  if (userSnap.data()?.status === "deleting") {
    throw new HttpsError("failed-precondition", "account_deletion_pending");
  }
  if (role !== "admin" && role !== "owner") {
    throw new HttpsError("permission-denied", "admin_required");
  }
}

async function writeOwnerAudit(
  actorId: string,
  action: string,
  targetType: string,
  targetId: string,
  details: Record<string, string | number | boolean | null> = {},
): Promise<void> {
  await db.collection("ownerAuditLog").add({
    actorId,
    action,
    targetType,
    targetId,
    details,
    createdAt: timestamp(),
  });
}

async function getUser(uid: string): Promise<FirebaseFirestore.DocumentData> {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "profile_required");
  }
  if (userSnap.data()?.status === "deleting") {
    throw new HttpsError("failed-precondition", "account_deletion_pending");
  }
  return userSnap.data()!;
}

function userIsBanned(user: FirebaseFirestore.DocumentData): boolean {
  const bannedUntil = user.bannedUntil?.toDate?.() as Date | undefined;
  return user.status === "banned" || (bannedUntil ? bannedUntil.getTime() > Date.now() : false);
}

function assertUserAllowed(user: FirebaseFirestore.DocumentData): void {
  if (userIsBanned(user)) {
    throw new HttpsError("permission-denied", "user_banned");
  }
}

function cleanText(value: unknown, max = 4000): string {
  return String(value ?? "").trim().slice(0, max);
}

function storagePathFromUrl(value: string): string {
  const url = cleanText(value, 1000);
  if (!url) {
    return "";
  }
  try {
    const parsed = new URL(url);
    const marker = "/o/";
    const markerIndex = parsed.pathname.indexOf(marker);
    if (!parsed.hostname.includes("firebasestorage.googleapis.com") || markerIndex < 0) {
      return "";
    }
    return decodeURIComponent(parsed.pathname.slice(markerIndex + marker.length));
  } catch {
    return "";
  }
}

function assertStorageUrlForUser(url: string, uid: string, allowedFolders: string[]): void {
  if (!url) {
    return;
  }
  const path = storagePathFromUrl(url);
  const allowed = allowedFolders.some((folder) => path.startsWith(`${folder}/${uid}/`));
  if (!allowed) {
    throw new HttpsError("invalid-argument", "storage_url_invalid");
  }
}

function assertStorageUrlsForUser(urls: string[], uid: string, allowedFolders: string[]): void {
  for (const url of urls) {
    assertStorageUrlForUser(url, uid, allowedFolders);
  }
}

function moderationStatus(decision: string, targetType: "listing" | "banner" | "message"): string {
  if (decision === "approved") {
    return targetType === "banner" ? "pending_payment" : "active";
  }
  if (decision === "rejected") {
    return "rejected";
  }
  return "owner_review";
}

type RuntimeAppSettings = {
  moderationEnabled: boolean;
  autoApproveBelow: number;
  ownerReviewAbove: number;
  autoRejectAbove: number;
  maxListingPhotos: number;
  maxBannerDays: number;
};

async function getRuntimeAppSettings(): Promise<RuntimeAppSettings> {
  const snap = await db.collection("appSettings").doc("general").get();
  const data = snap.data() ?? {};
  const numberValue = (value: unknown, fallback: number) => {
    const parsed = Number(value ?? fallback);
    return Number.isFinite(parsed) ? parsed : fallback;
  };
  return {
    moderationEnabled: data.moderationEnabled !== false,
    autoApproveBelow: Math.max(0, Math.min(1, numberValue(data.autoApproveBelow, 0.25))),
    ownerReviewAbove: Math.max(0, Math.min(1, numberValue(data.ownerReviewAbove, 0.55))),
    autoRejectAbove: Math.max(0, Math.min(1, numberValue(data.autoRejectAbove, 0.9))),
    maxListingPhotos: Math.max(1, Math.min(20, Math.round(numberValue(data.maxListingPhotos, 10)))),
    maxBannerDays: Math.max(1, Math.min(365, Math.round(numberValue(data.maxBannerDays, 30)))),
  };
}

function applyModerationSettings(
  result: AiModerationResult,
  settings: RuntimeAppSettings,
  targetType: ModerationTargetType,
): AiModerationResult {
  if (!settings.moderationEnabled) {
    return {
      decision: "approved",
      reason: {
        ru: targetType === "message" ? "Сообщение отправлено." : "Материал опубликован.",
        kk: targetType === "message" ? "Хабарлама жіберілді." : "Материал жарияланды.",
      },
      riskScore: 0,
      flags: ["moderation_disabled"],
      provider: result.provider ?? "settings",
    };
  }
  if (result.riskScore >= settings.autoRejectAbove) {
    return { ...result, decision: "rejected" };
  }
  if (result.riskScore >= settings.ownerReviewAbove && result.decision !== "rejected") {
    return {
      ...result,
      decision: "rejected",
      reason: {
        ru: "Материал отклонен: публикацию нельзя безопасно одобрить по правилам сервиса и законодательству Республики Казахстан.",
        kk: "Материал қабылданбады: сервис ережелері мен Қазақстан Республикасының заңнамасы бойынша қауіпсіз мақұлдау мүмкін емес.",
      },
      flags: uniqueStrings([...(result.flags ?? []), "auto_safe_reject"]),
    };
  }
  if (result.riskScore <= settings.autoApproveBelow && result.decision !== "rejected") {
    return { ...result, decision: "approved" };
  }
  if (result.decision === "needs_owner_review") {
    return {
      ...result,
      decision: "rejected",
      reason: {
        ru: "Материал отклонен: публикацию нельзя безопасно одобрить по правилам сервиса и законодательству Республики Казахстан.",
        kk: "Материал қабылданбады: сервис ережелері мен Қазақстан Республикасының заңнамасы бойынша қауіпсіз мақұлдау мүмкін емес.",
      },
      flags: uniqueStrings([...(result.flags ?? []), "auto_safe_reject"]),
    };
  }
  return result;
}

function hasCyrillicWordStem(text: string, stem: string): boolean {
  const normalized = text.toLowerCase().replace(/ё/g, "е");
  const safeStem = stem.toLowerCase().replace(/ё/g, "е").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^a-zа-я0-9])${safeStem}[a-zа-я0-9]*($|[^a-zа-я0-9])`, "i").test(normalized);
}

function heuristicModerateContent(input: {
  targetType?: ModerationTargetType;
  title?: string;
  description?: string;
  categoryId?: string;
  price?: number;
  images?: string[];
  userViolationCount?: number;
}): AiModerationResult {
  const rawText = `${input.title ?? ""} ${input.description ?? ""} ${input.categoryId ?? ""}`.toLowerCase().replace(/ё/g, "е");
  const rawTitle = `${input.title ?? ""}`.toLowerCase().replace(/ё/g, "е");
  const text = rawText.replace(/[^a-zа-я0-9]+/g, " ");
  const titleText = rawTitle.replace(/[^a-zа-я0-9]+/g, " ");
  const compactText = rawText.replace(/[^a-zа-я0-9]+/g, "");
  const kzIllegalGoods = [
    "наркот", "психотроп", "марихуан", "гашиш", "спайс", "закладк", "метадон", "героин", "кокаин",
    "оруж", "пистолет", "автомат", "ружь", "боеприп", "патрон", "гранат", "нож-бабочка", "кастет", "электрошок",
    "взрывчат", "пиротехник", "селитр", "тротил",
    "алкогол", "водка", "коньяк", "виски", "пиво", "самогон",
    "табак", "сигарет", "вейп", "жидкость для вейпа", "iqos", "насвай",
    "лекарств", "рецептур", "антибиотик", "анаболик", "стероид", "медицинск", "биоматериал", "донор",
    "паспорт", "удостоверен", "водительск", "диплом", "справк", "сертификат", "печать", "штамп",
    "база данных", "персональные данные", "пробив", "сим карта", "sim карта", "аккаунт госуслуг", "egov",
    "поддел", "реплика оригинал", "копия бренда", "контрафакт",
    "проститу", "эскорт", "интим услуг", "интимные услуги", "массаж 18", "услуги 18", "эротический массаж", "минет", "секс услуги",
    "майнинг ферма без документов", "финансовая пирамида", "гарант доход", "ставк", "казино", "букмекер",
    "крипта удвою", "обнал", "отмыв", "фальшив", "поддельные деньги",
  ];
  const fraud = [
    "мошен", "обман", "предоплат", "скинь код", "код из смс", "sms код", "cvv", "cvc",
    "номер карты", "пароль", "одноразовый код", "фишинг", "гарантия заработка", "быстрый доход",
  ];
  const profanity = [
    "хуй", "хуе", "хуя", "пизд", "пздц", "еба", "еби", "ебу", "ебл", "ёб", "ебан", "бля", "бляд",
    "сука", "сучар", "пидор", "пидр", "гандон", "мраз", "мудак", "долбо", "уеб", "уёб",
  ];
  const insults = ["тупой", "идиот", "дурак", "убью", "угрож"];
  const hardWords = [...kzIllegalGoods, ...fraud].map((word) => word.toLowerCase().replace(/ё/g, "е"));
  const flags = hardWords.filter((word) => text.includes(word) || compactText.includes(word.replace(/[^a-zа-я0-9]+/g, "")));
  const hasIntimInTitle = hasCyrillicWordStem(rawTitle, "интим");
  const hasIntimWithoutNegation =
    hasCyrillicWordStem(rawText, "интим") && !/(^|[^a-zа-я0-9])без\s+интим[a-zа-я0-9]*/i.test(rawText);
  if (hasIntimInTitle || hasIntimWithoutNegation) {
    flags.push("интим");
  }
  const profanityFlags = profanity.filter((word) => text.includes(word) || compactText.includes(word));
  const insultFlags = input.targetType === "message" ? insults.filter((word) => text.includes(word) || compactText.includes(word)) : [];
  const hasAdultService = flags.some((flag) => ["проститу", "эскорт", "интим", "интим услуг", "интимные услуги", "массаж 18", "услуги 18", "эротический массаж", "минет", "секс услуги"].includes(flag));
  const hasFraud = flags.some((flag) => fraud.includes(flag));
  const specificReasonsRu: string[] = [];
  const specificReasonsKk: string[] = [];
  if (profanityFlags.length > 0) {
    specificReasonsRu.push("ненормативная лексика");
    specificReasonsKk.push("балағат сөздер");
  }
  if (hasAdultService) {
    specificReasonsRu.push("интим-услуги и услуги 18+");
    specificReasonsKk.push("интим қызметтер мен 18+ қызметтер");
  }
  if (hasFraud) {
    specificReasonsRu.push("признаки мошенничества или запроса платежных/личных данных");
    specificReasonsKk.push("алаяқтық немесе төлем/жеке деректерді сұрау белгілері");
  }
  const combinedReasonRu = specificReasonsRu.length > 1
    ? `Материал отклонен: обнаружены нарушения: ${specificReasonsRu.join(", ")}.`
    : "";
  const combinedReasonKk = specificReasonsKk.length > 1
    ? `Материал қабылданбады: бұзушылықтар анықталды: ${specificReasonsKk.join(", ")}.`
    : "";
  if (profanityFlags.length > 0) {
    return {
      decision: "rejected",
      reason: {
        ru: combinedReasonRu || (input.targetType === "message"
          ? "Сообщение заблокировано: ненормативная лексика запрещена правилами сервиса."
          : "Материал отклонен: ненормативная лексика запрещена правилами сервиса."),
        kk: combinedReasonKk || (input.targetType === "message"
          ? "Хабарлама бұғатталды: балағат сөздер сервис ережелерімен тыйым салынған."
          : "Материал қабылданбады: балағат сөздер сервис ережелерімен тыйым салынған."),
      },
      riskScore: 0.98,
      flags: [...profanityFlags, ...flags],
      provider: "heuristic",
    };
  }
  if (insultFlags.length > 0) {
    return {
      decision: "rejected",
      reason: {
        ru: "Сообщение заблокировано: нарушает правила общения.",
        kk: "Хабарлама бұғатталды: қарым-қатынас ережелерін бұзады.",
      },
      riskScore: 0.9,
      flags: insultFlags,
      provider: "heuristic",
    };
  }
  if (flags.length > 0) {
    return {
      decision: "rejected",
      reason: {
        ru: hasAdultService
          ? "Материал отклонен: интим-услуги и услуги 18+ запрещены правилами сервиса."
          : hasFraud
            ? "Материал отклонен: обнаружены признаки мошенничества или запроса платежных/личных данных."
            : input.targetType === "message"
          ? "Сообщение заблокировано: найден контент, запрещенный правилами сервиса и законодательством Республики Казахстан."
          : "Материал отклонен: найден товар, услуга или контент, запрещенный правилами сервиса и законодательством Республики Казахстан.",
        kk: hasAdultService
          ? "Материал қабылданбады: интим қызметтер мен 18+ қызметтер сервис ережелерімен тыйым салынған."
          : hasFraud
            ? "Материал қабылданбады: алаяқтық немесе төлем/жеке деректерді сұрау белгілері анықталды."
            : input.targetType === "message"
          ? "Хабарлама бұғатталды: сервис ережелері мен Қазақстан Республикасының заңнамасына тыйым салынған мазмұн табылды."
          : "Материал қабылданбады: сервис ережелері мен Қазақстан Республикасының заңнамасына тыйым салынған тауар, қызмет немесе мазмұн табылды.",
      },
      riskScore: 0.94,
      flags,
      provider: "heuristic",
    };
  }
  if (input.targetType !== "message" && Number(input.price ?? 0) > 20000000) {
    return {
      decision: "rejected",
      reason: {
        ru: "Материал отклонен: цена выше допустимого лимита 20 000 000 ₸. Укажите реальную цену до 20 000 000 ₸ или выберите «Договорная».",
        kk: "Материал қабылданбады: баға рұқсат етілген 20 000 000 ₸ шегінен жоғары. 20 000 000 ₸ дейін нақты бағаны көрсетіңіз немесе «Келісімді» таңдаңыз.",
      },
      riskScore: 0.62,
      flags: ["price_too_high"],
      provider: "heuristic",
    };
  }
  return {
    decision: "approved",
    reason: {
      ru: input.targetType === "message" ? "Сообщение отправлено." : "Материал опубликован.",
      kk: input.targetType === "message" ? "Хабарлама жіберілді." : "Материал жарияланды.",
    },
    riskScore: 0.12,
    flags: [],
    provider: "heuristic",
  };
}

function parseAiModerationJson(text: string): AiModerationResult | null {
  const jsonText = text.trim().replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```$/i, "");
  let data: FirebaseFirestore.DocumentData;
  try {
    data = JSON.parse(jsonText) as FirebaseFirestore.DocumentData;
  } catch {
    return null;
  }
  const decision = String(data.decision ?? "");
  if (!["approved", "rejected", "needs_owner_review"].includes(decision)) {
    return null;
  }
  const riskScore = Math.max(0, Math.min(1, Number(data.riskScore ?? 0.5)));
  const reason = data.reason && typeof data.reason === "object" ? data.reason : {};
  const flags = Array.isArray(data.flags) ? data.flags.map((item) => String(item)).slice(0, 10) : [];
  return {
    decision: decision as AiModerationResult["decision"],
    reason: {
      ru: cleanText(reason.ru ?? data.reasonRu ?? "Статус проверки обновлен.", 500),
      kk: cleanText(reason.kk ?? data.reasonKk ?? "Тексеру мәртебесі жаңартылды.", 500),
    },
    riskScore,
    flags,
    provider: "vertex_ai_gemini",
  };
}

async function imagePartsFromUrls(urls: string[]): Promise<FirebaseFirestore.DocumentData[]> {
  const parts: FirebaseFirestore.DocumentData[] = [];
  for (const url of urls.slice(0, 4)) {
    if (!url.startsWith("http")) {
      continue;
    }
    try {
      const response = await fetch(url);
      const contentType = response.headers.get("content-type") ?? "";
      if (!response.ok || !contentType.startsWith("image/")) {
        continue;
      }
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length === 0 || bytes.length > 4 * 1024 * 1024) {
        continue;
      }
      parts.push({
        inlineData: {
          mimeType: contentType.split(";")[0],
          data: bytes.toString("base64"),
        },
      });
    } catch (error) {
      console.warn("Moderation image read skipped", error);
    }
  }
  return parts;
}

async function generateModerationText(requestParts: FirebaseFirestore.DocumentData[]): Promise<string> {
  const { GoogleAuth } = await import("google-auth-library");
  const googleAuth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const client = await googleAuth.getClient();
  const tokenResponse = await client.getAccessToken();
  const token = typeof tokenResponse === "string" ? tokenResponse : tokenResponse.token;
  if (!token) {
    throw new Error("vertex_ai_token_missing");
  }
  const endpoint = `https://${vertexAiLocation}-aiplatform.googleapis.com/v1/projects/${vertexAiProject}/locations/${vertexAiLocation}/publishers/google/models/${vertexAiModel}:generateContent`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      contents: [{ role: "user", parts: requestParts }],
      generationConfig: { temperature: 0, maxOutputTokens: 512 },
    }),
  });
  const payload = await response.json() as FirebaseFirestore.DocumentData;
  if (!response.ok) {
    throw new Error(`vertex_ai_error_${response.status}_${JSON.stringify(payload).slice(0, 300)}`);
  }
  const responseParts = payload.candidates?.[0]?.content?.parts;
  if (!Array.isArray(responseParts)) {
    return "";
  }
  return responseParts.map((part) => String(part.text ?? "")).join("");
}

async function moderateContent(input: {
  targetType?: ModerationTargetType;
  title?: string;
  description?: string;
  categoryId?: string;
  price?: number;
  images?: string[];
  userViolationCount?: number;
}): Promise<AiModerationResult> {
  const fallback = heuristicModerateContent(input);
  if (fallback.decision === "rejected" && fallback.riskScore >= 0.9) {
    return fallback;
  }
  try {
    const prompt = [
      "Ты AI-модератор доски объявлений PUSHKA в Казахстане.",
      "Проверь текст объявления, баннера или сообщения и все прикрепленные изображения.",
      "На изображениях прочитай видимый текст, номера, документы, водяные знаки, QR/ссылки, признаки мошенничества и запрещенные товары.",
      "Проверяй по правилам сервиса и законодательству Республики Казахстан.",
      "Запрещай: оружие, боеприпасы, взрывчатые вещества, наркотические/психотропные вещества, алкоголь, табак, вейпы, насвай, рецептурные лекарства и опасные медтовары, человеческие биоматериалы, документы/печати/штампы, персональные базы данных, SIM/аккаунты с чужими данными, контрафакт, поддельные товары и деньги, интим/эскорт/18+, незаконные услуги, азартные игры/ставки/казино, финансовые пирамиды, обнал/отмывание, мошенничество, фишинг, просьбы SMS-кодов/CVV/паролей, угрозы, оскорбления, дискриминацию, спам.",
      "Не отклоняй легальные бытовые услуги только из-за слова массаж. Фразы вроде профессиональный массаж, лечебный массаж, спортивный массаж, без интима допустимы, если нет сексуального контекста, эскорта, 18+, проституции или явных интим-услуг.",
      "Если категория явно не соответствует содержанию, отклоняй сразу с причиной Неверная категория и укажи правильную категорию.",
      "Верни только JSON без markdown.",
      "Схема: {\"decision\":\"approved|rejected|needs_owner_review\",\"reason\":{\"ru\":\"...\",\"kk\":\"...\"},\"riskScore\":0,\"flags\":[\"...\"]}.",
      "В reason нельзя упоминать AI, нейросеть, модель или автоматическую проверку. Пиши как обычная служба модерации приложения.",
      "approved используй только если нарушений нет. rejected используй для явных нарушений, запрещенных товаров/услуг и рискованных неполных публикаций. needs_owner_review используй только если по закону РК ситуация неоднозначна и нельзя безопасно решить автоматически.",
      "Для targetType=message rejected означает, что сообщение должно быть заблокировано.",
      `Данные: ${JSON.stringify({
        targetType: input.targetType ?? "listing",
        title: input.title ?? "",
        description: input.description ?? "",
        categoryId: input.categoryId ?? "",
        price: input.price ?? 0,
        imageCount: (input.images ?? []).length,
        userViolationCount: input.userViolationCount ?? 0,
      })}`,
    ].join("\n");
    const imageParts = await imagePartsFromUrls(input.images ?? []);
    const modelText = await generateModerationText([{ text: prompt }, ...imageParts]);
    return parseAiModerationJson(modelText) ?? fallback;
  } catch (error) {
    console.warn("Vertex AI moderation fallback", error);
    return fallback;
  }
}

async function createModerationCase(params: {
  type: "listing" | "banner" | "message" | "report";
  targetId: string;
  ownerId: string;
  reporterId?: string;
  result: AiModerationResult;
  payload?: FirebaseFirestore.DocumentData;
}) {
  const caseRef = db.collection("moderationCases").doc();
  await caseRef.set({
    id: caseRef.id,
    type: params.type,
    targetId: params.targetId,
    ownerId: params.ownerId,
    reporterId: params.reporterId ?? null,
    status: "open",
    decision: params.result.decision,
    reason: params.result.reason,
    riskScore: params.result.riskScore,
    flags: params.result.flags,
    payload: params.payload ?? {},
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  return caseRef.id;
}

async function notifyOwnersForModeration(caseId: string, type: string, title: string): Promise<void> {
  const owners = await db.collection("users").where("role", "in", ["owner", "admin"]).get();
  await Promise.all(owners.docs.map((doc) => notifyUser(
    doc.id,
    "moderation_required",
    { ru: "Нужна проверка", kk: "Тексеру қажет" },
    { ru: `${title || "Материал"} ожидает решения владельца.`, kk: `${title || "Материал"} иесінің шешімін күтуде.` },
    { caseId, type },
  )));
}

async function registerModerationOutcome(uid: string, result: AiModerationResult): Promise<void> {
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const user = userSnap.data() ?? {};
  if (result.decision !== "rejected") {
    await userRef.set({
      rejectionStreak: 0,
      lastModerationDecision: result.decision,
      updatedAt: timestamp(),
    }, { merge: true });
    return;
  }
  const violationCount = Number(user.violationCount ?? 0) + 1;
  const rejectionStreak = Number(user.rejectionStreak ?? 0) + 1;
  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    violationCount,
    rejectionStreak,
    lastModerationDecision: result.decision,
    lastViolationAt: timestamp(),
    lastViolationReason: result.reason,
    lastViolationFlags: result.flags,
    updatedAt: timestamp(),
  };
  if (rejectionStreak >= 20) {
    updates.status = "banned";
    updates.bannedAt = timestamp();
    updates.bannedReason = {
      ru: "Аккаунт заблокирован: 20 объявлений подряд были отклонены модерацией.",
      kk: "Аккаунт бұғатталды: қатарынан 20 хабарландыру модерациядан өтпеді.",
    };
  }
  await userRef.set(updates, { merge: true });
}

async function assertValidLocation(regionId: string, city: string): Promise<void> {
  const cleanRegionId = cleanText(regionId, 120);
  const cleanCity = cleanText(city, 80);
  const locations = await db.collection("locations").limit(1).get();
  if (locations.empty) {
    return;
  }
  if (!cleanRegionId || !cleanCity) {
    throw new HttpsError("invalid-argument", "location_required");
  }
  const locationSnap = await db.collection("locations").doc(cleanRegionId).get();
  const location = locationSnap.data();
  const cities = Array.isArray(location?.cities) ? location.cities.map((item) => String(item)) : [];
  if (!locationSnap.exists || !cities.includes(cleanCity)) {
    throw new HttpsError("invalid-argument", "location_invalid");
  }
}

async function assertValidCity(city: string): Promise<void> {
  const cleanCity = cleanText(city, 120);
  const locations = await db.collection("locations").limit(1).get();
  if (locations.empty) {
    return;
  }
  if (!cleanCity) {
    throw new HttpsError("invalid-argument", "city_required");
  }
  const snap = await db.collection("locations").get();
  const exists = snap.docs.some((doc) => {
    const cities = Array.isArray(doc.data().cities)
      ? doc.data().cities.map((item: unknown) => String(item))
      : [];
    return cities.includes(cleanCity);
  });
  if (!exists) {
    throw new HttpsError("invalid-argument", "city_invalid");
  }
}

async function assertValidListingCategory(categoryId: string): Promise<void> {
  const cleanCategoryId = cleanText(categoryId, 80);
  if (!cleanCategoryId) {
    throw new HttpsError("invalid-argument", "category_required");
  }
  const categoriesSnap = await db.collection("listingCategories").limit(1).get();
  if (categoriesSnap.empty) {
    return;
  }
  const directSnap = await db.collection("listingCategories").doc(cleanCategoryId).get();
  if (directSnap.exists && directSnap.data()?.isActive !== false) {
    return;
  }
  const allCategories = await db.collection("listingCategories").get();
  const foundSubcategory = allCategories.docs.some((doc) => {
    if (doc.data().isActive === false) {
      return false;
    }
    const subcategories = Array.isArray(doc.data().subcategories)
      ? doc.data().subcategories
      : [];
    return subcategories.some((item: FirebaseFirestore.DocumentData) => String(item?.id ?? "") === cleanCategoryId);
  });
  if (!foundSubcategory) {
    throw new HttpsError("invalid-argument", "category_invalid");
  }
}

async function rootListingCategoryId(categoryId: string): Promise<string> {
  const cleanCategoryId = cleanText(categoryId, 80);
  const directSnap = await db.collection("listingCategories").doc(cleanCategoryId).get();
  if (directSnap.exists) {
    return cleanCategoryId;
  }
  const allCategories = await db.collection("listingCategories").get();
  const parent = allCategories.docs.find((doc) => {
    const subcategories = Array.isArray(doc.data().subcategories)
      ? doc.data().subcategories
      : [];
    return subcategories.some((item: FirebaseFirestore.DocumentData) => String(item?.id ?? "") === cleanCategoryId);
  });
  return parent?.id ?? cleanCategoryId;
}

function categoryMismatchModeration(params: {
  title: string;
  description: string;
  rootCategoryId: string;
}): AiModerationResult | null {
  const raw = `${params.title} ${params.description}`.toLowerCase().replace(/ё/g, "е");
  const text = raw.replace(/[^a-zа-я0-9]+/g, " ");
  const rules = [
    { root: "services", labelRu: "Услуги", labelKk: "Қызметтер", words: ["массаж", "маникюр", "педикюр", "ресниц", "бров", "стрижк", "ремонт", "уборк", "доставк", "юрист", "репетитор", "обучен"] },
    { root: "electronics", labelRu: "Электроника", labelKk: "Электроника", words: ["телефон", "смартфон", "samsung", "iphone", "xiaomi", "ноутбук", "компьютер", "планшет", "телевизор"] },
    { root: "transport", labelRu: "Транспорт", labelKk: "Көлік", words: ["авто", "машин", "toyota", "hyundai", "kia", "bmw", "mercedes", "мото", "скутер"] },
    { root: "real_estate", labelRu: "Недвижимость", labelKk: "Жылжымайтын мүлік", words: ["квартир", "дом", "участок", "офис", "комнат", "аренда", "продам жилье"] },
    { root: "jobs", labelRu: "Работа", labelKk: "Жұмыс", words: ["ваканси", "работа", "зарплат", "требуется", "резюме"] },
  ];
  const matched = rules.find((rule) => rule.words.some((word) => text.includes(word)));
  if (!matched || matched.root === params.rootCategoryId) {
    return null;
  }
  return {
    decision: "rejected",
    reason: {
      ru: `Неверная категория: для этого объявления выберите категорию «${matched.labelRu}».`,
      kk: `Қате санат: бұл хабарландыру үшін «${matched.labelKk}» санатын таңдаңыз.`,
    },
    riskScore: 0.3,
    flags: ["category_mismatch"],
    provider: "heuristic",
  };
}

function makeOtpCode(): string {
  return String(randomInt(1000, 10000));
}

async function sendWappiMessage(phone: string, code: string): Promise<string> {
  const token = process.env.WAPPI_TOKEN;
  const profileId = process.env.WAPPI_PROFILE_ID;
  const url = process.env.WAPPI_URL ?? "https://wappi.pro/api/sync/message/send";
  if (!token || !profileId) {
    throw new HttpsError("unavailable", "otp_provider_not_configured");
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": token,
    },
    body: JSON.stringify({
      profile_id: profileId,
      recipient: phone.replace("+", ""),
      body: `PUSHKA: код входа ${code}`,
    }),
  });

  if (!response.ok) {
    throw new HttpsError("unavailable", "wappi_unavailable");
  }

  return "wappi";
}

async function notifyUser(userId: string, type: string, title: LocalizedText, body: LocalizedText, data: Record<string, string> = {}) {
  const userSnap = await db.collection("users").doc(userId).get();
  const user = userSnap.data();
  const language = user?.language === "kk" ? "kk" : "ru";
  const tokens = uniqueStrings(user?.fcmTokens ?? []);

  await db.collection("notifications").add({
    userId,
    type,
    title,
    body,
    isRead: false,
    createdAt: timestamp(),
    data,
  });

  if (tokens.length === 0) {
    return;
  }

  const pushResponse = await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title: title[language],
      body: body[language],
    },
    data: {
      type,
      ...data,
    },
  });
  const invalidTokens = pushResponse.responses
    .map((result, index) => {
      const code = result.error?.code ?? "";
      return code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
        ? tokens[index]
        : "";
    })
    .filter((token) => token.length > 0);
  await removeInvalidTokens(invalidTokens);
}

function uniqueStrings(values: unknown[]): string[] {
  return Array.from(
    new Set(
      values
        .filter((value): value is string => typeof value === "string")
        .map((value) => value.trim())
        .filter((value) => value.length > 0),
    ),
  );
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

async function removeInvalidTokens(invalidTokens: string[]): Promise<void> {
  const tokens = uniqueStrings(invalidTokens);
  if (tokens.length === 0) {
    return;
  }

  const userSnaps = await Promise.all(
    chunks(tokens, 10).map((tokenChunk) =>
      db.collection("users")
        .where("fcmTokens", "array-contains-any", tokenChunk)
        .get(),
    ),
  );

  const batch = db.batch();
  for (const snap of userSnaps) {
    for (const doc of snap.docs) {
      const userTokens = uniqueStrings(doc.data().fcmTokens ?? []);
      const staleForUser = userTokens.filter((token) => tokens.includes(token));
      if (staleForUser.length > 0) {
        batch.set(
          doc.ref,
          {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleForUser),
            updatedAt: timestamp(),
          },
          { merge: true },
        );
      }
    }
  }
  await batch.commit();
}

async function notifyAllUsers(title: LocalizedText, body: LocalizedText, data: Record<string, string> = {}) {
  const usersSnap = await db.collection("users").get();
  const tokenEntries: Array<{ token: string; language: "ru" | "kk" }> = [];

  usersSnap.docs.forEach((doc) => {
    const user = doc.data();
    const language = user.language === "kk" ? "kk" : "ru";
    const tokens = uniqueStrings(user.fcmTokens ?? []);

    tokens.forEach((token) => tokenEntries.push({ token, language }));
  });

  for (const userChunk of chunks(usersSnap.docs, 450)) {
    const notificationBatch = db.batch();
    userChunk.forEach((doc) => {
      notificationBatch.set(db.collection("notifications").doc(), {
        userId: doc.id,
        type: "admin_push",
        title,
        body,
        isRead: false,
        createdAt: timestamp(),
        data,
      });
    });
    await notificationBatch.commit();
  }

  const invalidTokens: string[] = [];
  for (const language of ["ru", "kk"] as const) {
    const tokens = uniqueStrings(
      tokenEntries
        .filter((entry) => entry.language === language)
        .map((entry) => entry.token),
    );
    for (const tokenChunk of chunks(tokens, 500)) {
      const response = await messaging.sendEachForMulticast({
        tokens: tokenChunk,
        notification: {
          title: title[language],
          body: body[language],
        },
        data: {
          type: "admin_push",
          titleRu: title.ru,
          titleKk: title.kk,
          bodyRu: body.ru,
          bodyKk: body.kk,
          ...data,
        },
      });
      response.responses.forEach((item, index) => {
        const code = item.error?.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token"
        ) {
          invalidTokens.push(tokenChunk[index]);
        }
      });
    }
  }
  await removeInvalidTokens(invalidTokens);
}

function kassa24AuthHeader(): string {
  const credentials = Buffer.from(`${kassa24Login.value()}:${kassa24Key.value()}`).toString("base64");
  return `Basic ${credentials}`;
}

function kassa24StatusValue(value: unknown): string {
  return String(value ?? "").trim().toLowerCase();
}

function isKassa24Paid(payload: FirebaseFirestore.DocumentData): boolean {
  const rawStatus = payload.status ?? payload.paymentStatus ?? payload.state;
  const status = kassa24StatusValue(rawStatus);
  const numericStatus = Number(rawStatus);
  return ["paid", "success", "succeeded", "approved", "completed", "confirmed"].includes(status)
    || numericStatus === 1
    || payload.success === true
    || payload.paid === true;
}

function isKassa24Failed(payload: FirebaseFirestore.DocumentData): boolean {
  const rawStatus = payload.status ?? payload.paymentStatus ?? payload.state;
  const status = kassa24StatusValue(rawStatus);
  const numericStatus = Number(rawStatus);
  const errCode = kassa24StatusValue(payload.errCode);
  const errMessage = kassa24StatusValue(payload.errMessage);
  return ["failed", "declined", "cancelled", "canceled", "rejected", "expired", "error"].includes(status)
    || (numericStatus === 0 && errCode !== "" && errCode !== "0")
    || errMessage.includes("истек")
    || errMessage.includes("expired")
    || payload.success === false
    || payload.paid === false && status !== "";
}

function kassa24ProviderPaymentId(payload: FirebaseFirestore.DocumentData): string | null {
  return String(
    payload.paymentId
      ?? payload.providerPaymentId
      ?? payload.transactionId
      ?? payload.id
      ?? "",
  ) || null;
}

function kassa24PaymentUrl(payload: FirebaseFirestore.DocumentData): string {
  const direct = String(
    payload.paymentUrl
      ?? payload.redirectUrl
      ?? payload.redirect_url
      ?? payload.payUrl
      ?? payload.pay_url
      ?? payload.url
      ?? payload.invoiceUrl
      ?? payload.invoice_url
      ?? payload.formUrl
      ?? payload.form_url
      ?? payload.data?.paymentUrl
      ?? payload.data?.redirectUrl
      ?? payload.data?.url
      ?? payload.result?.paymentUrl
      ?? payload.result?.redirectUrl
      ?? payload.result?.url
      ?? "",
  );
  if (direct.startsWith("http")) {
    return direct;
  }
  const raw = JSON.stringify(payload);
  const match = raw.match(/https?:\/\/[^"\\\s]+/);
  return match?.[0] ?? "";
}

async function createKassa24Payment(params: {
  paymentId: string;
  userId: string;
  amount: number;
  description: string;
  type: "promotion" | "banner";
  phone?: string;
  saveCard?: boolean;
  cardToken?: string;
  metadata?: Record<string, string>;
}): Promise<Kassa24PaymentResult> {
  const body: FirebaseFirestore.DocumentData = {
    merchantId: kassa24Login.value(),
    orderId: params.paymentId,
    amount: Math.round(params.amount * 100),
    currency: "KZT",
    description: params.description,
    callbackUrl: `${kassa24CallbackBaseUrl}?secret=${encodeURIComponent(kassa24WebhookSecret.value())}`,
    tokenization: params.saveCard === true,
    metadata: {
      paymentId: params.paymentId,
      userId: params.userId,
      type: params.type,
      ...(params.metadata ?? {}),
    },
  };

  if (params.phone) {
    body.customerData = {
      phone: normalizePhone(params.phone).replace("+", ""),
      ...(params.cardToken ? { cardToken: params.cardToken } : {}),
    };
  }

  const response = await fetch(kassa24ApiUrl, {
    method: "POST",
    headers: {
      "Authorization": kassa24AuthHeader(),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  let data: FirebaseFirestore.DocumentData = {};
  try {
    data = JSON.parse(text) as FirebaseFirestore.DocumentData;
  } catch {
    data = { rawBody: text };
  }

  if (!response.ok) {
    await db.collection("payments").doc(params.paymentId).set({
      status: "failed",
      providerError: data,
      updatedAt: timestamp(),
    }, { merge: true });
    throw new HttpsError("unavailable", "kassa24_payment_create_failed");
  }

  return {
    providerPaymentId: kassa24ProviderPaymentId(data) ?? undefined,
    paymentUrl: kassa24PaymentUrl(data),
    raw: data,
  };
}

async function getKassa24PaymentStatus(orderId: string): Promise<FirebaseFirestore.DocumentData | null> {
  const id = String(orderId).trim();
  if (!id) {
    return null;
  }

  const url = new URL(kassa24StatusApiUrl);
  url.searchParams.set("orderid", id);

  const response = await fetch(url, {
    method: "GET",
    headers: {
      "Authorization": kassa24AuthHeader(),
      "Accept": "application/json",
    },
  });

  const text = await response.text();
  let data: FirebaseFirestore.DocumentData = {};
  try {
    data = JSON.parse(text) as FirebaseFirestore.DocumentData;
  } catch {
    data = { rawBody: text };
  }

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new HttpsError("unavailable", "kassa24_status_check_failed", {
      orderId: id,
      statusCode: response.status,
      response: data,
    });
  }

  return {
    ...data,
    statusCheckedByOrderId: id,
    statusCheckedAt: admin.firestore.Timestamp.now(),
  };
}

async function syncKassa24PaymentFromApi(paymentId: string, payment: FirebaseFirestore.DocumentData): Promise<FirebaseFirestore.DocumentData | null> {
  const candidateIds = new Set<string>();
  candidateIds.add(paymentId);
  if (payment.providerPaymentId) {
    candidateIds.add(String(payment.providerPaymentId));
  }

  let lastPayload: FirebaseFirestore.DocumentData | null = null;
  for (const candidateId of candidateIds) {
    const payload = await getKassa24PaymentStatus(candidateId);
    if (!payload) {
      continue;
    }
    lastPayload = payload;
    await db.collection("payments").doc(paymentId).set({
      providerPayload: payload,
      providerPaymentId: kassa24ProviderPaymentId(payload) ?? payment.providerPaymentId ?? null,
      statusCheckedByOrderId: candidateId,
      updatedAt: timestamp(),
    }, { merge: true });
    if (isKassa24Paid(payload)) {
      await handlePaidPayment(paymentId, payload);
      return payload;
    }
    if (isKassa24Failed(payload)) {
      await db.collection("payments").doc(paymentId).set({
        status: "failed",
        providerPayload: payload,
        updatedAt: timestamp(),
      }, { merge: true });
      return payload;
    }
  }

  return lastPayload;
}

async function activatePromotion(payment: FirebaseFirestore.DocumentData) {
  if (!payment.listingId) {
    return;
  }
  const paymentId = String(payment.paymentId ?? payment.id ?? "");
  const durationDays = Number(payment.durationDays ?? 7);
  const until = admin.firestore.Timestamp.fromMillis(Date.now() + durationDays * 24 * 60 * 60 * 1000);
  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    paymentStatus: "paid",
    promotedUntil: until,
    updatedAt: timestamp(),
  };
  const planId = String(payment.planId ?? "");
  if (planId.includes("boost")) {
    updates.boostedAt = timestamp();
    updates.boostUntil = until;
  }
  if (planId.includes("top")) {
    updates.topUntil = until;
  }
  if (planId.includes("vip")) {
    updates.vipUntil = until;
  }
  await db.collection("listings").doc(payment.listingId).set(updates, { merge: true });
  await db.collection("promotionPurchases").doc(paymentId).set({
    id: paymentId,
    userId: payment.userId,
    listingId: payment.listingId,
    planId: payment.planId,
    paymentId,
    status: "active",
    activeUntil: until,
    updatedAt: timestamp(),
  }, { merge: true });
  await notifyUser(
    payment.userId,
    "promotion_active",
    { ru: "Продвижение активно", kk: "Жылжыту белсенді" },
    { ru: "Платное продвижение объявления активировано.", kk: "Хабарландыруды ақылы жылжыту іске қосылды." },
    { listingId: payment.listingId },
  );
}

async function activateBannerPlacement(payment: FirebaseFirestore.DocumentData) {
  if (!payment.bannerId) {
    return;
  }
  const durationDays = Number(payment.durationDays ?? 7);
  const until = admin.firestore.Timestamp.fromMillis(Date.now() + durationDays * 24 * 60 * 60 * 1000);
  await db.collection("bannerAds").doc(payment.bannerId).set({
    status: "active",
    paymentStatus: "paid",
    activeUntil: until,
    updatedAt: timestamp(),
  }, { merge: true });
  await notifyUser(
    payment.userId,
    "banner_active",
    { ru: "Баннер опубликован", kk: "Баннер жарияланды" },
    { ru: "Оплата прошла, баннер появился на главной.", kk: "Төлем өтті, баннер басты бетте көрсетіледі." },
    { bannerId: payment.bannerId },
  );
}

async function handlePaidPayment(paymentId: string, payload: FirebaseFirestore.DocumentData) {
  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) {
    throw new HttpsError("not-found", "payment_not_found");
  }
  const payment = paymentSnap.data()!;
  await paymentRef.update({
    status: "paid",
    providerPaymentId: kassa24ProviderPaymentId(payload) ?? payment.providerPaymentId ?? null,
    providerPayload: payload,
    paidAt: timestamp(),
    updatedAt: timestamp(),
  });
  if (payment.type === "promotion") {
    await activatePromotion({ ...payment, id: paymentId, paymentId });
  }
  if (payment.type === "banner") {
    await activateBannerPlacement({ ...payment, id: paymentId, paymentId });
  }
}

// Temporary access is bound to a random installation credential, never to phone
// ownership. Displaying a code must not allow claiming an existing phone account.
function deviceAccessUid(credential: unknown): string {
  if (typeof credential !== "string" || !/^[a-f0-9]{64}$/.test(credential)) {
    throw new HttpsError("invalid-argument", "device_credential_required");
  }
  return `device_${createHash("sha256").update(credential).digest("hex")}`;
}

type DeviceAccessInput = RequestOtpInput & { deviceCredential: string; code?: string };
const storeReviewPhone = "+77000000099";
const storeReviewUid = "store_review_user";

export const requestDeviceAccessCode = onCall<DeviceAccessInput>(async (request) => {
  const uid = deviceAccessUid(request.data.deviceCredential);
  const phone = normalizePhone(request.data.phone ?? "");
  if (!/^\+7\d{10}$/.test(phone) || phone === adminPhone) {
    throw new HttpsError("invalid-argument", "invalid_phone");
  }
  const code = makeOtpCode();
  const review = phone === storeReviewPhone;
  const accessUid = review ? storeReviewUid : uid;
  const reviewConfig = review ? (await db.doc("storeReviewAccess/config").get()).data() : null;
  if (review && !reviewConfig?.codeHash) throw new HttpsError("unavailable", "review_access_unavailable");
  const ref = db.collection("deviceAccessRequests").doc(uid);
  await db.runTransaction(async (tx) => {
    const [challenge, user, deletion] = await Promise.all([
      tx.get(ref), tx.get(db.collection("users").doc(accessUid)),
      tx.get(db.collection("accountDeletionRequests").doc(accessUid)),
    ]);
    if (deletion.exists) throw new HttpsError("failed-precondition", "account_deletion_pending");
    if (user.exists) {
      assertUserAllowed(user.data()!);
      if (user.data()?.phone !== phone) throw new HttpsError("failed-precondition", "use_original_phone");
    }
    const requestedAt = challenge.data()?.createdAt?.toMillis?.() ?? 0;
    if (Date.now() - requestedAt < 15000) throw new HttpsError("resource-exhausted", "wait_before_retry");
    tx.set(ref, {
      phone, codeHash: review ? reviewConfig!.codeHash : createHash("sha256").update(code).digest("hex"), attempts: 0,
      createdAt: timestamp(), expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 300000),
      language: request.data.language === "kk" ? "kk" : "ru",
    });
  });
  return { code: review ? null : code, phone, phoneVerified: false,
    transport: review ? "store_review_credentials" : "on_screen_device_access" };
});

export const verifyDeviceAccessCode = onCall<DeviceAccessInput>(async (request) => {
  const uid = deviceAccessUid(request.data.deviceCredential);
  const phone = normalizePhone(request.data.phone ?? "");
  const code = String(request.data.code ?? "").trim();
  const review = phone === storeReviewPhone;
  const accessUid = review ? storeReviewUid : uid;
  const ref = db.collection("deviceAccessRequests").doc(uid);
  const userRef = db.collection("users").doc(accessUid);
  const reviewAttemptsRef = db.doc("storeReviewAccess/attempts");
  const result = await db.runTransaction(async (tx) => {
    const [challenge, user, deletion, attempts] = await Promise.all([
      tx.get(ref), tx.get(userRef), tx.get(db.collection("accountDeletionRequests").doc(accessUid)),
      tx.get(reviewAttemptsRef),
    ]);
    const data = challenge.data();
    if (deletion.exists) throw new HttpsError("failed-precondition", "account_deletion_pending");
    if (!data || data.phone !== phone || data.expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("failed-precondition", "request_new_code");
    }
    if (data.attempts >= 5) throw new HttpsError("resource-exhausted", "otp_attempts_exceeded");
    const reviewCount = Date.now() - (attempts.data()?.windowStartedAt?.toMillis?.() ?? 0) < 900000
      ? Number(attempts.data()?.count ?? 0) : 0;
    if (review && reviewCount >= 5) throw new HttpsError("resource-exhausted", "otp_attempts_exceeded");
    if (createHash("sha256").update(code).digest("hex") !== data.codeHash) {
      tx.update(ref, { attempts: admin.firestore.FieldValue.increment(1) });
      if (review) tx.set(reviewAttemptsRef, {
        count: reviewCount + 1,
        windowStartedAt: reviewCount ? attempts.data()!.windowStartedAt : timestamp(),
      });
      return null;
    }
    if (user.exists) assertUserAllowed(user.data()!);
    const profile = user.data() ?? {
      id: accessUid, phone, phoneVerified: false, authMode: review ? "store_review" : "device_access", role: "user",
      name: review ? "Store Review" : "Пользователь", city: review ? "Алматы" : "", language: data.language,
      email: "", photoUrl: "", createdAt: timestamp(),
    };
    tx.set(userRef, { ...profile, updatedAt: timestamp() });
    tx.delete(ref);
    if (review) tx.delete(reviewAttemptsRef);
    return { uid: accessUid, role: "user", name: profile.name, phone, city: profile.city,
      language: profile.language, isNewUser: !user.exists && !review, phoneVerified: false };
  });
  if (!result) throw new HttpsError("permission-denied", "otp_invalid");
  return { ...result, customToken: await admin.auth().createCustomToken(accessUid, { role: "user" }) };
});

// Production OTP stays unavailable until a real provider and its secret bindings
// are configured. Demo builds authenticate locally and never call this endpoint.
export const requestWhatsAppOtp = onCall<RequestOtpInput>(async (request) => {
  const phone = normalizePhone(request.data.phone ?? "");
  if (!phone || phone.length < 11) {
    throw new HttpsError("invalid-argument", "invalid_phone");
  }
  if ((await db.collection("accountDeletionRequests").doc(uidFromPhone(phone)).get()).exists) {
    throw new HttpsError("failed-precondition", "account_deletion_pending");
  }

  const code = makeOtpCode();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 5 * 60 * 1000);
  const transport = await sendWappiMessage(phone, code);

  await db.collection("wappiOtpRequests").doc(phone).set({
    phone,
    code,
    attempts: 0,
    expiresAt,
    transport,
    name: request.data.name ?? null,
    city: request.data.city ?? null,
    language: request.data.language ?? "ru",
    acceptedLegalVersion: request.data.acceptedLegalVersion ?? null,
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });

  return {
    phone,
    code: null,
    debug: false,
    transport,
  };
});

export const verifyWhatsAppOtp = onCall<VerifyOtpInput>(async (request) => {
  const phone = normalizePhone(request.data.phone ?? "");
  const code = String(request.data.code ?? "").trim();
  const otpRef = db.collection("wappiOtpRequests").doc(phone);
  const otpSnap = await otpRef.get();
  const otp = otpSnap.data();
  if (!otpSnap.exists || !otp) {
    throw new HttpsError("not-found", "otp_not_found");
  }

  const expiresAt = otp.expiresAt?.toDate?.() as Date | undefined;
  if (!expiresAt || expiresAt.getTime() <= Date.now()) {
    throw new HttpsError("deadline-exceeded", "otp_expired");
  }
  if ((otp.attempts ?? 0) >= 5) {
    throw new HttpsError("resource-exhausted", "otp_attempts_exceeded");
  }
  if (otp.code !== code) {
    await otpRef.update({ attempts: admin.firestore.FieldValue.increment(1), updatedAt: timestamp() });
    throw new HttpsError("permission-denied", "otp_invalid");
  }

  const uid = uidFromPhone(phone);
  if ((await db.collection("accountDeletionRequests").doc(uid).get()).exists) {
    throw new HttpsError("failed-precondition", "account_deletion_pending");
  }
  const role = phone === adminPhone ? "owner" : "user";
  const userRef = db.collection("users").doc(uid);
  const existingUserSnap = await userRef.get();
  const userPayload: FirebaseFirestore.DocumentData = {
    id: uid,
    name: otp.name ?? (role === "owner" ? "Владелец" : "Пользователь"),
    phone,
    city: otp.city ?? "",
    language: otp.language ?? "ru",
    role,
    acceptedLegalVersion: otp.acceptedLegalVersion ?? null,
    updatedAt: timestamp(),
  };
  if (!existingUserSnap.exists) {
    Object.assign(userPayload, {
      email: "",
      photoUrl: "",
      createdAt: timestamp(),
    });
  }
  await userRef.set(userPayload, { merge: true });
  await otpRef.delete();

  return {
    customToken: await admin.auth().createCustomToken(uid, { role }),
    uid,
    role,
    name: userPayload.name,
    phone,
    city: userPayload.city,
    language: userPayload.language,
    isNewUser: !existingUserSnap.exists,
  };
});

export const completeUserProfile = onCall<CompleteUserProfileInput>(async (request) => {
  const uid = assertSignedIn(request);
  await getUser(uid);
  const name = cleanText(request.data.name, 120);
  const city = cleanText(request.data.city, 120);
  if (!name || !city) {
    throw new HttpsError("invalid-argument", "profile_required");
  }
  await assertValidCity(city);
  await db.collection("users").doc(uid).set({
    name,
    city,
    updatedAt: timestamp(),
    profileCompletedAt: timestamp(),
  }, { merge: true });
  return { ok: true, name, city };
});

export const updateUserLanguage = onCall<UpdateUserLanguageInput>(async (request) => {
  const uid = assertSignedIn(request);
  await getUser(uid);
  const language = request.data.language;
  if (language !== "ru" && language !== "kk") {
    throw new HttpsError("invalid-argument", "language_invalid");
  }
  await db.collection("users").doc(uid).set({
    language,
    updatedAt: timestamp(),
  }, { merge: true });
  return { ok: true, language };
});

export const registerFcmToken = onCall<RegisterFcmTokenInput>(async (request) => {
  const uid = assertSignedIn(request);
  await getUser(uid);
  const token = cleanText(request.data.token, 500);
  if (!token || token.length < 20) {
    throw new HttpsError("invalid-argument", "fcm_token_invalid");
  }
  await db.collection("users").doc(uid).set({
    fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
    updatedAt: timestamp(),
  }, { merge: true });
  return { ok: true };
});

export const markNotificationsRead = onCall<MarkNotificationsReadInput>(async (request) => {
  const uid = assertSignedIn(request);
  const requestedIds = Array.isArray(request.data.notificationIds)
    ? request.data.notificationIds.map((item) => cleanText(item, 120)).filter(Boolean).slice(0, 100)
    : [];
  const snap = requestedIds.length > 0
    ? await db.collection("notifications").where(admin.firestore.FieldPath.documentId(), "in", requestedIds.slice(0, 30)).get()
    : await db.collection("notifications").where("userId", "==", uid).where("isRead", "==", false).limit(100).get();
  const batch = db.batch();
  snap.docs.forEach((doc) => {
    if (doc.data().userId === uid) {
      batch.set(doc.ref, { isRead: true, readAt: timestamp() }, { merge: true });
    }
  });
  await batch.commit();
  return { ok: true, count: snap.size };
});

export const syncPaymentStatus = onCall<SyncPaymentStatusInput>({ secrets: [kassa24Login, kassa24Key] }, async (request) => {
  const uid = assertSignedIn(request);
  const paymentId = String(request.data.paymentId ?? "");
  if (!paymentId) {
    throw new HttpsError("invalid-argument", "payment_id_required");
  }
  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  if (!paymentSnap.exists) {
    throw new HttpsError("not-found", "payment_not_found");
  }
  const payment = paymentSnap.data()!;
  if (payment.userId !== uid) {
    throw new HttpsError("permission-denied", "payment_forbidden");
  }
  const payload = payment.providerPayload ?? {};
  if (payment.status !== "paid" && isKassa24Paid(payload)) {
    await handlePaidPayment(paymentId, payload);
  }
  if (payment.status !== "paid" && payment.provider === "kassa24") {
    await syncKassa24PaymentFromApi(paymentId, payment);
  }
  const updatedSnap = await paymentRef.get();
  const updatedPayment = updatedSnap.data() ?? payment;
  return {
    status: updatedPayment.status ?? "pending",
  };
});

export const createListing = onCall<CreateListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const title = cleanText(request.data.title, 120);
  const description = cleanText(request.data.description);
  const categoryId = cleanText(request.data.categoryId, 80);
  const regionId = cleanText(request.data.regionId, 120);
  const city = cleanText(request.data.city, 80);
  const settings = await getRuntimeAppSettings();
  const images = Array.isArray(request.data.images) ? request.data.images.map((item) => cleanText(item, 1000)).filter(Boolean).slice(0, settings.maxListingPhotos) : [];
  if (!title || !description || !categoryId || !city) {
    throw new HttpsError("invalid-argument", "listing_required_fields");
  }
  assertStorageUrlsForUser(images, uid, ["listingImages"]);
  await assertValidListingCategory(categoryId);
  await assertValidLocation(regionId, city);
  const rootCategoryId = await rootListingCategoryId(categoryId);
  const canSkipModeration = request.data.skipModeration === true && (user.role === "owner" || user.role === "admin");
  const mismatchResult = canSkipModeration ? null : categoryMismatchModeration({ title, description, rootCategoryId });
  const result: AiModerationResult = canSkipModeration ? {
    decision: "approved",
    reason: {
      ru: "Объявление опубликовано владельцем приложения.",
      kk: "Хабарландыру қолданба иесі арқылы жарияланды.",
    },
    riskScore: 0,
    flags: [],
    provider: "owner",
  } : mismatchResult ?? applyModerationSettings(await moderateContent({
    targetType: "listing",
    title,
    description,
    categoryId,
    price: Number(request.data.price ?? 0),
    images,
    userViolationCount: Number(user.violationCount ?? 0),
  }), settings, "listing");
  const listingRef = request.data.id ? db.collection("listings").doc(cleanText(request.data.id, 120)) : db.collection("listings").doc();
  const status = moderationStatus(result.decision, "listing");
  if (!canSkipModeration) {
    await registerModerationOutcome(uid, result);
  }
  await listingRef.set({
    id: listingRef.id,
    ownerId: uid,
    ownerName: user.name ?? "Пользователь",
    sellerType: cleanText(request.data.sellerType ?? user.sellerType ?? user.accountType ?? "private", 40) === "business" ? "business" : "private",
    phone: cleanText(request.data.phone ?? user.phone ?? "", 40),
    title,
    description,
    categoryId,
    regionId,
    price: Math.max(0, Number(request.data.price ?? 0)),
    negotiable: request.data.negotiable === true,
    condition: cleanText(request.data.condition, 40) || "used",
    city,
    district: cleanText(request.data.district, 80),
    address: cleanText(request.data.address, 160),
    images,
    attributes: request.data.attributes ?? {},
    status,
    moderation: result,
    rejectionReasonRu: status === "rejected" ? result.reason.ru : "",
    rejectionReasonKk: status === "rejected" ? result.reason.kk : "",
    viewCount: 0,
    favoriteCount: 0,
    createdAt: timestamp(),
    updatedAt: timestamp(),
    publishedAt: status === "active" ? timestamp() : null,
  }, { merge: true });
  let moderationCaseId: string | null = null;
  if (result.decision === "needs_owner_review") {
    moderationCaseId = await createModerationCase({ type: "listing", targetId: listingRef.id, ownerId: uid, result, payload: { title, categoryId } });
    await notifyOwnersForModeration(moderationCaseId, "listing", title);
  }
  await notifyUser(
    uid,
    status === "active" ? "listing_approved" : status === "rejected" ? "listing_rejected" : "listing_owner_review",
    status === "active"
      ? { ru: "Объявление опубликовано", kk: "Хабарландыру жарияланды" }
      : status === "rejected"
        ? { ru: "Объявление отклонено", kk: "Хабарландыру қабылданбады" }
        : { ru: "Объявление на проверке", kk: "Хабарландыру тексерілуде" },
    status === "active"
      ? { ru: "Ваше объявление уже доступно пользователям.", kk: "Хабарландыруыңыз пайдаланушыларға қолжетімді." }
      : status === "rejected"
        ? result.reason
        : { ru: "Мы проверим объявление и сообщим о результате.", kk: "Біз хабарландыруды тексеріп, нәтижесін хабарлаймыз." },
    { listingId: listingRef.id },
  );
  return { listingId: listingRef.id, status, moderation: result, moderationCaseId };
});

export const updateListing = onCall<UpdateListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  const isAdminEdit = user.role === "admin" || user.role === "owner";
  if (listing.ownerId !== uid && !isAdminEdit) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  const settings = await getRuntimeAppSettings();
  const images = Array.isArray(request.data.images) ? request.data.images.map((item) => cleanText(item, 1000)).filter(Boolean).slice(0, settings.maxListingPhotos) : [];
  const existingImages = Array.isArray(listing.images) ? listing.images.map((item: unknown) => String(item)) : [];
  assertStorageUrlsForUser(
    images.filter((url) => !existingImages.includes(url)),
    uid,
    ["listingImages"],
  );
  const categoryId = cleanText(request.data.categoryId, 80);
  const title = cleanText(request.data.title, 120);
  const description = cleanText(request.data.description);
  await assertValidListingCategory(categoryId);
  await assertValidLocation(cleanText(request.data.regionId, 120), cleanText(request.data.city, 80));
  const rootCategoryId = await rootListingCategoryId(categoryId);
  const mismatchResult = categoryMismatchModeration({ title, description, rootCategoryId });
  const result = mismatchResult ?? applyModerationSettings(await moderateContent({
    targetType: "listing",
    title,
    description,
    categoryId,
    price: Number(request.data.price ?? 0),
    images,
  }), settings, "listing");
  const status = moderationStatus(result.decision, "listing");
  await registerModerationOutcome(uid, result);
  await listingRef.update({
    title,
    description,
    categoryId,
    regionId: cleanText(request.data.regionId, 120),
    price: Math.max(0, Number(request.data.price ?? 0)),
    negotiable: request.data.negotiable === true,
    condition: cleanText(request.data.condition, 40),
    city: cleanText(request.data.city, 80),
    district: cleanText(request.data.district, 80),
    address: cleanText(request.data.address, 160),
    phone: cleanText(request.data.phone, 40),
    sellerType: cleanText(request.data.sellerType ?? listing.sellerType ?? user.sellerType ?? user.accountType ?? "private", 40) === "business" ? "business" : "private",
    images,
    attributes: request.data.attributes ?? {},
    status,
    moderation: result,
    rejectionReasonRu: status === "rejected" ? result.reason.ru : "",
    rejectionReasonKk: status === "rejected" ? result.reason.kk : "",
    updatedAt: timestamp(),
    publishedAt: status === "active" ? timestamp() : null,
  });
  if (result.decision === "needs_owner_review") {
    const caseId = await createModerationCase({ type: "listing", targetId: listingId, ownerId: uid, result, payload: { title: request.data.title } });
    await notifyOwnersForModeration(caseId, "listing", cleanText(request.data.title, 120));
  }
  if (isAdminEdit && listing.ownerId !== uid) {
    await writeOwnerAudit(uid, "listing_edit", "listing", listingId, {
      ownerId: String(listing.ownerId ?? ""),
      status,
    });
  }
  return { listingId, status, moderation: result };
});

export const submitListingForModeration = onCall<SubmitListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  if (listing.ownerId !== uid) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  const settings = await getRuntimeAppSettings();
  const result = applyModerationSettings(
    await moderateContent({ ...listing, targetType: "listing", userViolationCount: Number(user.violationCount ?? 0) }),
    settings,
    "listing",
  );
  const status = moderationStatus(result.decision, "listing");
  await registerModerationOutcome(uid, result);
  await listingRef.update({
    status,
    moderation: result,
    rejectionReasonRu: status === "rejected" ? result.reason.ru : "",
    rejectionReasonKk: status === "rejected" ? result.reason.kk : "",
    updatedAt: timestamp(),
    publishedAt: status === "active" ? timestamp() : listing.publishedAt ?? null,
  });
  if (result.decision === "needs_owner_review") {
    const caseId = await createModerationCase({ type: "listing", targetId: listingId, ownerId: uid, result, payload: { title: listing.title } });
    await notifyOwnersForModeration(caseId, "listing", cleanText(listing.title, 120));
  }
  return { listingId, status, moderation: result };
});

export const archiveListing = onCall<ArchiveListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const listingId = cleanText(request.data.listingId, 120);
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  if (listing.ownerId !== uid) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  await listingRef.update({
    status: "archived",
    archivedAt: timestamp(),
    updatedAt: timestamp(),
  });
  return { listingId, status: "archived" };
});

export const restoreListing = onCall<RestoreListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const listingId = cleanText(request.data.listingId, 120);
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  if (listing.ownerId !== uid) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  const restoreUntil = listing.restoreUntil?.toDate?.() as Date | undefined;
  if (listing.status !== "archived" || !restoreUntil || restoreUntil.getTime() <= Date.now()) {
    throw new HttpsError("failed-precondition", "restore_expired");
  }
  await listingRef.set({
    status: "active",
    archivedAt: null,
    restoreUntil: null,
    archivedReason: null,
    updatedAt: timestamp(),
    publishedAt: timestamp(),
  }, { merge: true });
  return { listingId, status: "active" };
});

export const trackListingCall = onCall<TrackListingCallInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  const listingSnap = await db.collection("listings").doc(listingId).get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  if (listing.status !== "active") {
    throw new HttpsError("failed-precondition", "listing_not_active");
  }
  if (listing.ownerId === uid || listing.sellerType === "business") {
    return { skipped: true };
  }
  const callRef = db.collection("listingCallChecks").doc();
  await callRef.set({
    id: callRef.id,
    listingId,
    listingOwnerId: listing.ownerId,
    callerId: uid,
    callerPhone: user.phone ?? "",
    status: "waiting_owner_answer",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  await notifyUser(
    listing.ownerId,
    "listing_call_check",
    { ru: "Вам звонили по объявлению", kk: "Хабарландыру бойынша қоңырау болды" },
    {
      ru: `Покупатель звонил по объявлению "${cleanText(listing.title, 80)}". Договорились?`,
      kk: `"${cleanText(listing.title, 80)}" хабарландыруы бойынша қоңырау болды. Келістіңіздер ме?`,
    },
    { listingId, callCheckId: callRef.id, action: "listing_call_check" },
  );
  return { callCheckId: callRef.id, notified: true };
});

export const resolveListingCall = onCall<ResolveListingCallInput>(async (request) => {
  const uid = assertSignedIn(request);
  const listingId = cleanText(request.data.listingId, 120);
  const notificationId = cleanText(request.data.notificationId ?? "", 120);
  const agreed = request.data.agreed === true;
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  if (listing.ownerId !== uid) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  if (listing.sellerType === "business") {
    throw new HttpsError("failed-precondition", "business_listing_skip");
  }
  if (agreed) {
    await listingRef.set({
      status: "archived",
      archivedAt: timestamp(),
      archivedReason: "call_agreed",
      restoreUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
      updatedAt: timestamp(),
    }, { merge: true });
  }
  if (notificationId) {
    await db.collection("notifications").doc(notificationId).set({
      isRead: true,
      resolved: true,
      resolvedAt: timestamp(),
      answer: agreed ? "agreed" : "not_agreed",
      updatedAt: timestamp(),
    }, { merge: true });
  }
  return { listingId, status: agreed ? "archived" : "active", restoreHours: agreed ? 24 : 0 };
});

export const createBannerAd = onCall<CreateBannerAdInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const title = cleanText(request.data.title, 100);
  const caption = cleanText(request.data.caption, 180);
  const imageUrl = cleanText(request.data.imageUrl, 1000);
  if (!title || !caption || !imageUrl) {
    throw new HttpsError("invalid-argument", "banner_required_fields");
  }
  assertStorageUrlForUser(imageUrl, uid, ["bannerAds"]);
  const settings = await getRuntimeAppSettings();
  const result = applyModerationSettings(
    await moderateContent({ targetType: "banner", title, description: caption, images: [imageUrl], userViolationCount: Number(user.violationCount ?? 0) }),
    settings,
    "banner",
  );
  const bannerRef = request.data.id ? db.collection("bannerAds").doc(cleanText(request.data.id, 120)) : db.collection("bannerAds").doc();
  const status = moderationStatus(result.decision, "banner");
  await registerModerationOutcome(uid, result);
  await bannerRef.set({
    id: bannerRef.id,
    ownerId: uid,
    ownerName: user.name ?? "",
    title,
    caption,
    imageUrl,
    targetUrl: cleanText(request.data.targetUrl, 1000),
    status,
    paymentStatus: status === "pending_payment" ? "pending" : null,
    moderation: result,
    rejectionReasonRu: status === "rejected" ? result.reason.ru : "",
    rejectionReasonKk: status === "rejected" ? result.reason.kk : "",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  }, { merge: true });
  if (result.decision === "needs_owner_review") {
    const caseId = await createModerationCase({ type: "banner", targetId: bannerRef.id, ownerId: uid, result, payload: { title } });
    await notifyOwnersForModeration(caseId, "banner", title);
  }
  return { bannerId: bannerRef.id, status, moderation: result };
});

async function assertNotBlocked(a: string, b: string): Promise<void> {
  if (!b || a === b) return;
  const refs = [db.doc(`users/${a}/blockedUsers/${b}`), db.doc(`users/${b}/blockedUsers/${a}`)];
  if ((await db.getAll(...refs)).some((snap) => snap.exists)) {
    throw new HttpsError("permission-denied", "user_blocked");
  }
}

export const blockMarketplaceUser = onCall<{ userId: string; blocked: boolean }>(async (request) => {
  const uid = assertSignedIn(request);
  await getUser(uid);
  const target = cleanText(request.data.userId, 128);
  if (!target || target === uid || target.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid_user");
  }
  const ref = db.doc(`users/${uid}/blockedUsers/${target}`);
  if (request.data.blocked === false) await ref.delete();
  else await ref.set({ createdAt: timestamp() });
  return { ok: true };
});

export const getBlockedMarketplaceUsers = onCall(async (request) => {
  const uid = assertSignedIn(request);
  await getUser(uid);
  return { userIds: (await db.collection(`users/${uid}/blockedUsers`).get()).docs.map((doc) => doc.id) };
});

export const createChatRoom = onCall<CreateChatRoomInput>(async (request) => {
  try {
    const uid = assertSignedIn(request);
    const user = await getUser(uid);
    assertUserAllowed(user);
    const listingId = cleanText(request.data.listingId, 120);
    const listingSnap = await db.collection("listings").doc(listingId).get();
    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing || listing.status !== "active") {
      throw new HttpsError("not-found", "listing_not_found");
    }
    const sellerId = String(listing.ownerId ?? "");
    await assertNotBlocked(uid, sellerId);
    if (!sellerId) {
      throw new HttpsError("failed-precondition", "seller_not_found");
    }
    const chatId = [listingId, uid, sellerId].sort().join("_").slice(0, 500);
    await db.collection("chatRooms").doc(chatId).set({
      id: chatId,
      listingId,
      listingTitle: listing.title ?? "",
      sellerId,
      buyerId: uid === sellerId ? "" : uid,
      participants: Array.from(new Set([uid, sellerId])),
      lastMessage: "",
      lastMessageAt: timestamp(),
      createdAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
    return { chatId };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error("createChatRoom failed", error);
    throw new HttpsError("internal", "chat_create_failed");
  }
});

export const sendMessage = onCall<SendMessageInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const chatId = cleanText(request.data.chatId, 500);
  const chatRef = db.collection("chatRooms").doc(chatId);
  const chatSnap = await chatRef.get();
  const chat = chatSnap.data();
  if (!chatSnap.exists || !chat || !Array.isArray(chat.participants) || !chat.participants.includes(uid)) {
    throw new HttpsError("permission-denied", "chat_forbidden");
  }
  for (const participant of chat.participants) await assertNotBlocked(uid, String(participant));
  const text = cleanText(request.data.text, 2000);
  const imageUrl = cleanText(request.data.imageUrl, 1000);
  const fileUrl = cleanText(request.data.fileUrl, 1000);
  const fileName = cleanText(request.data.fileName, 180);
  if (!text && !imageUrl && !fileUrl) {
    throw new HttpsError("invalid-argument", "message_empty");
  }
  assertStorageUrlForUser(imageUrl, uid, ["chatImages"]);
  assertStorageUrlForUser(fileUrl, uid, ["chatFiles"]);
  const settings = await getRuntimeAppSettings();
  const result = applyModerationSettings(await moderateContent({
    targetType: "message",
    title: String(chat.listingTitle ?? ""),
    description: `${text} ${fileName} ${fileUrl}`,
    images: imageUrl ? [imageUrl] : [],
    userViolationCount: Number(user.violationCount ?? 0),
  }), settings, "message");
  const messageRef = chatRef.collection("messages").doc();
  const status = result.decision === "rejected" ? "blocked" : result.decision === "needs_owner_review" ? "owner_review" : "sent";
  await registerModerationOutcome(uid, result);
  await messageRef.set({
    id: messageRef.id,
    chatId,
    senderId: uid,
    text,
    imageUrl,
    fileUrl,
    fileName,
    status,
    hiddenFromUsers: status === "blocked",
    moderation: result,
    createdAt: timestamp(),
  });
  if (status !== "blocked") {
    await chatRef.set({
      lastMessage: text || (imageUrl ? "Фото" : "Файл"),
      lastMessageAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
  }
  if (result.decision === "needs_owner_review") {
    const caseId = await createModerationCase({ type: "message", targetId: `${chatId}/${messageRef.id}`, ownerId: uid, result, payload: { text, imageUrl, fileUrl, fileName } });
    await notifyOwnersForModeration(caseId, "message", String(chat.listingTitle ?? "Сообщение"));
  }
  const recipients = (chat.participants as string[]).filter((item) => item !== uid);
  if (status === "sent") {
    await Promise.all(recipients.map(async (recipientId) => {
      try {
        await notifyUser(
          recipientId,
          "new_message",
          { ru: "Новое сообщение", kk: "Жаңа хабарлама" },
          { ru: text || (imageUrl ? "Фото" : "Файл"), kk: text || (imageUrl ? "Фото" : "Файл") },
          { chatId },
        );
      } catch (error) {
        console.warn("new_message notification failed", error);
      }
    }));
  }
  return { messageId: messageRef.id, status, moderation: result };
});

export const deleteMessage = onCall<DeleteMessageInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const chatId = cleanText(request.data.chatId, 500);
  const messageId = cleanText(request.data.messageId, 120);
  const reason = cleanText(request.data.reason ?? "", 500);
  const role = String(user.role ?? "");
  const isOwnerRole = role === "owner" || role === "admin";
  const chatRef = db.collection("chatRooms").doc(chatId);
  const chatSnap = await chatRef.get();
  const chat = chatSnap.data();
  if (!chatSnap.exists || !chat || !Array.isArray(chat.participants) || (!chat.participants.includes(uid) && !isOwnerRole)) {
    throw new HttpsError("permission-denied", "chat_forbidden");
  }
  const messageRef = chatRef.collection("messages").doc(messageId);
  const messageSnap = await messageRef.get();
  const message = messageSnap.data();
  if (!messageSnap.exists || !message) {
    throw new HttpsError("not-found", "message_not_found");
  }
  if (message.senderId !== uid && !isOwnerRole) {
    throw new HttpsError("permission-denied", "message_delete_forbidden");
  }
  await messageRef.set({
    text: "",
    imageUrl: "",
    fileUrl: "",
    fileName: "",
    deleted: true,
    status: "deleted",
    deleteReason: reason,
    deletedAt: timestamp(),
    deletedBy: uid,
    updatedAt: timestamp(),
  }, { merge: true });
  await chatRef.set({
    lastMessage: "Сообщение удалено",
    updatedAt: timestamp(),
  }, { merge: true });
  if (isOwnerRole) {
    await writeOwnerAudit(uid, "message_delete", "message", `${chatId}/${messageId}`, {
      reason,
      senderId: message.senderId ?? "",
    });
  }
  return { ok: true };
});

export const reportListing = onCall<ReportListingInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  const reason = cleanText(request.data.reason, 1000);
  if (!listingId || !reason) {
    throw new HttpsError("invalid-argument", "report_required_fields");
  }
  const reportRef = db.collection("reports").doc();
  await reportRef.set({
    id: reportRef.id,
    reporterId: uid,
    listingId,
    reason,
    status: "open",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  await createModerationCase({
    type: "report",
    targetId: listingId,
    ownerId: uid,
    reporterId: uid,
    result: {
      decision: "needs_owner_review",
      reason: { ru: "Поступила жалоба пользователя.", kk: "Пайдаланушыдан шағым түсті." },
      riskScore: 0.75,
      flags: ["user_report"],
    },
    payload: { reason },
  });
  return { reportId: reportRef.id, status: "open" };
});

export const reportMessage = onCall<ReportMessageInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const chatId = cleanText(request.data.chatId, 500);
  const messageId = cleanText(request.data.messageId, 160);
  const reason = cleanText(request.data.reason, 1000);
  if (!chatId || !messageId || !reason) {
    throw new HttpsError("invalid-argument", "report_required_fields");
  }
  const chatRef = db.collection("chatRooms").doc(chatId);
  const chatSnap = await chatRef.get();
  const chat = chatSnap.data();
  if (!chatSnap.exists || !chat || !Array.isArray(chat.participants) || !chat.participants.includes(uid)) {
    throw new HttpsError("permission-denied", "chat_forbidden");
  }
  const messageRef = chatRef.collection("messages").doc(messageId);
  const messageSnap = await messageRef.get();
  const message = messageSnap.data();
  if (!messageSnap.exists || !message) {
    throw new HttpsError("not-found", "message_not_found");
  }
  const reportRef = db.collection("reports").doc();
  await reportRef.set({
    id: reportRef.id,
    reporterId: uid,
    chatId,
    messageId,
    reportedUserId: message.senderId ?? "",
    reason,
    type: "message",
    status: "open",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  const caseId = await createModerationCase({
    type: "message",
    targetId: `${chatId}/${messageId}`,
    ownerId: String(message.senderId ?? uid),
    reporterId: uid,
    result: {
      decision: "needs_owner_review",
      reason: { ru: "Поступила жалоба на сообщение.", kk: "Хабарламаға шағым түсті." },
      riskScore: 0.8,
      flags: ["user_report", "message_report"],
    },
    payload: {
      reason,
      text: message.text ?? "",
      imageUrl: message.imageUrl ?? "",
      fileUrl: message.fileUrl ?? "",
      fileName: message.fileName ?? "",
    },
  });
  await notifyOwnersForModeration(caseId, "message", String(chat.listingTitle ?? "Сообщение"));
  return { reportId: reportRef.id, status: "open" };
});

export const trackListingView = onCall<TrackListingViewInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  if (!listingId) {
    throw new HttpsError("invalid-argument", "listing_required");
  }
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  if (!listingSnap.exists || listingSnap.data()?.status !== "active") {
    throw new HttpsError("not-found", "listing_not_found");
  }
  await listingRef.set({
    views: admin.firestore.FieldValue.increment(1),
    updatedAt: timestamp(),
  }, { merge: true });
  await db.collection("listingStats").doc(listingId).set({
    listingId,
    views: admin.firestore.FieldValue.increment(1),
    updatedAt: timestamp(),
  }, { merge: true });
  return { ok: true };
});

export const setListingFavorite = onCall<SetListingFavoriteInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const listingId = cleanText(request.data.listingId, 120);
  const favorite = request.data.favorite === true;
  if (!listingId) {
    throw new HttpsError("invalid-argument", "listing_required");
  }
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  if (!listingSnap.exists || listingSnap.data()?.status !== "active") {
    throw new HttpsError("not-found", "listing_not_found");
  }
  const favoriteRef = db.collection("listingFavorites").doc(uid);
  await db.runTransaction(async (tx) => {
    const favoriteSnap = await tx.get(favoriteRef);
    const data = favoriteSnap.data() ?? {};
    const items = data.items && typeof data.items === "object" ? { ...data.items } : {};
    const hadFavorite = items[listingId] === true;
    if (favorite) {
      items[listingId] = true;
    } else {
      delete items[listingId];
    }
    const delta = favorite && !hadFavorite ? 1 : !favorite && hadFavorite ? -1 : 0;
    tx.set(favoriteRef, {
      userId: uid,
      items,
      updatedAt: timestamp(),
    }, { merge: true });
    if (delta !== 0) {
      tx.set(listingRef, {
        favoriteCount: admin.firestore.FieldValue.increment(delta),
        updatedAt: timestamp(),
      }, { merge: true });
      tx.set(db.collection("listingStats").doc(listingId), {
        listingId,
        favoriteCount: admin.firestore.FieldValue.increment(delta),
        updatedAt: timestamp(),
      }, { merge: true });
    }
  });
  return { ok: true, favorite };
});

export const saveSavedSearch = onCall<SaveSearchInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const searchRef = db.collection("savedSearches").doc(
    cleanText(request.data.id ?? "", 120) || db.collection("savedSearches").doc().id,
  );
  const title = cleanText(request.data.title, 120);
  if (!title) {
    throw new HttpsError("invalid-argument", "title_required");
  }
  await searchRef.set({
    id: searchRef.id,
    userId: uid,
    title,
    query: cleanText(request.data.query ?? "", 120),
    categoryId: cleanText(request.data.categoryId ?? "all", 80),
    subcategoryId: cleanText(request.data.subcategoryId ?? "all", 80),
    city: cleanText(request.data.city ?? "all", 120),
    minPrice: Number(request.data.minPrice ?? 0),
    maxPrice: Number(request.data.maxPrice ?? 100000000),
    condition: cleanText(request.data.condition ?? "all", 40),
    sortMode: cleanText(request.data.sortMode ?? "recommended", 40),
    attributes: request.data.attributes ?? {},
    createdAt: timestamp(),
    updatedAt: timestamp(),
  }, { merge: true });
  return { searchId: searchRef.id };
});

export const deleteSavedSearch = onCall<DeleteSavedSearchInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const searchId = cleanText(request.data.searchId, 120);
  if (!searchId) {
    throw new HttpsError("invalid-argument", "search_required");
  }
  const searchRef = db.collection("savedSearches").doc(searchId);
  const searchSnap = await searchRef.get();
  if (!searchSnap.exists) {
    return { ok: true };
  }
  if (searchSnap.data()?.userId !== uid) {
    throw new HttpsError("permission-denied", "search_forbidden");
  }
  await searchRef.delete();
  return { ok: true };
});

export const createSupportTicket = onCall<CreateSupportTicketInput>(async (request) => {
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  assertUserAllowed(user);
  const subject = cleanText(request.data.subject, 160);
  const message = cleanText(request.data.message, 3000);
  if (!subject || !message) {
    throw new HttpsError("invalid-argument", "support_required");
  }

  const ticketRef = db.collection("supportTickets").doc();
  await ticketRef.set({
    id: ticketRef.id,
    userId: uid,
    userName: user.name ?? "",
    phone: user.phone ?? "",
    subject,
    message,
    status: "open",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });

  const owners = await db.collection("users").where("role", "in", ["owner", "admin"]).get();
  await Promise.all(owners.docs.map((doc) => notifyUser(
    doc.id,
    "support_ticket",
    { ru: "Новое обращение", kk: "Жаңа өтініш" },
    { ru: subject, kk: subject },
    { ticketId: ticketRef.id },
  )));

  return { ticketId: ticketRef.id };
});

function assertPromotionPurchasesEnabled(): void {
  throw new HttpsError("failed-precondition", "promotion_unavailable_in_first_release");
}

export const deleteAccount = onCall(async (request) => {
  const uid = assertSignedIn(request);
  const userRef = db.collection("users").doc(uid);
  const deletionRef = db.collection("accountDeletionRequests").doc(uid);
  await db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    const deletion = await tx.get(deletionRef);
    if (deletion.exists) return;
    if (!user.exists) throw new HttpsError("not-found", "profile_not_found");
    tx.update(userRef, { status: "deleting", updatedAt: timestamp() });
    tx.create(deletionRef, { createdAt: timestamp() });
  });
  return { status: "accepted" };
});

export const processAccountDeletion = onDocumentCreated({
  document: "accountDeletionRequests/{uid}", retry: true,
  maxInstances: 1, concurrency: 1, timeoutSeconds: 540,
}, async (event) => {
  const requestRef = db.collection("accountDeletionRequests").doc(event.params.uid);
  const deletion = await requestRef.get();
  if (!deletion.exists) return;
  // Let requests already in flight reach their default 60-second timeout before
  // cleanup. New reads/writes and sign-ins are blocked by the deletion marker.
  const requestedAt = deletion.data()?.createdAt?.toMillis?.() ?? 0;
  const wait = requestedAt + 70_000 - Date.now();
  if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
  await deleteAccountData(event.params.uid);
  await requestRef.delete();
});

export const purchasePromotion = onCall<PurchasePromotionInput>(async (request) => {
  assertPromotionPurchasesEnabled();
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  const listingId = cleanText(request.data.listingId, 120);
  const planId = cleanText(request.data.planId, 80);
  const listingSnap = await db.collection("listings").doc(listingId).get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing || listing.ownerId !== uid) {
    throw new HttpsError("permission-denied", "listing_forbidden");
  }
  const planSnap = await db.collection("promotionPlans").doc(planId).get();
  const plan = planSnap.data() ?? {};
  if (!planSnap.exists || plan.isActive === false) {
    throw new HttpsError("not-found", "promotion_plan_not_found");
  }
  const paymentRef = db.collection("payments").doc();
  await paymentRef.set({
    id: paymentRef.id,
    userId: uid,
    listingId,
    planId,
    type: "promotion",
    status: "pending",
    amount: Number(plan.price),
    currency: plan.currency ?? "KZT",
    provider: "simulated",
    durationDays: Number(plan.durationDays ?? 7),
    customerPhone: user.phone ?? "",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  await handlePaidPayment(paymentRef.id, {
    status: "paid",
    providerPaymentId: `simulated_${paymentRef.id}`,
    source: "temporary_simulation",
  });
  return { paymentId: paymentRef.id, paymentUrl: "", status: "paid", simulated: true };
});

export const purchaseBannerPlacement = onCall<PurchaseBannerPlacementInput>(async (request) => {
  assertPromotionPurchasesEnabled();
  const uid = assertSignedIn(request);
  const user = await getUser(uid);
  const bannerId = cleanText(request.data.bannerId, 120);
  const planId = cleanText(request.data.planId, 80);
  const bannerSnap = await db.collection("bannerAds").doc(bannerId).get();
  const banner = bannerSnap.data();
  if (!bannerSnap.exists || !banner || banner.ownerId !== uid) {
    throw new HttpsError("permission-denied", "banner_forbidden");
  }
  if (banner.status !== "pending_payment" && banner.status !== "active") {
    throw new HttpsError("failed-precondition", "banner_not_approved");
  }
  const planSnap = await db.collection("bannerPlans").doc(planId).get();
  const plan = planSnap.data() ?? {};
  if (!planSnap.exists || plan.isActive === false) {
    throw new HttpsError("not-found", "banner_plan_not_found");
  }
  const paymentRef = db.collection("payments").doc();
  await paymentRef.set({
    id: paymentRef.id,
    userId: uid,
    bannerId,
    planId,
    type: "banner",
    status: "pending",
    amount: Number(plan.price),
    currency: plan.currency ?? "KZT",
    provider: "simulated",
    durationDays: Number(plan.durationDays ?? 7),
    customerPhone: user.phone ?? "",
    createdAt: timestamp(),
    updatedAt: timestamp(),
  });
  await handlePaidPayment(paymentRef.id, {
    status: "paid",
    providerPaymentId: `simulated_${paymentRef.id}`,
    source: "temporary_simulation",
  });
  return { paymentId: paymentRef.id, paymentUrl: "", status: "paid", simulated: true };
});

export const syncKassa24PaymentStatus = onCall<SyncPaymentStatusInput>({ secrets: [kassa24Login, kassa24Key] }, async (request) => {
  const uid = assertSignedIn(request);
  const paymentId = cleanText(request.data.paymentId, 120);
  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  const payment = paymentSnap.data();
  if (!paymentSnap.exists || !payment) {
    throw new HttpsError("not-found", "payment_not_found");
  }
  if (payment.userId !== uid) {
    throw new HttpsError("permission-denied", "payment_forbidden");
  }
  if (payment.status !== "paid" && payment.provider === "kassa24") {
    await syncKassa24PaymentFromApi(paymentId, payment);
  }
  const updated = (await paymentRef.get()).data() ?? payment;
  return { status: updated.status ?? "pending", type: updated.type ?? "", listingId: updated.listingId ?? null, bannerId: updated.bannerId ?? null };
});

async function runListingModerationSweep(params: {
  limit?: number;
  rejectAll?: boolean;
  actorId?: string;
  source: "schedule" | "owner";
}): Promise<{ checked: number; rejected: number; approved: number }> {
  const settings = await getRuntimeAppSettings();
  const max = Math.max(1, Math.min(500, Math.round(Number(params.limit ?? 200))));
  const snap = await db.collection("listings")
    .where("status", "in", ["active", "owner_review", "moderation"])
    .limit(max)
    .get();

  let checked = 0;
  let rejected = 0;
  let approved = 0;
  for (const doc of snap.docs) {
    const listing = doc.data();
    checked += 1;
    const ownerId = String(listing.ownerId ?? "");
    const user = ownerId ? await getUser(ownerId).catch(() => ({} as FirebaseFirestore.DocumentData)) : {};
    const result = params.rejectAll
      ? {
          decision: "rejected" as const,
          reason: {
            ru: "Объявление снято с публикации после повторной проверки.",
            kk: "Хабарландыру қайта тексеруден кейін жарияланымнан алынды.",
          },
          riskScore: 1,
          flags: ["manual_full_sweep_reject"],
          provider: "owner_sweep",
        }
      : applyModerationSettings(
          await moderateContent({
            targetType: "listing",
            title: String(listing.title ?? ""),
            description: String(listing.description ?? ""),
            categoryId: String(listing.categoryId ?? ""),
            price: Number(listing.price ?? 0),
            images: Array.isArray(listing.images) ? listing.images.map((item: unknown) => String(item)) : [],
            userViolationCount: Number(user.violationCount ?? 0),
          }),
          settings,
          "listing",
        );
    const status = moderationStatus(result.decision, "listing");
    if (status === "rejected") {
      rejected += 1;
      await doc.ref.set({
        status: "rejected",
        moderation: result,
        rejectionReasonRu: result.reason.ru,
        rejectionReasonKk: result.reason.kk,
        sweepSource: params.source,
        sweepRejectedAt: timestamp(),
        updatedAt: timestamp(),
        publishedAt: null,
      }, { merge: true });
      if (ownerId) {
        await notifyUser(
          ownerId,
          "listing_rejected",
          { ru: "Объявление отклонено", kk: "Хабарландыру қабылданбады" },
          result.reason,
          { listingId: doc.id },
        );
      }
    } else {
      approved += 1;
      await doc.ref.set({
        moderation: result,
        lastModerationSweepAt: timestamp(),
        updatedAt: timestamp(),
      }, { merge: true });
    }
  }
  if (params.actorId) {
    await writeOwnerAudit(params.actorId, "listing_moderation_sweep", "listing", "bulk", {
      checked,
      rejected,
      approved,
      rejectAll: params.rejectAll === true,
    });
  }
  return { checked, rejected, approved };
}

export const scheduledModerateListings = onSchedule("every 2 hours", async () => {
  await runListingModerationSweep({ source: "schedule" });
});

export const ownerRunListingModerationSweep = onCall<OwnerModerationSweepInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  return runListingModerationSweep({
    source: "owner",
    actorId: uid,
    limit: request.data.limit,
    rejectAll: request.data.rejectAll === true,
  });
});

export const ownerResolveModerationCase = onCall<OwnerResolveModerationInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const targetId = cleanText(request.data.targetId, 500);
  const reason = cleanText(request.data.reason, 1000);
  const decision = request.data.decision;
  if (!targetId || (decision !== "approved" && decision !== "rejected")) {
    throw new HttpsError("invalid-argument", "moderation_decision_invalid");
  }
  const status = decision === "approved" ? (request.data.type === "banner" ? "pending_payment" : request.data.type === "message" ? "sent" : "active") : "rejected";
  if (request.data.type === "listing") {
    await db.collection("listings").doc(targetId).set({ status, ownerDecisionReason: reason, updatedAt: timestamp(), publishedAt: status === "active" ? timestamp() : null }, { merge: true });
  } else if (request.data.type === "banner") {
    await db.collection("bannerAds").doc(targetId).set({ status, ownerDecisionReason: reason, updatedAt: timestamp() }, { merge: true });
  } else if (request.data.type === "message") {
    const [chatId, messageId] = targetId.split("/");
    if (chatId && messageId) {
      await db.collection("chatRooms").doc(chatId).collection("messages").doc(messageId).set({ status, ownerDecisionReason: reason, updatedAt: timestamp() }, { merge: true });
    }
  }
  if (request.data.caseId) {
    await db.collection("moderationCases").doc(cleanText(request.data.caseId, 120)).set({
      status: "resolved",
      ownerId: uid,
      ownerDecision: decision,
      ownerReason: reason,
      resolvedAt: timestamp(),
      updatedAt: timestamp(),
    }, { merge: true });
  }
  await writeOwnerAudit(uid, "moderation_resolve", request.data.type, targetId, {
    decision,
    reason,
  });
  return { targetId, status };
});

export const ownerSetUserStatus = onCall<OwnerSetUserStatusInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const userId = cleanText(request.data.userId, 160);
  const status = request.data.status;
  const reason = cleanText(request.data.reason ?? "", 500);
  if (!userId || (status !== "active" && status !== "banned")) {
    throw new HttpsError("invalid-argument", "user_status_invalid");
  }
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "user_not_found");
  }
  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    status,
    updatedAt: timestamp(),
  };
  if (status === "banned") {
    updates.bannedAt = timestamp();
    updates.bannedBy = uid;
    updates.bannedReason = {
      ru: reason || "Доступ ограничен владельцем приложения.",
      kk: reason || "Қол жеткізу қолданба иесімен шектелді.",
    };
  } else {
    updates.bannedUntil = admin.firestore.FieldValue.delete();
    updates.bannedReason = admin.firestore.FieldValue.delete();
    updates.bannedBy = admin.firestore.FieldValue.delete();
  }
  await userRef.set(updates, { merge: true });
  await writeOwnerAudit(uid, "user_status_change", "user", userId, {
    status,
    reason,
  });
  return { ok: true, status };
});

export const ownerSetUserRole = onCall<OwnerSetUserRoleInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const userId = cleanText(request.data.userId, 160);
  const role = request.data.role;
  if (!userId || !["user", "admin", "owner"].includes(role)) {
    throw new HttpsError("invalid-argument", "user_role_invalid");
  }
  if (userId === uid && role !== "owner") {
    throw new HttpsError("failed-precondition", "owner_cannot_downgrade_self");
  }
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "user_not_found");
  }
  await userRef.set({ role, updatedAt: timestamp() }, { merge: true });
  await writeOwnerAudit(uid, "user_role_change", "user", userId, { role });
  return { ok: true, role };
});

export const ownerUpdateUserProfile = onCall<OwnerUpdateUserProfileInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const userId = cleanText(request.data.userId, 160);
  if (!userId) {
    throw new HttpsError("invalid-argument", "user_required");
  }
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "user_not_found");
  }

  const name = cleanText(request.data.name ?? "", 120);
  const city = cleanText(request.data.city ?? "", 100);
  const phone = cleanText(request.data.phone ?? "", 40);
  const sellerType = cleanText(request.data.sellerType ?? "", 40);
  if (!name) {
    throw new HttpsError("invalid-argument", "name_required");
  }
  if (sellerType && sellerType !== "private" && sellerType !== "business") {
    throw new HttpsError("invalid-argument", "seller_type_invalid");
  }

  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    name,
    city,
    updatedAt: timestamp(),
    updatedBy: uid,
  };
  if (phone) updates.phone = normalizePhone(phone);
  if (sellerType) updates.sellerType = sellerType;

  await userRef.set(updates, { merge: true });
  await writeOwnerAudit(uid, "user_profile_update", "user", userId, {
    name,
    city,
    phone: phone ? normalizePhone(phone) : "",
    sellerType,
  });
  return { ok: true };
});

export const ownerSetListingStatus = onCall<OwnerSetListingStatusInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const listingId = cleanText(request.data.listingId, 120);
  const status = request.data.status;
  const reason = cleanText(request.data.reason ?? "", 1000);
  if (!listingId || !["active", "rejected", "owner_review", "archived", "deleted"].includes(status)) {
    throw new HttpsError("invalid-argument", "listing_status_invalid");
  }
  const listingRef = db.collection("listings").doc(listingId);
  const listingSnap = await listingRef.get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "listing_not_found");
  }
  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    status,
    ownerDecisionReason: reason,
    updatedAt: timestamp(),
    updatedBy: uid,
  };
  if (status === "active") {
    updates.publishedAt = timestamp();
    updates.rejectionReasonRu = "";
    updates.rejectionReasonKk = "";
  }
  if (status === "rejected") {
    updates.rejectionReasonRu = reason || "Отклонено владельцем приложения.";
    updates.rejectionReasonKk = reason || "Қолданба иесі қабылдамады.";
  }
  if (status === "archived") {
    updates.archivedAt = timestamp();
    updates.archivedReason = reason || "owner_archived";
  }
  if (status === "deleted") {
    updates.deletedAt = timestamp();
    updates.deletedBy = uid;
    updates.deletedReason = reason || "owner_deleted";
  }
  await listingRef.set(updates, { merge: true });
  await writeOwnerAudit(uid, "listing_status_change", "listing", listingId, {
    status,
    reason,
  });
  if (listing.ownerId) {
    const title = status === "active"
      ? { ru: "Объявление опубликовано", kk: "Хабарландыру жарияланды" }
      : status === "rejected"
        ? { ru: "Объявление отклонено", kk: "Хабарландыру қабылданбады" }
        : status === "archived"
          ? { ru: "Объявление перенесено в архив", kk: "Хабарландыру архивке ауыстырылды" }
          : status === "deleted"
            ? { ru: "Объявление удалено", kk: "Хабарландыру жойылды" }
            : { ru: "Объявление на проверке", kk: "Хабарландыру тексерісте" };
    const body = reason
      ? { ru: reason, kk: reason }
      : { ru: cleanText(listing.title, 120), kk: cleanText(listing.title, 120) };
    await notifyUser(String(listing.ownerId), "listing_status", title, body, { listingId, status });
  }
  return { listingId, status };
});

export const ownerSetBannerStatus = onCall<OwnerSetBannerStatusInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const bannerId = cleanText(request.data.bannerId, 120);
  const status = request.data.status;
  const reason = cleanText(request.data.reason ?? "", 1000);
  if (!bannerId || !["active", "rejected", "owner_review", "pending_payment", "archived", "deleted"].includes(status)) {
    throw new HttpsError("invalid-argument", "banner_status_invalid");
  }
  const bannerRef = db.collection("bannerAds").doc(bannerId);
  const bannerSnap = await bannerRef.get();
  const banner = bannerSnap.data();
  if (!bannerSnap.exists || !banner) {
    throw new HttpsError("not-found", "banner_not_found");
  }
  const settings = await getRuntimeAppSettings();
  const updates: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    status,
    ownerDecisionReason: reason,
    updatedAt: timestamp(),
    updatedBy: uid,
  };
  if (status === "active" && !banner.activeUntil) {
    updates.activeUntil = admin.firestore.Timestamp.fromMillis(Date.now() + settings.maxBannerDays * 24 * 60 * 60 * 1000);
  }
  if (status === "rejected") {
    updates.rejectionReasonRu = reason || "Баннер отклонён владельцем приложения.";
    updates.rejectionReasonKk = reason || "Баннер қолданба иесімен қабылданбады.";
  }
  if (status === "deleted") {
    updates.deletedAt = timestamp();
    updates.deletedBy = uid;
    updates.deletedReason = reason || "owner_deleted";
  }
  await bannerRef.set(updates, { merge: true });
  await writeOwnerAudit(uid, "banner_status_change", "banner", bannerId, {
    status,
    reason,
  });
  if (banner.ownerId) {
    await notifyUser(
      String(banner.ownerId),
      "banner_status",
      status === "active"
        ? { ru: "Баннер опубликован", kk: "Баннер жарияланды" }
        : status === "rejected"
          ? { ru: "Баннер отклонён", kk: "Баннер қабылданбады" }
          : { ru: "Статус баннера обновлён", kk: "Баннер күйі жаңартылды" },
      reason ? { ru: reason, kk: reason } : { ru: cleanText(banner.title, 120), kk: cleanText(banner.title, 120) },
      { bannerId, status },
    );
  }
  return { bannerId, status };
});

export const ownerUpdateBanner = onCall<OwnerUpdateBannerInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const bannerId = cleanText(request.data.bannerId, 120);
  const title = cleanText(request.data.title, 100);
  const caption = cleanText(request.data.caption, 180);
  const imageUrl = cleanText(request.data.imageUrl, 1000);
  if (!bannerId || !title || !caption || !imageUrl) {
    throw new HttpsError("invalid-argument", "banner_required_fields");
  }
  const bannerRef = db.collection("bannerAds").doc(bannerId);
  const bannerSnap = await bannerRef.get();
  const banner = bannerSnap.data();
  if (!bannerSnap.exists || !banner) {
    throw new HttpsError("not-found", "banner_not_found");
  }
  if (imageUrl !== String(banner.imageUrl ?? "")) {
    assertStorageUrlForUser(imageUrl, uid, ["bannerAds"]);
  }
  const settings = await getRuntimeAppSettings();
  const result = applyModerationSettings(
    await moderateContent({
      targetType: "banner",
      title,
      description: caption,
      images: [imageUrl],
      userViolationCount: Number((await getUser(String(banner.ownerId ?? uid))).violationCount ?? 0),
    }),
    settings,
    "banner",
  );
  const status = moderationStatus(result.decision, "banner");
  await bannerRef.set({
    title,
    caption,
    imageUrl,
    targetUrl: cleanText(request.data.targetUrl, 1000),
    status,
    moderation: result,
    rejectionReasonRu: result.decision === "rejected" ? result.reason.ru : "",
    updatedAt: timestamp(),
    updatedBy: uid,
  }, { merge: true });
  if (result.decision === "needs_owner_review") {
    const caseId = await createModerationCase({
      type: "banner",
      targetId: bannerId,
      ownerId: String(banner.ownerId ?? uid),
      result,
      payload: { title },
    });
    await notifyOwnersForModeration(caseId, "banner", title);
  }
  await writeOwnerAudit(uid, "banner_edit", "banner", bannerId, { status, title });
  if (banner.ownerId) {
    await notifyUser(
      String(banner.ownerId),
      "banner_updated",
      { ru: "Баннер обновлён", kk: "Баннер жаңартылды" },
      status === "rejected" ? result.reason : { ru: title, kk: title },
      { bannerId, status },
    );
  }
  return { bannerId, status, moderation: result };
});

export const ownerSetSupportTicketStatus = onCall<OwnerSetSupportTicketStatusInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const ticketId = cleanText(request.data.ticketId, 120);
  const status = request.data.status;
  const reply = cleanText(request.data.reply ?? "", 2000);
  if (!ticketId || !["open", "closed", "resolved"].includes(status)) {
    throw new HttpsError("invalid-argument", "support_status_invalid");
  }
  const ticketRef = db.collection("supportTickets").doc(ticketId);
  const ticketSnap = await ticketRef.get();
  const ticket = ticketSnap.data();
  if (!ticketSnap.exists || !ticket) {
    throw new HttpsError("not-found", "support_ticket_not_found");
  }
  await ticketRef.set({
    status,
    ownerReply: reply,
    updatedAt: timestamp(),
    updatedBy: uid,
    resolvedAt: status === "open" ? null : timestamp(),
  }, { merge: true });
  await writeOwnerAudit(uid, "support_ticket_status_change", "supportTicket", ticketId, { status, hasReply: Boolean(reply) });
  if (ticket.userId) {
    await notifyUser(
      String(ticket.userId),
      "support_ticket_status",
      { ru: "Статус обращения обновлён", kk: "Өтініш күйі жаңартылды" },
      { ru: reply || `Обращение: ${status}`, kk: reply || `Өтініш: ${status}` },
      { ticketId, status },
    );
  }
  return { ticketId, status };
});

export const ownerResolveReport = onCall<OwnerResolveReportInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const reportId = cleanText(request.data.reportId, 120);
  const status = request.data.status;
  const reason = cleanText(request.data.reason ?? "", 1000);
  if (!reportId || !["resolved", "rejected"].includes(status)) {
    throw new HttpsError("invalid-argument", "report_status_invalid");
  }
  const reportRef = db.collection("reports").doc(reportId);
  const reportSnap = await reportRef.get();
  if (!reportSnap.exists) {
    throw new HttpsError("not-found", "report_not_found");
  }
  await reportRef.set({
    status,
    ownerReason: reason,
    resolvedBy: uid,
    resolvedAt: timestamp(),
    updatedAt: timestamp(),
  }, { merge: true });
  await writeOwnerAudit(uid, "report_resolve", "report", reportId, {
    status,
    reason,
  });
  return { reportId, status };
});

export const ownerSyncPaymentStatus = onCall<SyncPaymentStatusInput>({ secrets: [kassa24Login, kassa24Key] }, async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const paymentId = cleanText(request.data.paymentId, 160);
  if (!paymentId) {
    throw new HttpsError("invalid-argument", "payment_id_required");
  }
  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentSnap = await paymentRef.get();
  const payment = paymentSnap.data();
  if (!paymentSnap.exists || !payment) {
    throw new HttpsError("not-found", "payment_not_found");
  }
  if (payment.status !== "paid" && payment.provider === "kassa24") {
    await syncKassa24PaymentFromApi(paymentId, payment);
  }
  const updated = (await paymentRef.get()).data() ?? payment;
  await writeOwnerAudit(uid, "payment_sync", "payment", paymentId, {
    status: String(updated.status ?? "pending"),
  });
  return { paymentId, status: updated.status ?? "pending" };
});

export const ownerSaveCategory = onCall<OwnerSaveCategoryInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const id = cleanText(request.data.id, 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const titleRu = cleanText(request.data.titleRu, 120);
  const titleKk = cleanText(request.data.titleKk ?? request.data.titleRu, 120);
  const iconKey = cleanText(request.data.iconKey ?? "grid", 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_") || "grid";
  if (!id || !titleRu) {
    throw new HttpsError("invalid-argument", "category_required");
  }
  const subcategories = (request.data.subcategories ?? [])
    .map((item) => {
      const subId = cleanText(item.id ?? "", 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
      const subRu = cleanText(item.titleRu ?? "", 120);
      const subKk = cleanText(item.titleKk ?? item.titleRu ?? "", 120);
      return subId && subRu ? { id: subId, title: { ru: subRu, kk: subKk || subRu } } : null;
    })
    .filter((item): item is { id: string; title: { ru: string; kk: string } } => item !== null)
    .slice(0, 80);
  const filters = (request.data.filters ?? [])
    .map((item) => {
      const filterId = cleanText(item.id ?? "", 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
      const filterRu = cleanText(item.titleRu ?? "", 120);
      const filterKk = cleanText(item.titleKk ?? item.titleRu ?? "", 120);
      const options = (item.options ?? [])
        .map((option) => cleanText(option, 80))
        .filter((option) => option.length > 0)
        .slice(0, 80);
      return filterId && filterRu && options.length
        ? { id: filterId, title: { ru: filterRu, kk: filterKk || filterRu }, options }
        : null;
    })
    .filter((item): item is { id: string; title: { ru: string; kk: string }; options: string[] } => item !== null)
    .slice(0, 40);
  const snap = await db.collection("listingCategories").get();
  const categoryRef = db.collection("listingCategories").doc(id);
  const existing = await categoryRef.get();
  const existingSortOrder = Number(existing.get("sortOrder") ?? 0);
  await db.collection("listingCategories").doc(id).set({
    id,
    title: { ru: titleRu, kk: titleKk || titleRu },
    iconKey,
    subcategories,
    filters,
    isActive: request.data.isActive === true,
    sortOrder: existingSortOrder > 0 ? existingSortOrder : snap.size + 1,
    updatedAt: timestamp(),
    updatedBy: uid,
  }, { merge: true });
  await writeOwnerAudit(uid, "category_save", "listingCategory", id, {
    titleRu,
    isActive: request.data.isActive === true,
  });
  return { categoryId: id };
});

export const ownerSavePlan = onCall<OwnerSavePlanInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const id = cleanText(request.data.id, 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const title = cleanText(request.data.title, 120);
  const titleKk = cleanText(request.data.titleKk ?? request.data.title, 120);
  const caption = cleanText(request.data.caption, 300);
  const captionKk = cleanText(request.data.captionKk ?? request.data.caption, 300);
  const price = Number(request.data.price ?? 0);
  const days = Number(request.data.days ?? 0);
  if (!id || !title || price < 0 || days <= 0) {
    throw new HttpsError("invalid-argument", "plan_required");
  }
  const collection = request.data.banner ? "bannerPlans" : "promotionPlans";
  const snap = await db.collection(collection).get();
  const planRef = db.collection(collection).doc(id);
  const existing = await planRef.get();
  const existingSortOrder = Number(existing.get("sortOrder") ?? 0);
  await db.collection(collection).doc(id).set({
    id,
    title: { ru: title, kk: titleKk || title },
    description: { ru: caption, kk: captionKk || caption },
    price,
    currency: "KZT",
    durationDays: days,
    isActive: request.data.isActive !== false,
    sortOrder: existingSortOrder > 0 ? existingSortOrder : snap.size + 1,
    updatedAt: timestamp(),
    updatedBy: uid,
  }, { merge: true });
  await writeOwnerAudit(uid, "plan_save", collection, id, {
    title,
    price,
    days,
    isActive: request.data.isActive !== false,
  });
  return { planId: id };
});

export const ownerSaveLocation = onCall<OwnerSaveLocationInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const id = cleanText(request.data.id, 80).toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const titleRu = cleanText(request.data.titleRu, 120);
  const titleKk = cleanText(request.data.titleKk ?? request.data.titleRu, 120);
  const cities = (request.data.cities ?? [])
    .map((city) => cleanText(city, 100))
    .filter((city) => city.length > 0)
    .slice(0, 300);
  if (!id || !titleRu || cities.length === 0) {
    throw new HttpsError("invalid-argument", "location_required");
  }
  const snap = await db.collection("locations").get();
  const locationRef = db.collection("locations").doc(id);
  const existing = await locationRef.get();
  const existingSortOrder = Number(existing.get("sortOrder") ?? 0);
  await locationRef.set({
    id,
    title: { ru: titleRu, kk: titleKk || titleRu },
    cities,
    isActive: request.data.isActive !== false,
    sortOrder: existingSortOrder > 0 ? existingSortOrder : snap.size + 1,
    updatedAt: timestamp(),
    updatedBy: uid,
  }, { merge: true });
  await writeOwnerAudit(uid, "location_save", "location", id, {
    titleRu,
    cities: cities.length,
    isActive: request.data.isActive !== false,
  });
  return { locationId: id };
});

export const ownerSaveLegalDocuments = onCall<OwnerSaveLegalInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const documents: Record<string, LocalizedText> = {};
  for (const [id, value] of Object.entries(request.data.documents ?? {})) {
    const cleanId = cleanText(id, 80).replace(/[^a-z0-9_]+/g, "_");
    const ru = cleanText(value?.ru ?? "", 12000);
    const kk = cleanText(value?.kk ?? "", 12000);
    if (cleanId && (ru || kk)) {
      documents[cleanId] = { ru, kk: kk || ru };
    }
  }
  if (Object.keys(documents).length === 0) {
    throw new HttpsError("invalid-argument", "legal_documents_required");
  }
  const currentVersion = cleanText(request.data.currentVersion ?? new Date().toISOString().slice(0, 10), 40);
  await db.collection("appSettings").doc("legal").set({
    currentVersion,
    documents,
    updatedAt: timestamp(),
    updatedBy: uid,
  }, { merge: true });
  await writeOwnerAudit(uid, "legal_documents_save", "appSettings", "legal", {
    currentVersion,
    documents: Object.keys(documents).length,
  });
  return { ok: true, currentVersion };
});

export const ownerSaveAppSettings = onCall<OwnerSaveAppSettingsInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  const clamp = (value: unknown, min: number, max: number, fallback: number) => {
    const numberValue = Number(value ?? fallback);
    if (!Number.isFinite(numberValue)) return fallback;
    return Math.min(max, Math.max(min, numberValue));
  };
  const settings = {
    supportPhone: cleanText(request.data.supportPhone ?? "", 80),
    supportWhatsApp: cleanText(request.data.supportWhatsApp ?? "", 80),
    moderationEnabled: request.data.moderationEnabled !== false,
    autoApproveBelow: clamp(request.data.autoApproveBelow, 0, 1, 0.25),
    ownerReviewAbove: clamp(request.data.ownerReviewAbove, 0, 1, 0.55),
    autoRejectAbove: clamp(request.data.autoRejectAbove, 0, 1, 0.9),
    maxListingPhotos: clamp(request.data.maxListingPhotos, 1, 20, 10),
    maxBannerDays: clamp(request.data.maxBannerDays, 1, 365, 30),
    updatedAt: timestamp(),
    updatedBy: uid,
  };
  await db.collection("appSettings").doc("general").set(settings, { merge: true });
  await writeOwnerAudit(uid, "app_settings_save", "appSettings", "general", {
    moderationEnabled: settings.moderationEnabled,
    autoApproveBelow: settings.autoApproveBelow,
    ownerReviewAbove: settings.ownerReviewAbove,
    autoRejectAbove: settings.autoRejectAbove,
  });
  return { ok: true };
});

export const sendPushNotification = onCall<SendPushInput>(async (request) => {
  const uid = assertSignedIn(request);
  await assertAdmin(uid);
  if (!request.data.userId && !request.data.topic) {
    throw new HttpsError("invalid-argument", "recipient_required");
  }

  if (request.data.userId) {
    await notifyUser(request.data.userId, "admin_push", request.data.title, request.data.body, request.data.data ?? {});
    await writeOwnerAudit(uid, "push_send", "user", request.data.userId, {
      titleRu: request.data.title.ru,
    });
    return { ok: true };
  }

  if (request.data.topic === "all") {
    await notifyAllUsers(request.data.title, request.data.body, request.data.data ?? {});
    await writeOwnerAudit(uid, "push_send", "topic", "all", {
      titleRu: request.data.title.ru,
    });
    return { ok: true };
  }

  await messaging.send({
    topic: request.data.topic!,
    notification: {
      title: request.data.title.ru,
      body: request.data.body.ru,
    },
    data: {
      type: "admin_push",
      titleRu: request.data.title.ru,
      titleKk: request.data.title.kk,
      bodyRu: request.data.body.ru,
      bodyKk: request.data.body.kk,
      ...(request.data.data ?? {}),
    },
  });
  await writeOwnerAudit(uid, "push_send", "topic", request.data.topic!, {
    titleRu: request.data.title.ru,
  });
  return { ok: true };
});

export const kassa24Callback = onRequest({ secrets: [kassa24WebhookSecret] }, async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("method_not_allowed");
    return;
  }

  const configuredSecret = kassa24WebhookSecret.value();
  const incomingSecret = String(request.header("x-webhook-secret") ?? request.query.secret ?? "");
  if (configuredSecret && incomingSecret !== configuredSecret) {
    response.status(403).send("forbidden");
    return;
  }

  const payload = request.body as FirebaseFirestore.DocumentData;
  const paymentId = String(
    payload.orderId
      ?? payload.metadata?.paymentId
      ?? payload.paymentId
      ?? "",
  );
  if (!paymentId) {
    response.status(400).send("payment_id_required");
    return;
  }

  await db.collection("payments").doc(paymentId).set({
    providerPayload: payload,
    providerPaymentId: kassa24ProviderPaymentId(payload),
    updatedAt: timestamp(),
  }, { merge: true });

  if (isKassa24Paid(payload)) {
    await handlePaidPayment(paymentId, payload);
  } else {
    const status = kassa24StatusValue(payload.status ?? payload.paymentStatus ?? payload.state);
    await db.collection("payments").doc(paymentId).set({
      status: status === "failed" || status === "declined" || status === "cancelled" ? "failed" : "pending",
      updatedAt: timestamp(),
    }, { merge: true });
  }

  response.status(200).send("ok");
});
