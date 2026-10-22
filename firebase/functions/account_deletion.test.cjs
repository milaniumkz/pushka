const assert = require('node:assert/strict');
const admin = require('firebase-admin');

// This test may never run against a real project.
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):/);
assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):/);
admin.initializeApp({ projectId: 'demo-pushka-release', storageBucket: 'demo-pushka-release.appspot.com' });
const { deleteAccountData } = require('./lib/account_deletion');

(async () => {
  const db = admin.firestore();
  const uid = 'phone_77000000001';
  const other = `${uid}_other`;
  await admin.auth().createUser({ uid });
  await admin.auth().createUser({ uid: other });
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}`), { phone: '+77000000001', status: 'deleting' });
  batch.set(db.doc(`users/${other}`), { name: 'Keep me' });
  batch.set(db.doc('listings/own'), { ownerId: uid });
  batch.set(db.doc('listings/other'), { ownerId: other });
  batch.set(db.doc('listingStats/own'), { views: 10 });
  batch.set(db.doc('reports/on-own'), { reporterId: other, listingId: 'own' });
  batch.set(db.doc('chatRooms/shared'), { participants: [uid, other] });
  batch.set(db.doc('chatRooms/shared/messages/private'), { senderId: uid, text: 'Private text' });
  batch.set(db.doc('chatRooms/other'), { participants: [other, 'another'] });
  batch.set(db.doc('payments/own'), { userId: uid, customerPhone: '+77000000001', providerPayload: { phone: '+77000000001' }, amount: 990, status: 'paid' });
  batch.set(db.doc('payments/other'), { userId: other, amount: 100 });
  batch.set(db.doc('wappiOtpRequests/+77000000001'), { code: '1234' });
  for (let i = 0; i < 105; i++) batch.set(db.doc(`savedSearches/own-${i}`), { userId: uid });
  batch.set(db.doc('savedSearches/other'), { userId: other });
  await batch.commit();
  const bucket = admin.storage().bucket();
  await bucket.file(`listingImages/${uid}/photo.jpg`).save('private');
  await bucket.file(`listingImages/${other}/photo.jpg`).save('keep');
  await deleteAccountData(uid);
  await deleteAccountData(uid); // Retries must be harmless.
  for (const path of [`users/${uid}`, 'listings/own', 'listingStats/own', 'reports/on-own', 'chatRooms/shared/messages/private', 'chatRooms/shared', 'wappiOtpRequests/+77000000001']) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await db.collection('savedSearches').where('userId', '==', uid).get()).size, 0);
  const payment = (await db.doc('payments/own').get()).data();
  assert.equal(payment.amount, 990);
  assert.equal(payment.userId, undefined);
  assert.equal(payment.customerPhone, undefined);
  assert.equal(payment.providerPayload, undefined);
  assert.equal(payment.accountDeleted, true);
  for (const path of [`users/${other}`, 'listings/other', 'payments/other', 'savedSearches/other', 'chatRooms/other']) {
    assert.equal((await db.doc(path).get()).exists, true, path);
  }
  assert.equal((await bucket.file(`listingImages/${uid}/photo.jpg`).exists())[0], false);
  assert.equal((await bucket.file(`listingImages/${other}/photo.jpg`).exists())[0], true);
  await assert.rejects(admin.auth().getUser(uid), { code: 'auth/user-not-found' });
  assert.equal((await admin.auth().getUser(other)).uid, other);
  console.log('Account deletion integration passed: pagination, retry, personal data, files, and other-user isolation.');
  await admin.app().delete();
})().catch(error => { console.error(error); process.exitCode = 1; });
