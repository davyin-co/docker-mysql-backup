FROM deitch/mysql-backup
USER root
RUN pip3 install --upgrade pip && pip3 install rotate-backups
COPY rotate-dbbackups.sh /scripts.d/post-backup/rotate-dbbackups.sh
RUN chmod +x /scripts.d/post-backup/rotate-dbbackups.sh
USER appuser

ENTRYPOINT ["/entrypoint"]
