-- Ensure the SPARK status table has safe defaults on a fresh Preview database.
-- Existing installations keep their rows; Worker adds missing style columns idempotently.
CREATE TABLE IF NOT EXISTS status_posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL,
  background_key TEXT NOT NULL DEFAULT 'midnight',
  text_color_key TEXT NOT NULL DEFAULT 'white',
  font_key TEXT NOT NULL DEFAULT 'modern',
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
