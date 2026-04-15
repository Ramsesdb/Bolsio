ALTER TABLE categories DROP COLUMN calcTithe;
ALTER TABLE categories DROP COLUMN subFundPercent;
ALTER TABLE transactions DROP COLUMN calcTithe;
ALTER TABLE transactions ADD COLUMN exchangeRateApplied REAL;
ALTER TABLE transactions ADD COLUMN exchangeRateSource TEXT CHECK(exchangeRateSource IN ('bcv','paralelo','manual','auto'));
ALTER TABLE exchangeRates ADD COLUMN source TEXT;
DROP TABLE IF EXISTS auditLogs;
