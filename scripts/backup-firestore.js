#!/usr/bin/env node
// Exports all Firestore collections (including subcollections) to JSON files.
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const KEY_PATH = path.join(__dirname, '..', 'wallex-c6a69-firebase-adminsdk-fbsvc-b7a96ded2b.json');
const BACKUP_DIR = path.join(__dirname, '..', 'firestore-backup', new Date().toISOString().slice(0, 10));

admin.initializeApp({ credential: admin.credential.cert(KEY_PATH) });
const db = admin.firestore();

fs.mkdirSync(BACKUP_DIR, { recursive: true });

async function exportCollection(colRef, basePath) {
  // listDocuments() includes phantom docs (containers with subcollections but no fields)
  const docRefs = await colRef.listDocuments();
  if (docRefs.length === 0) return {};

  const data = {};
  for (const ref of docRefs) {
    const snap = await ref.get();
    data[ref.id] = { _data: snap.exists ? snap.data() : null, _subcollections: {} };
    const subcols = await ref.listCollections();
    for (const sub of subcols) {
      data[ref.id]._subcollections[sub.id] = await exportCollection(sub, `${basePath}/${ref.id}/${sub.id}`);
    }
  }
  return data;
}

async function main() {
  console.log(`Backing up Firestore → ${BACKUP_DIR}`);
  const collections = await db.listCollections();

  for (const col of collections) {
    process.stdout.write(`  Exporting ${col.id}...`);
    const data = await exportCollection(col, col.id);
    const file = path.join(BACKUP_DIR, `${col.id}.json`);
    fs.writeFileSync(file, JSON.stringify(data, null, 2));
    console.log(` ✓  (${Object.keys(data).length} docs)`);
  }

  console.log(`\nBackup complete: ${BACKUP_DIR}`);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
