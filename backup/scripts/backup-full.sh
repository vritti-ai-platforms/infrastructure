#!/usr/bin/env bash
# Full PostgreSQL backup for Infisical Secret Manager
# Backs up to REPO1 (local) and REPO2 (Cloudflare R2) in a single pass.
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

# Full backup to all repos in a single pass (reads DB once, writes to REPO1 + REPO2 simultaneously)
log "Backing up to REPO1 (local) + REPO2 (Cloudflare R2)..."
docker exec -u postgres "${POSTGRES}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --type=full \
        --log-level-console=info \
        backup
log "Full backup complete (both repos)"

# Print backup info summary
log "Backup info:"
docker exec -u postgres "${POSTGRES}" pgbackrest --stanza="${STANZA}" info

log "========================================"
log "FULL backup complete"
log "========================================"
