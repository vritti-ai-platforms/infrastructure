#!/usr/bin/env bash
# Redis backup for Infisical Secret Manager
# Triggers a Redis BGSAVE, copies the RDB file, compresses it,
# and uploads to Cloudflare R2 via rclone.
#
# Redis in Infisical is used for distributed locking (redlock), session
# caching, and job queues — NOT as the source of truth for secrets.
# Secrets live in PostgreSQL. A 24h RPO for Redis is acceptable.
#
# Schedule: Every day at 03:00 UTC (see cron/backup-crontab)
#
# Usage:
#   bash /opt/infisical/scripts/backup-redis.sh
set -euo pipefail

# Load backup env vars if present (R2 credentials, local backup dir)
BACKUP_ENV_FILE="/opt/infisical/.env.backup"
if [[ -f "${BACKUP_ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    set -a; source "${BACKUP_ENV_FILE}"; set +a
fi

REDIS_CONTAINER="${REDIS_CONTAINER:-infisical-redis}"
BACKUP_DIR="${REDIS_BACKUP_LOCAL_DIR:-/opt/vritti/backups/infisical/redis}"
R2_BUCKET="${BACKREST_R2_BUCKET:-infisical-backups}"
R2_ENDPOINT="${BACKREST_R2_ENDPOINT:-}"
R2_ACCESS_KEY="${BACKREST_R2_ACCESS_KEY:-}"
R2_SECRET_KEY="${BACKREST_R2_SECRET_KEY:-}"
RETENTION_DAYS=14
LOG_TAG="[infisical-backup-redis]"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }
warn() { echo "${LOG_TAG} WARN: $*"; }

log "========================================"
log "Starting Redis backup at ${TIMESTAMP}"
log "========================================"

# Verify Redis container is running
if ! docker inspect "${REDIS_CONTAINER}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    die "Redis container '${REDIS_CONTAINER}' is not running"
fi

# Create local backup directory
mkdir -p "${BACKUP_DIR}"

# Trigger a non-blocking background save
log "Triggering Redis BGSAVE..."
docker exec "${REDIS_CONTAINER}" redis-cli BGSAVE > /dev/null

# Poll LASTSAVE timestamp until it advances (save completed)
BEFORE=$(docker exec "${REDIS_CONTAINER}" redis-cli LASTSAVE)
TIMEOUT_SECS=120
ELAPSED=0
while true; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    AFTER=$(docker exec "${REDIS_CONTAINER}" redis-cli LASTSAVE)
    if [[ "${AFTER}" -gt "${BEFORE}" ]]; then
        log "BGSAVE completed (lastsave changed: ${BEFORE} → ${AFTER})"
        break
    fi
    if [[ "${ELAPSED}" -ge "${TIMEOUT_SECS}" ]]; then
        die "BGSAVE did not complete within ${TIMEOUT_SECS} seconds"
    fi
done

# Copy RDB file from container to local backup directory
DEST="${BACKUP_DIR}/redis-dump-${TIMESTAMP}.rdb"
docker cp "${REDIS_CONTAINER}:/data/dump.rdb" "${DEST}"
log "RDB copied to ${DEST}"

# Also copy AOF file if it exists
if docker exec "${REDIS_CONTAINER}" test -f /data/appendonly.aof 2>/dev/null; then
    docker cp "${REDIS_CONTAINER}:/data/appendonly.aof" \
        "${BACKUP_DIR}/redis-aof-${TIMESTAMP}.aof"
    log "AOF copied to ${BACKUP_DIR}/redis-aof-${TIMESTAMP}.aof"
    gzip "${BACKUP_DIR}/redis-aof-${TIMESTAMP}.aof"
fi

# Compress the RDB file
gzip "${DEST}"
DEST="${DEST}.gz"
log "Compressed to ${DEST} ($(du -sh "${DEST}" | cut -f1))"

# Upload to Cloudflare R2 via rclone
if command -v rclone >/dev/null 2>&1 && [[ -n "${R2_ENDPOINT}" ]]; then
    log "Uploading to Cloudflare R2 (${R2_BUCKET}/redis/)..."
    rclone copy \
        "${DEST}" \
        ":s3:${R2_BUCKET}/redis/" \
        --s3-provider=Cloudflare \
        --s3-region=auto \
        --s3-endpoint="${R2_ENDPOINT}" \
        --s3-access-key-id="${R2_ACCESS_KEY}" \
        --s3-secret-access-key="${R2_SECRET_KEY}" \
        --s3-no-check-bucket \
        --verbose
    log "Upload complete: ${R2_BUCKET}/redis/$(basename "${DEST}")"
else
    warn "rclone not found or R2 not configured — storing locally only"
    warn "Install rclone and configure BACKREST_R2_* variables in ${BACKUP_ENV_FILE}"
fi

# Prune local backups older than RETENTION_DAYS
PRUNED=$(find "${BACKUP_DIR}" -name "redis-dump-*.rdb.gz" -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
find "${BACKUP_DIR}" -name "redis-aof-*.aof.gz" -mtime "+${RETENTION_DAYS}" -delete
log "Pruned ${PRUNED} local Redis backups older than ${RETENTION_DAYS} days"

log "========================================"
log "Redis backup complete: $(basename "${DEST}")"
log "========================================"
