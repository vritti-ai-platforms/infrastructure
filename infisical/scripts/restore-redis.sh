#!/usr/bin/env bash
# Interactive Redis restore for Infisical Secret Manager
#
# Restores Redis from a local .rdb.gz backup or downloads from Cloudflare R2.
# Note: Redis in Infisical is NOT the source of truth for secrets (those are
# in PostgreSQL). Restoring Redis recovers session caches and pending job queues.
#
# Usage:
#   bash /opt/infisical/scripts/restore-redis.sh
set -euo pipefail

# Load backup env vars
BACKUP_ENV_FILE="/opt/infisical/.env.backup"
if [[ -f "${BACKUP_ENV_FILE}" ]]; then
    set -a; source "${BACKUP_ENV_FILE}"; set +a
fi

REDIS_CONTAINER="${REDIS_CONTAINER:-infisical-redis}"
BACKUP_DIR="${REDIS_BACKUP_LOCAL_DIR:-/opt/vritti/backups/infisical/redis}"
R2_BUCKET="${BACKREST_R2_BUCKET:-infisical-backups}"
R2_ENDPOINT="${BACKREST_R2_ENDPOINT:-}"
R2_ACCESS_KEY="${BACKREST_R2_ACCESS_KEY:-}"
R2_SECRET_KEY="${BACKREST_R2_SECRET_KEY:-}"
LOG_TAG="[infisical-restore-redis]"

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }
warn() { echo "${LOG_TAG} WARN: $*"; }

echo ""
echo "================================================================"
echo " Infisical Redis Restore"
echo "================================================================"
echo ""

echo "Local Redis backups in ${BACKUP_DIR}:"
ls -lh "${BACKUP_DIR}"/redis-dump-*.rdb.gz 2>/dev/null || echo "  (none found locally)"
echo ""
read -rp "Enter path to local .rdb.gz file, or press Enter to download from R2: " LOCAL_FILE

if [[ -z "${LOCAL_FILE}" ]]; then
    # Download from R2
    if ! command -v rclone >/dev/null 2>&1; then
        die "rclone is not installed. Install it or provide a local file path."
    fi
    [[ -n "${R2_ENDPOINT}" ]] || die "BACKREST_R2_ENDPOINT not set in ${BACKUP_ENV_FILE}"

    echo ""
    echo "Available Redis backups on R2 (${R2_BUCKET}/redis/):"
    rclone ls ":s3:${R2_BUCKET}/redis/" \
        --s3-provider=Cloudflare \
        --s3-region=auto \
        --s3-endpoint="${R2_ENDPOINT}" \
        --s3-access-key-id="${R2_ACCESS_KEY}" \
        --s3-secret-access-key="${R2_SECRET_KEY}" \
        --filter="+ redis-dump-*.rdb.gz" \
        --filter="- *" \
        2>/dev/null || die "Could not list R2 backups. Check R2 credentials."

    echo ""
    read -rp "Enter filename to download (e.g. redis-dump-20240615T020000Z.rdb.gz): " R2_FILENAME
    [[ -n "${R2_FILENAME}" ]] || die "Filename cannot be empty"

    LOCAL_FILE="/tmp/${R2_FILENAME}"
    log "Downloading ${R2_FILENAME} from R2..."
    rclone copy \
        ":s3:${R2_BUCKET}/redis/${R2_FILENAME}" \
        /tmp/ \
        --s3-provider=Cloudflare \
        --s3-region=auto \
        --s3-endpoint="${R2_ENDPOINT}" \
        --s3-access-key-id="${R2_ACCESS_KEY}" \
        --s3-secret-access-key="${R2_SECRET_KEY}"
    log "Downloaded to ${LOCAL_FILE}"
fi

[[ -f "${LOCAL_FILE}" ]] || die "File not found: ${LOCAL_FILE}"

# Decompress if gzipped
DUMP_FILE="${LOCAL_FILE}"
if [[ "${LOCAL_FILE}" == *.gz ]]; then
    DUMP_FILE="${LOCAL_FILE%.gz}"
    gunzip -c "${LOCAL_FILE}" > "${DUMP_FILE}"
    log "Decompressed to ${DUMP_FILE}"
fi

# Final confirmation
echo ""
warn "THIS WILL STOP REDIS AND OVERWRITE THE CURRENT REDIS DATA."
warn "Active sessions and pending job queues will be replaced."
echo ""
read -rp "Type CONFIRM (all caps) to proceed: " ANSWER
[[ "${ANSWER}" == "CONFIRM" ]] || { log "Restore cancelled by user."; exit 0; }

# Stop Redis
log "Stopping Redis container..."
docker stop "${REDIS_CONTAINER}"

# Copy RDB into volume
log "Copying RDB file into Redis data volume..."
DUMP_DIR=$(dirname "${DUMP_FILE}")
DUMP_NAME=$(basename "${DUMP_FILE}")
docker run --rm \
    -v infisical-redis-data:/data \
    -v "${DUMP_DIR}:/restore_src:ro" \
    busybox \
    sh -c "cp /restore_src/${DUMP_NAME} /data/dump.rdb && chmod 644 /data/dump.rdb"
log "RDB installed in volume"

# Start Redis (it will load dump.rdb on startup)
log "Starting Redis container..."
docker start "${REDIS_CONTAINER}"

# Cleanup temp decompress if we created it
if [[ "${DUMP_FILE}" != "${LOCAL_FILE}" && "${DUMP_FILE}" == /tmp/* ]]; then
    rm -f "${DUMP_FILE}"
fi

echo ""
log "Redis restore complete. Redis will load the RDB file on startup."
log "Monitor: docker logs -f ${REDIS_CONTAINER}"
