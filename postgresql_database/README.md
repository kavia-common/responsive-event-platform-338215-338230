# postgresql_database

This container runs PostgreSQL and bootstraps the database `myapp` on port `5000`.

## Connection

The startup script writes a connection helper to:

- `db_connection.txt` (example: `psql postgresql://appuser:dbuser123@localhost:5000/myapp`)

## Migrations + seed data

### Flow (single entrypoint)
- `./migrate.sh` is the canonical entrypoint for schema migrations and seed data.
- `startup.sh` calls `./migrate.sh` after it creates the database/user and writes `db_connection.txt`.

### How it works
- Migrations live in `migrations/*.sql` and are applied in lexicographic order.
- Applied migrations are tracked in `public.schema_migrations(version, applied_at)`.
- Seed data lives in `seed/seed.sql` (optional).
- Seed application is tracked in `public.seed_log(seed_name, applied_at)` so it runs once.

### Debugging
If migrations fail:
1. Check `post_process.log` and container logs.
2. Connect using `db_connection.txt` and inspect:
   - `SELECT * FROM public.schema_migrations ORDER BY applied_at;`
   - `SELECT * FROM public.seed_log ORDER BY applied_at;`
3. Re-run `./migrate.sh` after fixing the migration file.

## Backup/restore

- `backup_db.sh` uses `pg_dump --clean --if-exists --create` to produce `database_backup.sql`
- `restore_db.sh` restores from `database_backup.sql`

Because migrations are applied via tracked SQL files, restoring a dump is compatible; `startup.sh` will see the DB running and will not re-run in that early-exit case. If you need to re-apply migrations after a restore, manually run `./migrate.sh`.
