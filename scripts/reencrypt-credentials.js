#!/usr/bin/env node
// Decrypts credentials with old wallex pepper, re-encrypts with new nitido pepper,
// and writes directly to Firestore nitido-1c416.
const crypto = require('crypto');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const OLD_PEPPER  = 'wallex.v1.pepper.3f7a2c91d4e58b6ac0ef1d92a73b4c8e5f6079182a3b4c5d6e7f80912a3b4c5d6';
const NEW_PEPPER  = 'nitido.v1.pepper.3f7a2c91d4e58b6ac0ef1d92a73b4c8e5f6079182a3b4c5d6e7f80912a3b4c5d6';
const ITERATIONS  = 100000;
const KEY_LEN     = 32;

const CRED_FIELDS = ['nexusApiKey', 'nexusModel', 'ai_nexus_apiKey', 'ai_nexus_model',
                     'binanceApiKey', 'binanceSecret', 'hiddenModePinHash', 'hiddenModePinSalt'];

function deriveKey(uid, pepper, saltPrefix) {
  const secret = Buffer.from(uid + pepper, 'utf8');
  const salt   = Buffer.from(`${saltPrefix}.credentials.salt.v1:${uid}`, 'utf8');
  return crypto.pbkdf2Sync(secret, salt, ITERATIONS, KEY_LEN, 'sha256');
}

function decrypt(key, b64) {
  if (!b64 || typeof b64 !== 'string') return null;
  const buf      = Buffer.from(b64, 'base64');
  const nonce    = buf.subarray(0, 12);
  const authTag  = buf.subarray(buf.length - 16);
  const cipher   = buf.subarray(12, buf.length - 16);
  const dec      = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  dec.setAuthTag(authTag);
  return dec.update(cipher, undefined, 'utf8') + dec.final('utf8');
}

function encrypt(key, plaintext) {
  const nonce  = crypto.randomBytes(12);
  const enc    = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const body   = Buffer.concat([enc.update(plaintext, 'utf8'), enc.final()]);
  const tag    = enc.getAuthTag();
  return Buffer.concat([nonce, body, tag]).toString('base64');
}

const DEST_KEY = path.join(__dirname, '..', 'nitido-1c416-firebase-adminsdk-fbsvc-fd1cf17133.json');
admin.initializeApp({ credential: admin.credential.cert(DEST_KEY) });
const db = admin.firestore();

const BACKUP = path.join(__dirname, '..', 'firestore-backup', '2026-05-01', 'users.json');
const data   = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));

async function main() {
  console.log('Re-encrypting credentials wallex → nitido...\n');

  for (const [uid, user] of Object.entries(data)) {
    const encDoc = user._subcollections?.credentials?.encrypted?._data;
    if (!encDoc) { console.log(`${uid.slice(0,8)}... no credentials, skipping`); continue; }

    const oldKey = deriveKey(uid, OLD_PEPPER, 'wallex');
    const newKey = deriveKey(uid, NEW_PEPPER, 'nitido');

    const updates = {};
    for (const field of CRED_FIELDS) {
      if (!encDoc[field]) continue;
      try {
        const plain = decrypt(oldKey, encDoc[field]);
        updates[field] = encrypt(newKey, plain);
      } catch {
        console.warn(`  ${field}: decrypt failed, skipping`);
      }
    }

    if (Object.keys(updates).length === 0) {
      console.log(`${uid.slice(0,8)}... (${encDoc.updatedBy}) — no fields decrypted`);
      continue;
    }

    updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await db.doc(`users/${uid}/credentials/encrypted`).update(updates);
    console.log(`✓ ${uid.slice(0,8)}... (${encDoc.updatedBy}) — re-encrypted: ${Object.keys(updates).filter(k => k !== 'updatedAt').join(', ')}`);
  }

  console.log('\nDone. Credentials are now readable by the Nitido app.');
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
