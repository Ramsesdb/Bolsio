PRAGMA foreign_keys = OFF;

ALTER TABLE users RENAME TO users_old;

CREATE TABLE IF NOT EXISTS users (
  id TEXT NOT NULL PRIMARY KEY,
  email TEXT NOT NULL,
  displayName TEXT,
  role TEXT NOT NULL DEFAULT 'user',
  createdAt TEXT NOT NULL,
  lastLogin TEXT
);

INSERT INTO users (id, email, displayName, role, createdAt, lastLogin)
SELECT id, email, displayName, role, createdAt, lastLogin
FROM users_old;

DROP TABLE users_old;

PRAGMA foreign_keys = ON;
