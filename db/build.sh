#!/usr/bin/env bash
# Rebuild kpx.db from the module files, in build-plan order.
# The .db is a build artefact — the .sql files are the source of truth.
#
# File naming is MMSS_name.sql: MM = module number, SS = order within it
# (01 schema, 09 seed). All-digit prefixes keep the order identical under any
# locale — a plain 01_x.sql / 01_x_seed.sql pair sorts differently in
# en_US.UTF-8 than in C, and silently runs the seed first.
set -euo pipefail
export LC_ALL=C                      # deterministic glob order regardless of environment
cd "$(dirname "$0")"
DB="kpx.db"
rm -f "$DB" "$DB-journal" "$DB-wal" "$DB-shm"

for f in modules/*.sql; do
  printf '  applying %-44s' "$f"
  sqlite3 "$DB" < "$f"
  echo "ok"
done

echo ""
echo "  integrity : $(sqlite3 "$DB" 'PRAGMA integrity_check;')"
echo "  fk errors : $(sqlite3 "$DB" 'PRAGMA foreign_key_check;' | wc -l | tr -d ' ')"
sqlite3 -box "$DB" "
SELECT 'tables'  AS object, count(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
UNION ALL SELECT 'views',   count(*) FROM sqlite_master WHERE type='view'
UNION ALL SELECT 'indexes', count(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';"
