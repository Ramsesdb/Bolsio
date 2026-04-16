-- v20: Create "Banco de Venezuela USD" account if it does not exist.
-- Uses a UUID-like hex string as ID. Only inserts if no account with that
-- exact name + currency already exists (idempotent).

INSERT OR IGNORE INTO accounts (
  id, name, displayOrder, type, currencyId, iniValue, date, iconId, color
)
SELECT
  lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)),2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6))),
  'Banco de Venezuela USD',
  COALESCE((SELECT MAX(displayOrder) FROM accounts), 0) + 1,
  'normal',
  'USD',
  0,
  datetime('now'),
  'account_balance',
  '1A237E'
WHERE NOT EXISTS (
  SELECT 1 FROM accounts
  WHERE LOWER(name) = 'banco de venezuela usd' AND currencyId = 'USD'
);
