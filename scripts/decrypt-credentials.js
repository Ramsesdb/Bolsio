#!/usr/bin/env node
// Decrypts Firestore credentials using the same scheme as firebase_credentials_cipher.dart
// PBKDF2-HMAC-SHA256 (100k iterations) + AES-256-GCM
// Format: base64(nonce[12] || ciphertext || authTag[16])
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PEPPER = 'wallex.v1.pepper.3f7a2c91d4e58b6ac0ef1d92a73b4c8e5f6079182a3b4c5d6e7f80912a3b4c5d6';
const ITERATIONS = 100000;
const KEY_LEN = 32; // 256-bit

function deriveKey(uid) {
  const secret = Buffer.from(uid + PEPPER, 'utf8');
  const salt = Buffer.from(`wallex.credentials.salt.v1:${uid}`, 'utf8');
  return crypto.pbkdf2Sync(secret, salt, ITERATIONS, KEY_LEN, 'sha256');
}

function decrypt(key, b64) {
  if (!b64 || typeof b64 !== 'string') return null;
  try {
    const buf = Buffer.from(b64, 'base64');
    const nonce = buf.subarray(0, 12);
    const authTag = buf.subarray(buf.length - 16);
    const ciphertext = buf.subarray(12, buf.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(authTag);
    return decipher.update(ciphertext, undefined, 'utf8') + decipher.final('utf8');
  } catch {
    return '(decrypt failed)';
  }
}

const BACKUP = path.join(__dirname, '..', 'firestore-backup', '2026-05-01', 'users.json');
const data = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));

const CRED_FIELDS = ['nexusApiKey', 'nexusModel', 'ai_nexus_apiKey', 'ai_nexus_model',
                     'binanceApiKey', 'binanceSecret', 'hiddenModePinHash', 'hiddenModePinSalt'];

console.log('Deriving keys and decrypting credentials...\n');
console.log('='.repeat(60));

for (const [uid, user] of Object.entries(data)) {
  const creds = user._subcollections?.credentials;
  if (!creds) continue;

  const encDoc = creds['encrypted']?._data;
  if (!encDoc) continue;

  console.log(`\nUID: ${uid}`);
  console.log(`updatedBy: ${encDoc.updatedBy}`);

  const key = deriveKey(uid);

  for (const field of CRED_FIELDS) {
    if (encDoc[field]) {
      const plain = decrypt(key, encDoc[field]);
      if (plain && plain !== '(decrypt failed)') {
        console.log(`  ${field}: ${plain}`);
      }
    }
  }
  console.log('-'.repeat(60));
}
