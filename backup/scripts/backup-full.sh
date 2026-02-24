#!/usr/bin/env bash
# Full PostgreSQL backup for Infisical Secret Manager
# Runs a full backup to REPO1 (local) then REPO2 (Cloudflare R2).
# Schedule: Every Sunday at 02:00 UTC (see backup/cron/backup-crontab)
#
# Usage:
#   bash /opt/infisical/backup/scripts/backup-full.sh
set -euo pipefail

POSTGRES="infisical-postgres"
STANZA="infisical"
LOG_TAG="[infisical-backup-full]"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }

log "========================================"
log "Starting FULL backup at ${TIMESTAMP}"
log "========================================"

# Verify the postgres container is running
if ! docker inspect "${POSTGRES}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    die "container '${POSTGRES}' is not running. Run: docker compose up -d infisical-postgres"
fi

# Full backup to REPO1 (local, fast)
log "Backing up to REPO1 (local)..."
docker exec "${POSTGRES}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --repo=1 \
        --type=full \
        --log-level-console=info \
        backup
log "REPO1 full backup complete"

# Full backup to REPO2 (Cloudflare R2, offsite)
log "Backing up to REPO2 (Cloudflare R2)..."
docker exec "${POSTGRES}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --repo=2 \
        --type=full \
        --log-level-console=info \
        backup
log "REPO2 full backup complete"

# Print backup info summary
log "Backup info:"
docker exec "${POSTGRES}" pgbackrest --stanza="${STANZA}" info

log "========================================"
log "FULL backup complete"
log "========================================"
