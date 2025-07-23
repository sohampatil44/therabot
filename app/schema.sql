-- Drop the table if it exists to start fresh (useful for init-db)
DROP TABLE IF EXISTS users;

CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,       
  password TEXT NOT NULL               
);

DROP TABLE IF EXISTS chat_history;

CREATE TABLE chat_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  sender TEXT NOT NULL CHECK(sender IN ('user', 'bot')), -- 'user' or 'bot'
  message TEXT NOT NULL,
  emotion TEXT, -- Optional: Store detected emotion for bot messages
  FOREIGN KEY (user_id) REFERENCES user (id)
);

