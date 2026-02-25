#!/usr/bin/env bash
# Verify backup health for Infisical Secret Manager
# Checks WAL archiving is working and backup age is within threshold.
#
# Exit codes:
#   0  All checks passed
#   1  Warning (backup older than threshold)
#   2  Error (WAL check failed or no backups found)
#
# Schedule: Every day at 04:00 UTC (see backup/cron/backup-crontab)
#
# Usage:
#   bash /opt/infisical/backup/scripts/verify-backup.sh
set -euo pipefail

POSTGRES="infisical-postgres"
STANZA="infisical"
MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"
LOG_TAG="[infisical-verify]"
EXIT_CODE=0

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
warn() { echo "${LOG_TAG} WARN: $*"; EXIT_CODE=1; }
err()  { echo "${LOG_TAG} ERROR: $*" >&2; EXIT_CODE=2; }

log "========================================"
log "Starting backup verification"
log "Max allowed backup age: ${MAX_AGE_HOURS}h"
log "========================================"

# Verify postgres container is running
if ! docker inspect "${POSTGRES}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    err "container '${POSTGRES}' is not running"
    exit 2
fi

# --- Check WAL archiving across all repos ---
log "Checking WAL archive connectivity (all repos)..."
if docker exec -u postgres "${POSTGRES}" \
    pgbackrest --stanza="${STANZA}" check \
    --log-level-console=warn 2>&1; then
    log "WAL archive check: OK (REPO1 + REPO2)"
else
    err "WAL archive check FAILED — archive_command may not be working or R2 unreachable"
fi

# --- Check backup age ---
log "Checking backup age..."
INFO_OUTPUT=$(docker exec -u postgres "${POSTGRES}" pgbackrest --stanza="${STANZA}" info 2>&1)
echo "${INFO_OUTPUT}"

# Find the most recent backup stop time in the info output
# Format: "timestamp start/stop: 2026-02-24 13:34:29+00 / 2026-02-24 13:34:38+00"
# || true prevents set -e from exiting if grep finds no match
LAST_STOP=$(echo "${INFO_OUTPUT}" | grep "timestamp start/stop:" | tail -1 | awk '{print $6, $7}' || true)

if [[ -z "${LAST_STOP}" ]]; then
    err "No backups found in any repo — run backup-full.sh to create the first backup"
else
    # Parse timestamp and check age (strip +00 timezone suffix, interpret as UTC)
    LAST_EPOCH=$(date -d "${LAST_STOP%+00} UTC" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))

    log "Most recent backup stop: ${LAST_STOP} (${AGE_HOURS}h ago)"

    if [[ "${AGE_HOURS}" -gt "${MAX_AGE_HOURS}" ]]; then
        warn "BACKUP IS STALE: Last backup was ${AGE_HOURS}h ago (threshold: ${MAX_AGE_HOURS}h)"
        warn "Check cron logs: cat /var/log/infisical-backup.log"
    else
        log "Backup age check: OK (${AGE_HOURS}h < ${MAX_AGE_HOURS}h threshold)"
    fi
fi

log "========================================"
if [[ "${EXIT_CODE}" -eq 0 ]]; then
    log "All checks PASSED"
elif [[ "${EXIT_CODE}" -eq 1 ]]; then
    log "Verification completed with WARNINGS (exit ${EXIT_CODE})"
else
    log "Verification FAILED (exit ${EXIT_CODE})"
fi
log "========================================"

exit "${EXIT_CODE}"
