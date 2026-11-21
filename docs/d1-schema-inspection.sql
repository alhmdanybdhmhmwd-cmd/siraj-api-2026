-- READ-ONLY schema inspection for an ISOLATED NON-PRODUCTION D1 database.
-- Do NOT run against production. This script reads SQLite catalog metadata only.
-- Run with: npx wrangler d1 execute <TEST_DATABASE_NAME> --remote --file docs/d1-schema-inspection.sql
-- The selected database must be a dedicated test database, not the production binding.

SELECT
  type,
  name,
  tbl_name,
  sql
FROM sqlite_master
WHERE type IN ('table', 'index')
  AND name NOT LIKE 'sqlite_%'
ORDER BY type, tbl_name, name;

-- Column definitions for the three core tables.
SELECT 'users' AS table_name, cid, name, type, "notnull", dflt_value, pk
FROM pragma_table_info('users')
UNION ALL
SELECT 'friendships', cid, name, type, "notnull", dflt_value, pk
FROM pragma_table_info('friendships')
UNION ALL
SELECT 'messages', cid, name, type, "notnull", dflt_value, pk
FROM pragma_table_info('messages')
ORDER BY table_name, cid;

-- Foreign-key relationships for the three core tables.
SELECT 'users' AS table_name, id, seq, "table", "from", "to", on_update, on_delete, match
FROM pragma_foreign_key_list('users')
UNION ALL
SELECT 'friendships', id, seq, "table", "from", "to", on_update, on_delete, match
FROM pragma_foreign_key_list('friendships')
UNION ALL
SELECT 'messages', id, seq, "table", "from", "to", on_update, on_delete, match
FROM pragma_foreign_key_list('messages')
ORDER BY table_name, id, seq;

-- Index inventory and indexed columns.
SELECT 'users' AS table_name, il.name AS index_name, il."unique" AS is_unique,
       il.origin, il.partial, ii.seqno, ii.cid, ii.name AS column_name
FROM pragma_index_list('users') AS il
JOIN pragma_index_info(il.name) AS ii
UNION ALL
SELECT 'friendships', il.name, il."unique", il.origin, il.partial,
       ii.seqno, ii.cid, ii.name
FROM pragma_index_list('friendships') AS il
JOIN pragma_index_info(il.name) AS ii
UNION ALL
SELECT 'messages', il.name, il."unique", il.origin, il.partial,
       ii.seqno, ii.cid, ii.name
FROM pragma_index_list('messages') AS il
JOIN pragma_index_info(il.name) AS ii
ORDER BY table_name, index_name, seqno;
