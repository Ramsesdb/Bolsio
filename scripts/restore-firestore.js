#!/usr/bin/env node
// Restores a Firestore backup JSON file into a target Firebase project.
// Converts {_seconds,_nanoseconds} objects back to Firestore Timestamps.
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, '..', 'nitido-1c416-firebase-adminsdk-fbsvc-fd1cf17133.json');
const BACKUP_FILE = path.join(__dirname, '..', 'firestore-backup', '2026-05-01', 'users.json');

admin.initializeApp({ credential: admin.credential.cert(KEY_PATH) });
const db = admin.firestore();

function reviveValue(v) {
  if (v === null || v === undefined) return v;
  if (Array.isArray(v)) return v.map(reviveValue);
  if (typeof v === 'object') {
    if (typeof v._seconds === 'number' && typeof v._nanoseconds === 'number' && Object.keys(v).length === 2) {
      return new admin.firestore.Timestamp(v._seconds, v._nanoseconds);
    }
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = reviveValue(val);
    return out;
  }
  return v;
}

let docCount = 0;
async function writeDocs(parentPath, docs) {
  // Use batches of 400 (Firestore limit is 500 writes per batch)
  const entries = Object.entries(docs);
  let batch = db.batch();
  let inBatch = 0;

  for (const [docId, doc] of entries) {
    const fullPath = `${parentPath}/${docId}`;
    if (doc._data !== null) {
      const ref = db.doc(fullPath);
      batch.set(ref, reviveValue(doc._data));
      inBatch++;
      docCount++;
      if (inBatch >= 400) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
    }

    // Recurse into subcollections (commit current batch first to keep ordering simple)
    for (const [subName, subDocs] of Object.entries(doc._subcollections || {})) {
      if (inBatch > 0) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
      await writeDocs(`${fullPath}/${subName}`, subDocs);
    }
  }

  if (inBatch > 0) await batch.commit();
}

async function main() {
  console.log(`Restoring from: ${BACKUP_FILE}`);
  console.log(`Target project: nitido-1c416\n`);

  const data = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));

  // The top-level file is a single collection (users)
  const collectionName = path.basename(BACKUP_FILE, '.json');
  console.log(`Restoring collection: ${collectionName}`);

  await writeDocs(collectionName, data);

  console.log(`\n✓ Restore complete. ${docCount} documents written.`);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
