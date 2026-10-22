import * as admin from "firebase-admin";

// Retried by the Firestore trigger. Every operation is safe to repeat.
export async function deleteAccountData(uid: string): Promise<void> {
  const db = admin.firestore();
  const user = await db.collection("users").doc(uid).get();
  const phone = String(user.data()?.phone ?? "").replace(/\D/g, "");
  const removeQuery = async (query: FirebaseFirestore.Query): Promise<void> => {
    for (;;) {
      const page = await query.limit(100).get();
      if (page.empty) return;
      for (const doc of page.docs) await db.recursiveDelete(doc.ref);
    }
  };
  for (;;) {
    const listings = await db.collection("listings").where("ownerId", "==", uid).limit(100).get();
    if (listings.empty) break;
    for (const listing of listings.docs) {
      await removeQuery(db.collection("reports").where("listingId", "==", listing.id));
      await removeQuery(db.collection("moderationCases").where("targetId", "==", listing.id));
      await removeQuery(db.collection("notifications").where("data.listingId", "==", listing.id));
      await db.recursiveDelete(db.collection("listingStats").doc(listing.id));
      await db.recursiveDelete(listing.ref);
    }
  }
  for (;;) {
    const chats = await db.collection("chatRooms").where("participants", "array-contains", uid).limit(100).get();
    if (chats.empty) break;
    for (const chat of chats.docs) {
      await removeQuery(db.collection("reports").where("chatId", "==", chat.id));
      await removeQuery(db.collection("notifications").where("data.chatId", "==", chat.id));
      await db.recursiveDelete(chat.ref);
    }
  }
  // Remove public content before deleting the profile. Associated conversations
  // are deleted as a whole, including attachments owned by this account.
  for (const [collection, field] of [
    ["listings", "ownerId"], ["listingDrafts", "ownerId"],
    ["bannerAds", "ownerId"], ["savedSearches", "userId"],
    ["notifications", "userId"], ["supportTickets", "userId"],
    ["reports", "reporterId"], ["reports", "reportedUserId"],
    ["moderationCases", "ownerId"], ["moderationCases", "reporterId"],
    ["promotionPurchases", "userId"], ["listingCallChecks", "callerId"],
    ["listingCallChecks", "listingOwnerId"],
    ["ownerAuditLog", "actorId"], ["ownerAuditLog", "targetId"],
  ]) {
    await removeQuery(db.collection(collection).where(field, "==", uid));
  }
  await db.recursiveDelete(db.collection("listingFavorites").doc(uid));
  await db.collection("deviceAccessRequests").doc(uid).delete();

  // Keep only an anonymous accounting record; remove provider payloads because
  // they may contain a payer's contact details.
  for (;;) {
    const payments = await db.collection("payments").where("userId", "==", uid).limit(100).get();
    if (payments.empty) break;
    const batch = db.batch();
    for (const payment of payments.docs) {
      const data = payment.data();
      batch.set(payment.ref, {
        id: payment.id, type: data.type ?? "", status: data.status ?? "",
        amount: data.amount ?? 0, currency: data.currency ?? "KZT",
        createdAt: data.createdAt ?? null, paidAt: data.paidAt ?? null,
        accountDeleted: true,
      });
    }
    await batch.commit();
  }
  const bucket = admin.storage().bucket();
  for (const folder of ["users", "listingImages", "bannerAds", "chatImages", "chatFiles"]) {
    await bucket.deleteFiles({ prefix: `${folder}/${uid}/` });
  }
  if (phone && !uid.startsWith("device_")) {
    await db.collection("wappiOtpRequests").doc(`+${phone}`).delete();
  }
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
  }
  await db.recursiveDelete(db.collection("users").doc(uid));
}
