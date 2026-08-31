#!/usr/bin/env bash
# Rebuild kpx.db from scratch. Destroys any local data — the .db file is a
# build artefact, schema.sql and seed.sql are the source of truth.
set -euo pipefail

cd "$(dirname "$0")"
DB="kpx.db"

rm -f "$DB" "$DB-journal" "$DB-wal" "$DB-shm"
sqlite3 "$DB" < schema.sql
sqlite3 "$DB" < seed.sql

echo "Built $DB"
sqlite3 "$DB" "PRAGMA integrity_check;"
echo "Foreign key violations: $(sqlite3 "$DB" 'PRAGMA foreign_key_check;' | wc -l | tr -d ' ')"
sqlite3 -box "$DB" "
SELECT 'tables' AS object, count(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
UNION ALL SELECT 'views',   count(*) FROM sqlite_master WHERE type='view'
UNION ALL SELECT 'indexes', count(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';"
