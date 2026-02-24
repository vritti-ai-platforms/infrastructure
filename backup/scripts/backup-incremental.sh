#!/usr/bin/env bash
# Incremental PostgreSQL backup for Infisical Secret Manager
# Backs up to REPO1 (local) and REPO2 (Cloudflare R2) in a single pass.
# Requires a prior full backup to exist in each repo.
# Schedule: Mon–Sat at 02:00 UTC (see backup/cron/backup-crontab)
#
# Usage:
#   bash /opt/infisical/backup/scripts/backup-incremental.sh
set -euo pipefail

POSTGRES="infisical-postgres"
STANZA="infisical"
LOG_TAG="[infisical-backup-incr]"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }

log "========================================"
log "Starting INCREMENTAL backup at ${TIMESTAMP}"
log "========================================"

# Verify the postgres container is running
if ! docker inspect "${POSTGRES}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    die "container '${POSTGRES}' is not running. Run: docker compose up -d infisical-postgres"
fi

# Incremental backup to all repos in a single pass (reads DB once, writes to REPO1 + REPO2 simultaneously)
log "Backing up to REPO1 (local) + REPO2 (Cloudflare R2)..."
docker exec -u postgres "${POSTGRES}" \
    pgbackrest \
        --stanza="${STANZA}" \
        --type=incr \
        --log-level-console=info \
        backup
log "Incremental backup complete (both repos)"

log "========================================"
log "INCREMENTAL backup complete"
log "========================================"
