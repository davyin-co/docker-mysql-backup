#!/bin/bash
export PATH="$PATH:/root/.local/bin"

# #### Pre Script (tiredofit/db-backup 4.x signature)
# #### $1=DB_TYPE
# #### $2=DB_HOST
# #### $3=DB_NAME
# #### $4=BACKUP_START_TIME
# #### $5=BACKUP_FILENAME

mkdir -p "${DEFAULT_FILESYSTEM_PATH}/$3"

# Cheap sanity log so users can confirm what the strip-cache hook will do for
# the upcoming dump. The actual filtering happens in rotate-dbbackups.sh
# (post-hook) since the file isn't on disk yet here.
if [ "${DB01_STRIP_CACHE_DATA:-${STRIP_CACHE_DATA:-${DEFAULT_STRIP_CACHE_DATA:-FALSE}}}" = "TRUE" ] ; then
    echo "[pre-backup] strip-cache ENABLED for db='$3' tables='${DB01_STRIP_CACHE_TABLES:-${STRIP_CACHE_TABLES:-${DEFAULT_STRIP_CACHE_TABLES:-cache_%,sessions,watchdog,queue,batch,flood,http_client_log}}}'" >&2
else
    echo "[pre-backup] strip-cache DISABLED for db='$3'" >&2
fi
