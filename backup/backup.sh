#!/usr/bin/env bash
#
# Paperclip backup — runs INSIDE the backup container (scheduled by supercronic).
# -----------------------------------------------------------------------------
# Differences from a host script:
#   - Reaches Postgres over the Docker network by service hostname `db`
#     (no `docker compose exec` — we ARE in a container).
#   - The Paperclip data volume is mounted read-only at /data.
#   - The Paperclip .env is mounted read-only at /secrets/paperclip.env.
#   - rclone config is mounted at /config/rclone so credentials persist.
#
# Environment variables (set on the service in docker-compose.yml):
#   POSTGRES_PASSWORD   - same value Paperclip uses
#   RCLONE_REMOTE       - name of the configured rclone remote (e.g. gdrive)
#   RCLONE_DEST_PATH    - folder path inside Google Drive
#   RETENTION_DAYS      - how many days of dated folders to keep
#   TZ                  - timezone (also drives the cron schedule)

set -euo pipefail

# ---- Settings (overridable via env) ----------------------------------------
PGHOST="${PGHOST:-db}"
PGUSER="${PGUSER:-paperclip}"
PGDATABASE="${PGDATABASE:-paperclip}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
RCLONE_DEST_PATH="${RCLONE_DEST_PATH:-paperclip-backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
# ----------------------------------------------------------------------------

DATE="$(date +%Y-%m-%d)"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
WORK_DIR="/backups/${DATE}"
LOG_TAG="[paperclip-backup ${STAMP}]"

echo "${LOG_TAG} starting"
mkdir -p "$WORK_DIR"

# 1. Database dump (all companies live in this one DB) -----------------------
echo "${LOG_TAG} dumping Postgres from host '${PGHOST}'..."
PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
    -h "$PGHOST" -U "$PGUSER" "$PGDATABASE" \
    | gzip > "${WORK_DIR}/paperclip-db_${STAMP}.sql.gz"

# 2. Data volume (mounted read-only at /data) + .env -------------------------
echo "${LOG_TAG} archiving data volume..."
tar czf "${WORK_DIR}/paperclip-data_${STAMP}.tar.gz" -C /data .

if [ -f /secrets/paperclip.env ]; then
    echo "${LOG_TAG} copying .env (holds BETTER_AUTH_SECRET)..."
    cp /secrets/paperclip.env "${WORK_DIR}/env_${STAMP}.backup"
else
    echo "${LOG_TAG} WARNING: /secrets/paperclip.env not found — skipping .env backup"
fi

# 3. Upload to Google Drive (dated folder) -----------------------------------
echo "${LOG_TAG} uploading to ${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${DATE} ..."
rclone copy "$WORK_DIR" "${RCLONE_REMOTE}:${RCLONE_DEST_PATH}/${DATE}" \
    --transfers=4 --checkers=8 --contimeout=60s --timeout=300s --retries=3

# 4. Prune old backups (local + remote) --------------------------------------
echo "${LOG_TAG} pruning local backups older than ${RETENTION_DAYS} days..."
find /backups -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" \
    -exec rm -rf {} +

echo "${LOG_TAG} pruning remote backups older than ${RETENTION_DAYS} days..."
rclone delete "${RCLONE_REMOTE}:${RCLONE_DEST_PATH}" \
    --min-age "${RETENTION_DAYS}d" --rmdirs || true

echo "${LOG_TAG} done."
