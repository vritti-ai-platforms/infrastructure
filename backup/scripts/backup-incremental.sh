#!/usr/bin/env bash
# Incremental PostgreSQL backup for Infisical Secret Manager
# Runs an incremental backup to REPO1 (local) then REPO2 (Cloudflare R2).
# Requires a prior full backup to exist in each repo.
# Schedule: Mon–Sat at 02:00 UTC (see backup/cron/backup-crontab)
#
# Usage:
#   bash /opt/infisical/backup/scripts/backup-incremental.sh
set -euo pipefail

SIDECAR="infisical-pgbackrest"
STANZA="infisical"
LOG_TAG="[infisical-backup-incr]"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }

log "========================================"
log "Starting INCREMENTAL backup at ${TIMESTAMP}"
log "========================================"

# Verify the sidecar container is running
if ! docker inspect "${SIDECAR}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    die "sidecar container '${SIDECAR}' is not running. Run: docker compose up -d infisical-pgbackrest"
fi

# Incremental backup to REPO1
log "Backing up to REPO1 (local)..."
docker exec "${SIDECAR}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --repo=1 \
        --type=incr \
        --log-level-console=info \
        backup
log "REPO1 incremental backup complete"

# Incremental backup to REPO2
log "Backing up to REPO2 (Cloudflare R2)..."
docker exec "${SIDECAR}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --repo=2 \
        --type=incr \
        --log-level-console=info \
        backup
log "REPO2 incremental backup complete"

log "========================================"
log "INCREMENTAL backup complete"
log "========================================"
