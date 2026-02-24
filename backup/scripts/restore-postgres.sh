#!/usr/bin/env bash
# Interactive PostgreSQL restore for Infisical Secret Manager
#
# Supports:
#   - Restore from REPO1 (local — fastest) or REPO2 (Cloudflare R2 — disaster recovery)
#   - Latest backup restore or Point-in-Time Recovery (PITR)
#
# IMPORTANT: This script stops Infisical and the database. Plan for downtime.
# All data written after the target backup timestamp will be LOST.
#
# Usage:
#   bash /opt/infisical/backup/scripts/restore-postgres.sh
set -euo pipefail

SIDECAR="infisical-pgbackrest"
DB_CONTAINER="infisical-postgres"
APP_CONTAINER="infisical"
STANZA="infisical"
WORK_DIR="/opt/infisical"
LOG_TAG="[infisical-restore-pg]"

log()  { echo "${LOG_TAG} $(date -u +%H:%M:%SZ) $*"; }
die()  { echo "${LOG_TAG} ERROR: $*" >&2; exit 1; }
warn() { echo "${LOG_TAG} WARN: $*"; }

echo ""
echo "================================================================"
echo " Infisical PostgreSQL Restore"
echo "================================================================"
echo ""

# Verify sidecar is running
if ! docker inspect "${SIDECAR}" --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
    die "sidecar container '${SIDECAR}' is not running"
fi

# Show available backups
echo "--- REPO1 (local) backup info ---"
docker exec "${SIDECAR}" pgbackrest --stanza="${STANZA}" --repo=1 info 2>/dev/null \
    || warn "REPO1 not accessible or no backups found"
echo ""
echo "--- REPO2 (Cloudflare R2) backup info ---"
docker exec "${SIDECAR}" pgbackrest --stanza="${STANZA}" --repo=2 info 2>/dev/null \
    || warn "REPO2 not accessible or no backups found"
echo ""

# Prompt: repo selection
read -rp "Restore from which repo? [1 = local (fast), 2 = Cloudflare R2 (DR)]: " REPO
[[ "${REPO}" =~ ^[12]$ ]] || die "Invalid repo selection: '${REPO}'. Must be 1 or 2."
REPO_NAME=$([ "${REPO}" = "1" ] && echo "local (REPO1)" || echo "Cloudflare R2 (REPO2)")
log "Selected: ${REPO_NAME}"

# Prompt: PITR or latest
echo ""
read -rp "Restore to latest backup? [y = yes, n = specify a PITR target time]: " USE_LATEST
PITR_TARGET=""
RESTORE_TYPE="default"
if [[ "${USE_LATEST}" != "y" ]]; then
    echo "Enter target time in UTC format: YYYY-MM-DD HH:MM:SS"
    echo "Example: 2024-06-15 14:30:00"
    read -rp "PITR target time: " PITR_TARGET
    [[ -n "${PITR_TARGET}" ]] || die "PITR target cannot be empty"
    RESTORE_TYPE="time"
    log "PITR target: ${PITR_TARGET}"
fi

# Final confirmation
echo ""
echo "================================================================"
warn "THIS WILL STOP INFISICAL AND RESTORE OVER EXISTING DATABASE DATA."
warn "All data written after the backup/PITR target will be LOST."
echo ""
echo "  Repo:   ${REPO_NAME}"
echo "  Type:   ${RESTORE_TYPE}"
[ -n "${PITR_TARGET}" ] && echo "  Target: ${PITR_TARGET}"
echo "================================================================"
echo ""
read -rp "Type CONFIRM (all caps) to proceed: " ANSWER
[[ "${ANSWER}" == "CONFIRM" ]] || { log "Restore cancelled by user."; exit 0; }

# --- Stop application and database ---
log "Stopping Infisical application..."
docker stop "${APP_CONTAINER}" 2>/dev/null || warn "${APP_CONTAINER} was not running"

log "Stopping PostgreSQL..."
docker stop "${DB_CONTAINER}" 2>/dev/null || warn "${DB_CONTAINER} was not running"

# --- Clear the data directory ---
# pgBackRest delta restore can work without clearing, but explicit clear
# ensures no orphaned files from a different backup timeline.
log "Clearing PostgreSQL data directory (infisical-postgres-data volume)..."
docker run --rm \
    -v infisical-postgres-data:/data \
    busybox \
    sh -c "rm -rf /data/*"
log "Data directory cleared"

# --- Build restore command ---
RESTORE_ARGS=(
    "--stanza=${STANZA}"
    "--repo=${REPO}"
    "--delta"
)

if [[ "${RESTORE_TYPE}" == "time" ]]; then
    RESTORE_ARGS+=(
        "--type=time"
        "--target=${PITR_TARGET}"
        "--target-action=promote"
    )
fi

# --- Run pgBackRest restore ---
log "Running pgBackRest restore (this may take several minutes)..."
docker exec "${SIDECAR}" pgbackrest "${RESTORE_ARGS[@]}" restore
log "pgBackRest restore operation complete"

# --- Start the database ---
log "Starting PostgreSQL..."
docker start "${DB_CONTAINER}"

log "Waiting for PostgreSQL to accept connections..."
TIMEOUT=120
ELAPSED=0
while ! docker exec "${DB_CONTAINER}" pg_isready -U infisical -d infisical_db >/dev/null 2>&1; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
        die "PostgreSQL did not become ready within ${TIMEOUT}s. Check: docker logs ${DB_CONTAINER}"
    fi
done
log "PostgreSQL is ready"

# --- Run database migrations ---
# After restoring from a backup, the schema may be behind the current application
# version. Running migrations is safe (idempotent via infisical_migrations table).
log "Running Infisical database migrations (infisical_migrations table)..."
if docker exec "${DB_CONTAINER}" \
    psql -U infisical -d infisical_db -c "SELECT 1" >/dev/null 2>&1; then
    # Let the Infisical container run migrations on startup
    log "Migrations will run automatically when Infisical starts"
else
    warn "Could not connect to database. Check configuration before starting Infisical."
fi

# --- Start the application ---
log "Starting Infisical application..."
docker start "${APP_CONTAINER}"

echo ""
echo "================================================================"
log "Restore complete. Monitor application health:"
log "  docker logs -f ${APP_CONTAINER}"
log "  docker inspect ${APP_CONTAINER} --format='{{.State.Health.Status}}'"
echo "================================================================"
