ARG VERSION
FROM tiredofit/db-backup:${VERSION}
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

# --- Custom hook scripts (existing) ---------------------------------------
COPY scripts/rotate-dbbackups.sh /assets/scripts/post/
COPY scripts/pre-backup.sh /assets/scripts/pre/

# --- Drupal strip-cache patcher (new) -------------------------------------
# strip-cache-data.sh implements PR nfrastack/container-db-backup#477's
# {db} placeholder substitution plus an extra layer that expands '%'
# wildcards in STRIP_CACHE_TABLES into concrete --ignore-table args and
# prepends schema-only dumps. apply-strip-cache-patch.py idempotently
# injects a `source` call + post-mysqldump prepend block into the
# upstream /assets/functions/10-db-backup's backup_mysql() function.
COPY assets/strip-cache-data.sh /assets/strip-cache-data.sh
COPY assets/apply-strip-cache-patch.py /tmp/apply-strip-cache-patch.py

## https://www.yaolong.net/article/pip-externally-managed-environment/
RUN apk add --no-cache tzdata && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    apk del tzdata && \
    python3 -m venv /venv && \
    . /venv/bin/activate && \
    pip install rotate-backups && \
    chmod +x /assets/scripts/post/rotate-dbbackups.sh \
             /assets/scripts/pre/pre-backup.sh \
             /assets/strip-cache-data.sh && \
    python3 /tmp/apply-strip-cache-patch.py && \
    rm -f /tmp/apply-strip-cache-patch.py && \
    echo "$TIMEZONE" | tee /etc/timezone