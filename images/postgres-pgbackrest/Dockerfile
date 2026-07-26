# Custom PostgreSQL 18.4 image with pgBackRest installed.
#
# pgBackRest MUST live in the same image as Postgres: `archive_command` runs pgbackrest as the
# postgres OS user INSIDE this container on every WAL segment, and physical backups read PGDATA
# directly. The official postgres image doesn't ship pgBackRest, so we add it. The SAME image is
# reused for backup/restore ops (run via `docker exec`). Pinned to the PG 18 major — the on-disk
# data format is version-specific, so never float `:latest`.
#
# Debian (bookworm) not alpine, because pgBackRest ships in the official PGDG apt repo on Debian.

FROM postgres:18.4-bookworm

# Install pgBackRest from the PostgreSQL Global Development Group apt repo
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
        https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest \
    && rm -rf /var/lib/apt/lists/*

# pgBackRest dirs owned by the postgres user. When Docker mounts a fresh volume at
# /var/lib/pgbackrest it copies this structure (with ownership) in, so archive_command
# (running as the postgres OS user) can write WAL.
RUN mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest /tmp/pgbackrest \
    && chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest /tmp/pgbackrest
