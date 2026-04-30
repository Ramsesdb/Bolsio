-- v28: currency-modes-rework — Phase 1 schema migration.
--
-- Three concurrent effects, all idempotent on re-run:
--   1. Widen the `transactions.exchangeRateSource` CHECK constraint from
--      ('bcv','paralelo','manual','auto') to
--      ('bcv','paralelo','manual','auto_frankfurter') and remap legacy
--      'auto' rows to 'auto_frankfurter'. Lowercase any rogue uppercase
--      rows during the copy.
--   2. Lowercase-normalize the `exchangeRates.source` column in-place.
--   3. Seed `currencyMode` and `secondaryCurrency` rows in `userSettings`
--      via the heuristic from `design.md §2` (preferredRateSource → dual+VES,
--      preferredCurrency=USD → single_usd, etc.). Idempotent via
--      INSERT OR IGNORE — re-running produces no diff.
--
-- The transactions-table recreate dance follows the same pattern as v18.sql,
-- preserving every column, FK, default, and CHECK constraint verbatim. There
-- are NO indexes or triggers attached to `transactions` (verified against
-- tables.drift and assets/sql/migrations as of v27), so no extra recreate
-- steps are needed beyond the table itself.

PRAGMA foreign_keys = OFF;

CREATE TABLE IF NOT EXISTS transactions_temp (
  id TEXT NOT NULL PRIMARY KEY,
  date DATETIME NOT NULL,
  accountID TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE ON UPDATE CASCADE,
  value REAL NOT NULL,
  title TEXT,
  notes TEXT,
  type TEXT NOT NULL CHECK(type IN ('E', 'I', 'T')),
  status TEXT CHECK(status IN ('V', 'P', 'R', 'U')),
  categoryID TEXT REFERENCES categories(id) ON DELETE CASCADE ON UPDATE CASCADE,
  debtId TEXT REFERENCES debts(id) ON DELETE SET NULL ON UPDATE CASCADE,
  valueInDestiny REAL,
  receivingAccountID TEXT REFERENCES accounts(id) ON DELETE CASCADE ON UPDATE CASCADE,
  isHidden BOOLEAN NOT NULL DEFAULT 0,
  exchangeRateApplied REAL,
  exchangeRateSource TEXT CHECK(exchangeRateSource IN ('bcv','paralelo','manual','auto_frankfurter')),
  createdBy TEXT REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
  modifiedBy TEXT REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
  createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modifiedAt DATETIME,
  locLatitude REAL,
  locLongitude REAL,
  locAddress TEXT,
  intervalPeriod TEXT CHECK(intervalPeriod IN ('day','week','month','year')),
  intervalEach INTEGER,
  endDate DATETIME,
  remainingTransactions INTEGER,

  CHECK ((receivingAccountID IS NULL) != (categoryID IS NULL)),
  CHECK ((intervalPeriod IS NULL) == (intervalEach IS NULL)),
  CHECK ((intervalPeriod IS NOT NULL) OR (endDate IS NULL)),
  CHECK ((intervalPeriod IS NOT NULL) OR (remainingTransactions IS NULL)),
  CHECK ((locLongitude IS NULL AND locLatitude IS NULL) OR (locLongitude IS NOT NULL AND locLatitude IS NOT NULL)),
  CHECK ((locAddress IS NULL) OR (locLatitude IS NOT NULL AND locLongitude IS NOT NULL)),
  CHECK (categoryID IS NULL OR valueInDestiny IS NULL)
);

INSERT INTO transactions_temp (
  id,
  date,
  accountID,
  value,
  title,
  notes,
  type,
  status,
  categoryID,
  debtId,
  valueInDestiny,
  receivingAccountID,
  isHidden,
  exchangeRateApplied,
  exchangeRateSource,
  createdBy,
  modifiedBy,
  createdAt,
  modifiedAt,
  locLatitude,
  locLongitude,
  locAddress,
  intervalPeriod,
  intervalEach,
  endDate,
  remainingTransactions
)
SELECT
  id,
  date,
  accountID,
  value,
  title,
  notes,
  type,
  status,
  categoryID,
  debtId,
  valueInDestiny,
  receivingAccountID,
  isHidden,
  exchangeRateApplied,
  CASE
    WHEN exchangeRateSource IS NULL THEN NULL
    WHEN LOWER(exchangeRateSource) = 'auto' THEN 'auto_frankfurter'
    ELSE LOWER(exchangeRateSource)
  END AS exchangeRateSource,
  createdBy,
  modifiedBy,
  createdAt,
  modifiedAt,
  locLatitude,
  locLongitude,
  locAddress,
  intervalPeriod,
  intervalEach,
  endDate,
  remainingTransactions
FROM transactions;

DROP TABLE transactions;
ALTER TABLE transactions_temp RENAME TO transactions;

PRAGMA foreign_keys = ON;

-- (2) Lowercase-normalize the exchangeRates.source column. Idempotent
--     because LOWER on already-lowercase rows is a no-op. Legacy 'auto'
--     stays 'auto' here (rate refresh writes the new 'auto_frankfurter'
--     going forward — old rows remain readable via RateSource.fromDb).
UPDATE exchangeRates SET source = LOWER(source) WHERE source IS NOT NULL;

-- (3) Heuristic seed for currencyMode / secondaryCurrency. INSERT OR IGNORE
--     guarantees idempotency: a re-run of v28 (or a user already on the new
--     build) is a no-op because the row PK already exists. The heuristic
--     mirrors design.md §2 verbatim:
--
--       preferredRateSource present              -> currencyMode='dual',          secondaryCurrency='VES'
--       preferredCurrency='USD' & no rateSource  -> currencyMode='single_usd',    secondaryCurrency=NULL
--       preferredCurrency='VES' & no rateSource  -> currencyMode='single_bs',     secondaryCurrency=NULL
--       any other preferredCurrency              -> currencyMode='single_other',  secondaryCurrency=NULL
--       no keys at all                           -> currencyMode='dual',          secondaryCurrency='VES'

INSERT OR IGNORE INTO userSettings (settingKey, settingValue)
SELECT 'currencyMode',
       CASE
         WHEN EXISTS (SELECT 1 FROM userSettings WHERE settingKey = 'preferredRateSource')
              THEN 'dual'
         WHEN (SELECT settingValue FROM userSettings WHERE settingKey = 'preferredCurrency') = 'USD'
              THEN 'single_usd'
         WHEN (SELECT settingValue FROM userSettings WHERE settingKey = 'preferredCurrency') = 'VES'
              THEN 'single_bs'
         WHEN (SELECT settingValue FROM userSettings WHERE settingKey = 'preferredCurrency') IS NOT NULL
              THEN 'single_other'
         ELSE 'dual'
       END;

INSERT OR IGNORE INTO userSettings (settingKey, settingValue)
SELECT 'secondaryCurrency',
       CASE
         WHEN EXISTS (SELECT 1 FROM userSettings WHERE settingKey = 'preferredRateSource')
              THEN 'VES'
         WHEN (SELECT settingValue FROM userSettings WHERE settingKey = 'preferredCurrency') IS NULL
              THEN 'VES'
         ELSE NULL
       END;
