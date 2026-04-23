-- v27: rename legacy key 'binanceNotifProfileEnabled' to 'binanceApiProfileEnabled'.
--
-- The key was misnamed at creation. The real table name in the schema is
-- userSettings (camelCase), not user_settings.
UPDATE userSettings
   SET settingKey = 'binanceApiProfileEnabled'
 WHERE settingKey = 'binanceNotifProfileEnabled';
