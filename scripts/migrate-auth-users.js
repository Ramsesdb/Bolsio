#!/usr/bin/env node
// Exports users from wallex-c6a69 and imports them into nitido-1c416
// preserving UIDs so Firestore data remains linked.
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SRC_KEY  = path.join(__dirname, '..', 'wallex-c6a69-firebase-adminsdk-fbsvc-b7a96ded2b.json');
const DEST_KEY = path.join(__dirname, '..', 'nitido-1c416-firebase-adminsdk-fbsvc-fd1cf17133.json');

const srcApp  = admin.initializeApp({ credential: admin.credential.cert(SRC_KEY)  }, 'src');
const destApp = admin.initializeApp({ credential: admin.credential.cert(DEST_KEY) }, 'dest');

const srcAuth  = srcApp.auth();
const destAuth = destApp.auth();

async function main() {
  console.log('Exporting users from wallex-c6a69...');
  const allUsers = [];
  let pageToken;

  do {
    const result = await srcAuth.listUsers(1000, pageToken);
    allUsers.push(...result.users);
    pageToken = result.pageToken;
  } while (pageToken);

  console.log(`Found ${allUsers.length} users`);

  // Build import records preserving UID, email, passwordHash, salt, etc.
  const importRecords = allUsers.map(u => {
    const record = {
      uid: u.uid,
      email: u.email,
      emailVerified: u.emailVerified,
      displayName: u.displayName || undefined,
      photoURL: u.photoURL || undefined,
      disabled: u.disabled,
      metadata: {
        creationTime: u.metadata.creationTime,
        lastSignInTime: u.metadata.lastSignInTime,
      },
      providerData: u.providerData,
    };
    // Include password hash if available (email/password accounts)
    if (u.passwordHash) record.passwordHash = Buffer.from(u.passwordHash, 'base64');
    if (u.passwordSalt) record.passwordSalt = Buffer.from(u.passwordSalt, 'base64');
    return record;
  });

  // Save export for reference
  const exportPath = path.join(__dirname, '..', 'firestore-backup', '2026-05-01', 'auth-users.json');
  fs.writeFileSync(exportPath, JSON.stringify(allUsers.map(u => ({
    uid: u.uid,
    email: u.email,
    displayName: u.displayName,
    emailVerified: u.emailVerified,
  })), null, 2));
  console.log(`Saved user list to ${exportPath}`);

  // Import into nitido-1c416
  console.log('\nImporting into nitido-1c416...');
  const result = await destAuth.importUsers(importRecords, {
    hash: { algorithm: 'BCRYPT' },
  });

  if (result.errors.length > 0) {
    console.log(`\nErrors (${result.errors.length}):`);
    result.errors.forEach(e => console.log(`  UID ${e.index}: ${e.error.message}`));
  }

  const success = importRecords.length - result.errors.length;
  console.log(`\n✓ Imported ${success}/${importRecords.length} users successfully`);
  process.exit(result.errors.length > 0 ? 1 : 0);
}

main().catch(e => { console.error(e); process.exit(1); });
