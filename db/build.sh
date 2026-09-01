#!/usr/bin/env bash
# Rebuild kpx.db from the module files, in build-plan order.
# The .db is a build artefact — the .sql files are the source of truth.
#
# File naming is MMSS_name.sql: MM = module number, SS = order within it
# (01 schema, 09 seed). All-digit prefixes keep the order identical under any
# locale — a plain 01_x.sql / 01_x_seed.sql pair sorts differently in
# en_US.UTF-8 than in C, and silently runs the seed first.
#
# The build goes to a temp file and is then copied OVER the existing kpx.db
# rather than deleting it. `cp` truncates and rewrites in place, so the inode
# is preserved. Deleting the file instead would leave any GUI client (DBeaver,
# TablePlus) holding an open handle to the now-deleted inode — it would keep
# showing a ghost of the old database, and Refresh could never fix it because
# Refresh re-reads metadata over the same handle rather than reopening the file.
# Reconnecting is still the reliable move after a rebuild; this just makes a
# stale connection far less likely.
set -euo pipefail
export LC_ALL=C                      # deterministic glob order regardless of environment
cd "$(dirname "$0")"
DB="kpx.db"
TMP="$(mktemp -t kpx_build).db"
trap 'rm -f "$TMP" "${TMP%.db}"' EXIT

for f in modules/*.sql; do
  printf '  applying %-44s' "$f"
  sqlite3 "$TMP" < "$f"
  echo "ok"
done

if [ -e "$DB" ]; then cp "$TMP" "$DB"; else mv "$TMP" "$DB"; fi

echo ""
echo "  integrity : $(sqlite3 "$DB" 'PRAGMA integrity_check;')"
echo "  fk errors : $(sqlite3 "$DB" 'PRAGMA foreign_key_check;' | wc -l | tr -d ' ')"
sqlite3 -box "$DB" "
SELECT 'tables'  AS object, count(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'
UNION ALL SELECT 'views',   count(*) FROM sqlite_master WHERE type='view'
UNION ALL SELECT 'indexes', count(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';"
echo ""
echo "  path      : $(pwd)/$DB"
echo "  note      : after a rebuild, Disconnect and Reconnect in your SQL client —"
echo "              Refresh alone does not reopen the file."
