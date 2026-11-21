-- SPARK text-only presentation metadata. Existing rows receive safe defaults.
ALTER TABLE status_posts ADD COLUMN background_key TEXT NOT NULL DEFAULT 'midnight';
ALTER TABLE status_posts ADD COLUMN text_color_key TEXT NOT NULL DEFAULT 'white';
ALTER TABLE status_posts ADD COLUMN font_key TEXT NOT NULL DEFAULT 'modern';
