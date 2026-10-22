const assert = require('node:assert/strict');
const { createHash, randomBytes } = require('node:crypto');
assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):/);
assert.match(process.env.FIREBASE_AUTH_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):/);
const { requestDeviceAccessCode: request, verifyDeviceAccessCode: verify,
  blockMarketplaceUser, getBlockedMarketplaceUsers, sendMessage } = require('./lib/index');
const admin = require('firebase-admin');

(async () => {
  const db = admin.firestore();
  const phone = '+77000000001';
  const data = { phone, deviceCredential: randomBytes(32).toString('hex') };
  const other = { phone, deviceCredential: randomBytes(32).toString('hex') };
  await db.doc('users/phone_77000000001').set({ role: 'owner', name: 'Existing owner' });
  await assert.rejects(request.run({ data: { phone, deviceCredential: '' } }));
  await assert.rejects(request.run({ data: { ...data, phone: '+70000000000' } }));
  const first = await request.run({ data });
  assert.match(first.code, /^\d{4}$/);
  const wrong = first.code === '0000' ? '0001' : '0000';
  await assert.rejects(verify.run({ data: { ...other, code: first.code } }));
  await assert.rejects(verify.run({ data: { ...data, code: wrong } }));
  const a = await verify.run({ data: { ...data, code: first.code } });
  assert.match(a.uid, /^device_[a-f0-9]{64}$/);
  assert.equal(a.role, 'user');
  assert.equal(a.phoneVerified, false);
  await assert.rejects(verify.run({ data: { ...data, code: first.code } }));
  const second = await request.run({ data: other });
  const b = await verify.run({ data: { ...other, code: second.code } });
  assert.notEqual(a.uid, b.uid);
  await assert.rejects(blockMarketplaceUser.run({ data: { userId: b.uid, blocked: true } }));
  await blockMarketplaceUser.run({ auth: { uid: a.uid }, data: { userId: b.uid, blocked: true } });
  assert.deepEqual((await getBlockedMarketplaceUsers.run({ auth: { uid: a.uid } })).userIds, [b.uid]);
  await db.doc('chatRooms/blocked-chat').set({ participants: [a.uid, b.uid] });
  for (const uid of [a.uid, b.uid]) {
    await assert.rejects(sendMessage.run({ auth: { uid }, data: { chatId: 'blocked-chat', text: 'Must not send' } }), error => error.message === 'user_blocked');
  }
  await blockMarketplaceUser.run({ auth: { uid: a.uid }, data: { userId: b.uid, blocked: false } });
  assert.deepEqual((await getBlockedMarketplaceUsers.run({ auth: { uid: a.uid } })).userIds, []);
  assert.equal((await db.doc('users/phone_77000000001').get()).data().role, 'owner');
  await assert.rejects(request.run({ data: { ...data, phone: '+77000000002' } }));
  const again = await request.run({ data });
  for (let i = 0; i < 5; i++) {
    await assert.rejects(verify.run({ data: { ...data, code: again.code === '0000' ? '0001' : '0000' } }));
  }
  await assert.rejects(verify.run({ data: { ...data, code: again.code } }));
  await db.doc('storeReviewAccess/config').set({ codeHash: createHash('sha256').update('8274').digest('hex') });
  for (let i = 0; i < 2; i++) {
    const reviewer = { phone: '+77000000099', deviceCredential: randomBytes(32).toString('hex') };
    assert.equal((await request.run({ data: reviewer })).code, null);
    const result = await verify.run({ data: { ...reviewer, code: '8274' } });
    assert.equal(result.uid, 'store_review_user');
    assert.equal(result.role, 'user');
    assert.equal(result.isNewUser, false);
    assert.equal(result.city, 'Алматы');
  }
  for (let i = 0; i < 5; i++) {
    const attacker = { phone: '+77000000099', deviceCredential: randomBytes(32).toString('hex') };
    await request.run({ data: attacker });
    await assert.rejects(verify.run({ data: { ...attacker, code: '0000' } }));
  }
  const limited = { phone: '+77000000099', deviceCredential: randomBytes(32).toString('hex') };
  await request.run({ data: limited });
  await assert.rejects(verify.run({ data: { ...limited, code: '8274' } }), error => error.code === 'resource-exhausted');
  console.log('Device access passed: separate identities for same phone, no owner access, no replay, attempt limit, phone binding.');
  await admin.app().delete();
})().catch(error => { console.error(error); process.exitCode = 1; });
