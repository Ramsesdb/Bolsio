-- v22: Set initial balances, rename Ahorro USD, add note to BNC #2.

-- Banco de Venezuela (VES): 358,683.35 Bs
UPDATE accounts SET iniValue = 358683.35
WHERE LOWER(name) = 'banco de venezuela' AND currencyId = 'VES';

-- Banco de Venezuela USD: 46.21 USD
UPDATE accounts SET iniValue = 46.21
WHERE LOWER(name) = 'banco de venezuela usd' AND currencyId = 'USD';

-- Binance: skip (API syncs balance automatically)

-- BNC #1: 0.61 Bs
UPDATE accounts SET iniValue = 0.61
WHERE LOWER(name) = 'banco nacional de credito #1';

-- BNC #2: 17,600.71 Bs (iglesia — pendiente transferir)
UPDATE accounts SET iniValue = 17600.71,
  description = 'Dinero de la iglesia. Pendiente transferir a cuenta de la iglesia.'
WHERE LOWER(name) = 'banco nacional de credito #2';

-- Banplus: 4,483.73 Bs
UPDATE accounts SET iniValue = 4483.73
WHERE LOWER(name) = 'banplus';

-- Provincial: 0
UPDATE accounts SET iniValue = 0
WHERE LOWER(name) = 'provincial';

-- Zinli: 0.04 USD
UPDATE accounts SET iniValue = 0.04
WHERE LOWER(name) = 'zinli';

-- Efectivo USD (cartera): 55 USD
UPDATE accounts SET iniValue = 55
WHERE LOWER(name) = 'efectivo usd';

-- Efectivo Bs: 0
UPDATE accounts SET iniValue = 0
WHERE LOWER(name) = 'efectivo bs';

-- Rename "Ahorro USD" to "Ahorro Efectivo USD" (cash savings, not digital)
UPDATE accounts SET name = 'Ahorro Efectivo USD',
  description = 'Ahorro en efectivo fisico USD. No tocar.'
WHERE LOWER(name) = 'ahorro usd';
