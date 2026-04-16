-- v21: Reorder accounts by user preference.
UPDATE accounts SET displayOrder = 1 WHERE LOWER(name) = 'banco de venezuela' AND currencyId = 'VES';
UPDATE accounts SET displayOrder = 2 WHERE LOWER(name) = 'banco de venezuela usd' AND currencyId = 'USD';
UPDATE accounts SET displayOrder = 3 WHERE LOWER(name) = 'binance';
UPDATE accounts SET displayOrder = 4 WHERE LOWER(name) = 'banco nacional de credito #1';
UPDATE accounts SET displayOrder = 5 WHERE LOWER(name) = 'banco nacional de credito #2';
UPDATE accounts SET displayOrder = 6 WHERE LOWER(name) = 'banplus';
UPDATE accounts SET displayOrder = 7 WHERE LOWER(name) = 'provincial';
UPDATE accounts SET displayOrder = 8 WHERE LOWER(name) = 'zinli';
UPDATE accounts SET displayOrder = 9 WHERE LOWER(name) = 'ahorro usd';
UPDATE accounts SET displayOrder = 10 WHERE LOWER(name) = 'efectivo usd';
UPDATE accounts SET displayOrder = 11 WHERE LOWER(name) = 'efectivo bs';
