CREATE TABLE statement_import_batches (
  id           TEXT PRIMARY KEY,
  accountId    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  createdAt    DATETIME NOT NULL,
  mode         TEXT NOT NULL,
  transactionIds TEXT NOT NULL
);
CREATE INDEX idx_sib_account ON statement_import_batches(accountId);
CREATE INDEX idx_sib_created ON statement_import_batches(createdAt);
