#!/usr/bin/env bash
# One-time PostgreSQL 16 -> 18.4 migration for the Infisical stack.
#
# WHY THIS EXISTS: the on-disk data format is major-version-specific. Pointing the 18.4 image at
# the existing PG16 data volume makes Postgres refuse to start ("database files are incompatible
# with server"). So this is a logical dump/restore, run DELIBERATELY once — never by the recurring
# deploy (which just uses the new image and assumes the data dir already matches).
#
# Run ON the Infisical VM, from /opt/infisical, BEFORE the first 18.4 deploy:
#   1) dry run (dump only, non-destructive):      bash scripts/migrate-pg16-to-18.sh
#   2) perform the swap (DESTROYS the PG16 volume, restores into fresh PG18):
#                                                 CONFIRM=yes bash scripts/migrate-pg16-to-18.sh
set -euo pipefail

POSTGRES="infisical-postgres"
DB_USER="${POSTGRES_USER:-infisical}"
DB_NAME="${POSTGRES_DB:-infisical_db}"
STANZA="infisical"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP="/opt/infisical/pg16-dump-${TS}.sql"

log() { echo "[pg16->18] $*"; }
die() { echo "[pg16->18] ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not found"
docker inspect "${POSTGRES}" --format '{{.State.Running}}' 2>/dev/null | grep -q true \
  || die "container '${POSTGRES}' is not running — start the current (PG16) stack first"

VER="$(docker exec "${POSTGRES}" sh -c 'echo "$PG_MAJOR"' 2>/dev/null || true)"
log "current server PG_MAJOR=${VER:-unknown}"

# --- 1) Always dump first (non-destructive) ---
log "dumping the whole cluster (pg_dumpall) -> ${DUMP}"
docker exec -u postgres "${POSTGRES}" pg_dumpall -U "${DB_USER}" > "${DUMP}"
[ -s "${DUMP}" ] || die "dump is empty — aborting, nothing was changed"
log "dump ok ($(wc -l < "${DUMP}") lines, $(du -h "${DUMP}" | cut -f1))"

if [ "${CONFIRM:-no}" != "yes" ]; then
  cat <<EOF

[pg16->18] DRY RUN complete. A logical dump was taken; NOTHING was destroyed.

To perform the migration (this DELETES the PG16 data volume and restores into a fresh PG18):
    CONFIRM=yes bash scripts/migrate-pg16-to-18.sh

Make sure docker-compose.yml already points at postgres-pgbackrest:18.4 and that
image is pushed to GHCR, then re-run with CONFIRM=yes.
EOF
  exit 0
fi

# --- 2) Destructive swap (guarded by CONFIRM=yes) ---
VOL="$(docker volume ls --format '{{.Name}}' | grep -E 'infisical-postgres-data$' | head -1)"
[ -n "${VOL}" ] || die "could not find the infisical-postgres-data volume"
log "target data volume: ${VOL}"

log "stopping the stack"
docker compose down --remove-orphans

log "removing the PG16 data volume ${VOL} (dump is safe at ${DUMP})"
docker volume rm "${VOL}"

log "starting a fresh PG18 postgres (initializes a new data dir)"
docker compose up -d "${POSTGRES}"

log "waiting for health"
for i in $(seq 1 30); do
  [ "$(docker inspect "${POSTGRES}" --format '{{.State.Health.Status}}' 2>/dev/null || echo none)" = "healthy" ] && break
  sleep 3
  [ "$i" = "30" ] && die "postgres did not become healthy"
done

# The image auto-creates ${DB_NAME}; drop it so the dump's CREATE DATABASE restores cleanly.
log "dropping the auto-created empty ${DB_NAME} before restore"
docker exec -u postgres "${POSTGRES}" dropdb -U "${DB_USER}" --if-exists "${DB_NAME}"

log "restoring the dump into the fresh PG18 cluster"
docker exec -i -u postgres "${POSTGRES}" psql -U "${DB_USER}" -d postgres < "${DUMP}"

log "upgrading the pgBackRest stanza to the new PG version"
docker exec -u postgres "${POSTGRES}" pgbackrest --stanza="${STANZA}" stanza-upgrade || \
  log "stanza-upgrade failed (repo may be empty) — run stanza-create manually if needed"

log "bringing up the full stack"
docker compose up -d

log "DONE. Verify Infisical login, then take a fresh full backup:"
log "  docker exec -u postgres ${POSTGRES} pgbackrest --stanza=${STANZA} --type=full backup"
