-- v19: Add transfer support to pendingImports (type 'T', receivingAccountId, valueInDestiny)
-- SQLite does not support ALTER COLUMN to change CHECK constraints,
-- so we recreate the table.

PRAGMA foreign_keys = OFF;

CREATE TABLE IF NOT EXISTS pendingImports_new (
  id TEXT NOT NULL PRIMARY KEY,
  accountId TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  amount REAL NOT NULL,
  currencyId TEXT NOT NULL,
  date DATETIME NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('E', 'I', 'T')),
  counterpartyName TEXT,
  bankRef TEXT,
  rawText TEXT NOT NULL,
  channel TEXT NOT NULL CHECK(channel IN ('sms', 'notification', 'api')),
  sender TEXT,
  confidence REAL NOT NULL DEFAULT 0.0,
  proposedCategoryId TEXT REFERENCES categories(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'rejected', 'duplicate')),
  createdTransactionId TEXT REFERENCES transactions(id) ON DELETE SET NULL,
  createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  receivingAccountId TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  valueInDestiny REAL
);

INSERT INTO pendingImports_new (
  id, accountId, amount, currencyId, date, type,
  counterpartyName, bankRef, rawText, channel, sender,
  confidence, proposedCategoryId, status, createdTransactionId, createdAt
)
SELECT
  id, accountId, amount, currencyId, date, type,
  counterpartyName, bankRef, rawText, channel, sender,
  confidence, proposedCategoryId, status, createdTransactionId, createdAt
FROM pendingImports;

DROP TABLE pendingImports;

ALTER TABLE pendingImports_new RENAME TO pendingImports;

PRAGMA foreign_keys = ON;
