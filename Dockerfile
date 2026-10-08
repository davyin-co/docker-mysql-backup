# ---------------------------------------------------------------------------
# Frozen 4.x base
#
# Upstream tiredofit/db-backup deleted every 4.x tag from Docker Hub when the
# project moved to nfrastack/db-backup and was rewritten in Go (a shell-less
# scratch binary: no apk, no python, no /assets layout). The last working 4.x
# base is preserved in this repo's own registry as
# davyinsa/mysql-backup-rotate:4.1.100 (built 2026-09-09 from the final
# tiredofit/db-backup:4.1.100) and is pinned here.
#
# The base already contains /venv with rotate-backups, the Asia/Shanghai
# timezone and these hook scripts. The layers below only re-apply the ENV
# defaults and refresh the hook scripts so edits in scripts/ actually ship.
# (Migration to nfrastack/db-backup 5.x is a separate project.)
# ---------------------------------------------------------------------------
ARG BASE_IMAGE=davyinsa/mysql-backup-rotate
ARG BASE_VERSION=4.1.100
FROM ${BASE_IMAGE}:${BASE_VERSION}
ENV ROTATE_OPTIONS="--daily=7 --weekly=4 --monthly=3 --prefer-recent"
#ENV POST_SCRIPT=/assets/scripts/post/rotate-dbbackups.sh
ENV CONTAINER_ENABLE_MONITORING=FALSE
ENV TIMEZONE=Asia/Shanghai
ENV BACKUP_LOCATION=FILESYSTEM
ENV DB_NAME_EXCLUDE=sys,mysql
ENV DB_CLEANUP_TIME=FALSE
ENV ENABLE_CHECKSUM=FALSE
ENV COMPRESSION=GZ
ENV SPLIT_DB=TRUE
ENV SIZE_VALUE=megabytes
ENV ENABLE_SMTP=FALSE
ENV CREATE_LATEST_SYMLINK=FALSE
ENV ENABLE_ZABBIX=FALSE
ENV ENABLE_LOGROTATE=FALSE

ENV DEFAULT_BACKUP_LOCATION=FILESYSTEM
ENV DEFAULT_BACKUP_INTERVAL=1440
ENV DB01_SPLIT_DB=TRUE
ENV DEFAULT_FILESYSTEM_PATH=/backup
ENV DEFAULT_DB_NAME_EXCLUDE=sys,mysql
ENV DEFAULT_DB_CLEANUP_TIME=FALSE
ENV DEFAULT_CHECKSUM=NONE
ENV DEFAULT_COMPRESSION=GZ
ENV DEFAULT_SPLIT_DB=TRUE
ENV DEFAULT_SIZE_VALUE=megabytes
ENV DEFAULT_ENABLE_SMTP=FALSE
ENV DEFAULT_CREATE_LATEST_SYMLINK=FALSE
ENV DEFAULT_ENABLE_ZABBIX=FALSE
ENV DEFAULT_ENABLE_LOGROTATE=FALSE

# --- Drupal transient-table stripping (defaults ON, see README) -----------
# Only the DEFAULT_* form is set: tiredofit/db-backup 4.x's
# transform_backup_instance_variable resolves DEFAULT_FOO as the preferred
# fallback (no log warning). Per-instance overrides use DB##_STRIP_CACHE_DATA
# (e.g. DB01_STRIP_CACHE_DATA=FALSE) and win over this default.
ENV DEFAULT_STRIP_CACHE_DATA=TRUE
ENV DEFAULT_STRIP_CACHE_TABLES=cache_%,sessions,watchdog,queue,batch,flood,http_client_log

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/bin

# --- Custom hook scripts ---------------------------------------------------
# rotate-dbbackups.sh ships the strip-cache perl filter (post-hook) and the
# per-db move + rotate-backups rotation; pre-backup.sh creates the per-db
# directory. Both are refreshed from this repo on every build.
# NOTE: rotate-dbbackups.sh is 100644 in git, so the chmod here is required.
COPY scripts/rotate-dbbackups.sh /assets/scripts/post/
COPY scripts/pre-backup.sh /assets/scripts/pre/
RUN chmod +x /assets/scripts/post/rotate-dbbackups.sh \
             /assets/scripts/pre/pre-backup.sh
