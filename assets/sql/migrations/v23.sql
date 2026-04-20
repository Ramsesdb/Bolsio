-- v23: add generic attachments table for receipts/avatars and owner index.

CREATE TABLE IF NOT EXISTS attachments (
  id TEXT NOT NULL PRIMARY KEY,
  ownerType TEXT NOT NULL CHECK(ownerType IN ('transaction', 'userProfile', 'account', 'budget')),
  ownerId TEXT NOT NULL,
  localPath TEXT NOT NULL,
  mimeType TEXT NOT NULL,
  sizeBytes INTEGER NOT NULL,
  role TEXT,
  createdAt TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_attachments_owner
  ON attachments(ownerType, ownerId);
