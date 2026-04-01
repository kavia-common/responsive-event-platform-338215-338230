#!/bin/bash
set -euo pipefail

# Migration runner for this PostgreSQL container.
#
# Contract:
# - Inputs:
#   - Reads DB connection parameters from local db_connection.txt (must contain: psql postgresql://...)
#   - Reads SQL migration files from ./migrations/*.sql (lexicographically sorted)
#   - Optional seed SQL at ./seed/seed.sql (applied once, after migrations, if present)
# - Outputs:
#   - Ensures schema exists and is up-to-date per migrations
#   - Creates/updates schema_migrations + seed_log tables for idempotency
# - Errors:
#   - Any psql error stops execution (set -e). Output includes failed migration filename.
# - Side effects:
#   - Writes rows into schema_migrations and seed_log tables in the target database.
#
# Notes:
# - This intentionally uses file-based migrations because this container’s startup scripts
#   are shell-based and already manage DB lifecycle.
# - We keep a single canonical flow (this script) for applying migrations/seed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [ ! -f "db_connection.txt" ]; then
  echo "ERROR: db_connection.txt not found. Cannot run migrations."
  exit 1
fi

# db_connection.txt contains a helpful command like:
#   psql postgresql://appuser:dbuser123@localhost:5000/myapp
CONN_STR="$(cat db_connection.txt | tr -d '\n' | sed 's/^psql[[:space:]]*//')"
if [ -z "${CONN_STR}" ]; then
  echo "ERROR: Could not parse connection string from db_connection.txt"
  exit 1
fi

PSQL_BASE=(psql "${CONN_STR}" -v ON_ERROR_STOP=1 -q)

echo "Running DB migrations using ${CONN_STR}"

# Ensure migration tracking tables exist.
"${PSQL_BASE[@]}" -c "CREATE TABLE IF NOT EXISTS public.schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"
"${PSQL_BASE[@]}" -c "CREATE TABLE IF NOT EXISTS public.seed_log (seed_name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());"

apply_migration () {
  local file_path="$1"
  local file_name
  file_name="$(basename "${file_path}")"

  # version = leading digits + underscore name, e.g. "001_init.sql" -> "001_init"
  local version="${file_name%.sql}"

  local already
  already="$("${PSQL_BASE[@]}" -t -c "SELECT 1 FROM public.schema_migrations WHERE version='${version}' LIMIT 1;" | tr -d '[:space:]' || true)"
  if [ "${already}" = "1" ]; then
    echo "✓ Migration already applied: ${file_name}"
    return 0
  fi

  echo "Applying migration: ${file_name}"
  "${PSQL_BASE[@]}" -f "${file_path}"

  # Record only if successful.
  "${PSQL_BASE[@]}" -c "INSERT INTO public.schema_migrations(version) VALUES ('${version}');"
  echo "✓ Applied migration: ${file_name}"
}

shopt -s nullglob
MIGRATIONS=(migrations/*.sql)
if [ "${#MIGRATIONS[@]}" -eq 0 ]; then
  echo "No migrations found in ./migrations. Skipping."
else
  for m in "${MIGRATIONS[@]}"; do
    apply_migration "${m}"
  done
fi

apply_seed () {
  local seed_file="$1"
  local seed_name
  seed_name="$(basename "${seed_file}")"

  local already
  already="$("${PSQL_BASE[@]}" -t -c "SELECT 1 FROM public.seed_log WHERE seed_name='${seed_name}' LIMIT 1;" | tr -d '[:space:]' || true)"
  if [ "${already}" = "1" ]; then
    echo "✓ Seed already applied: ${seed_name}"
    return 0
  fi

  echo "Applying seed: ${seed_name}"
  "${PSQL_BASE[@]}" -f "${seed_file}"
  "${PSQL_BASE[@]}" -c "INSERT INTO public.seed_log(seed_name) VALUES ('${seed_name}');"
  echo "✓ Applied seed: ${seed_name}"
}

if [ -f "seed/seed.sql" ]; then
  apply_seed "seed/seed.sql"
else
  echo "No seed file found at ./seed/seed.sql. Skipping seed."
fi

echo "Migrations/seed complete."
