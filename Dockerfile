FROM tiredofit/db-backup
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

COPY scripts/rotate-dbbackups.sh /assets/scripts/post/
COPY scripts/pre-backup.sh /assets/scripts/pre/

RUN apk add --no-cache py3-pip && \ 
    pip3 install --upgrade pip && \ 
    pip3 install rotate-backups && \
    chmod +x /assets/scripts/post/rotate-dbbackups.sh /assets/scripts/pre/pre-backup.sh && \
    echo "$TIMEZONE" | tee /etc/timezone

