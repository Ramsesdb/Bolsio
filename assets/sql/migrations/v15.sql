-- Expand CHECK constraint on pending_imports.channel to include 'api'
PRAGMA foreign_keys=OFF;

CREATE TABLE pendingImports_new (
  id TEXT NOT NULL PRIMARY KEY,
  accountId TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  amount REAL NOT NULL,
  currencyId TEXT NOT NULL,
  date DATETIME NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('E','I')),
  counterpartyName TEXT,
  bankRef TEXT,
  rawText TEXT NOT NULL,
  channel TEXT NOT NULL CHECK(channel IN ('sms','notification','api')),
  sender TEXT,
  confidence REAL NOT NULL DEFAULT 0.0,
  proposedCategoryId TEXT REFERENCES categories(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','confirmed','rejected','duplicate')),
  createdTransactionId TEXT REFERENCES transactions(id) ON DELETE SET NULL,
  createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO pendingImports_new SELECT * FROM pendingImports;
DROP TABLE pendingImports;
ALTER TABLE pendingImports_new RENAME TO pendingImports;

CREATE INDEX idx_pending_imports_status_created ON pendingImports(status, createdAt DESC);
CREATE INDEX idx_pending_imports_bankref ON pendingImports(bankRef);

PRAGMA foreign_keys=ON;
