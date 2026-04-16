CREATE TABLE IF NOT EXISTS pendingImports (
    id TEXT NOT NULL PRIMARY KEY,
    accountId TEXT REFERENCES accounts(id) ON DELETE SET NULL,
    amount REAL NOT NULL,
    currencyId TEXT NOT NULL,
    date DATETIME NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('E','I')),
    counterpartyName TEXT,
    bankRef TEXT,
    rawText TEXT NOT NULL,
    channel TEXT NOT NULL CHECK(channel IN ('sms','notification')),
    sender TEXT,
    confidence REAL NOT NULL DEFAULT 0.0,
    proposedCategoryId TEXT REFERENCES categories(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','confirmed','rejected','duplicate')),
    createdTransactionId TEXT REFERENCES transactions(id) ON DELETE SET NULL,
    createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_pending_imports_status_created ON pendingImports (status, createdAt DESC);
CREATE INDEX IF NOT EXISTS idx_pending_imports_bankref ON pendingImports (bankRef);
