#!/bin/bash
export PATH="$PATH:/root/.local/bin"

# #### Post Script (tiredofit/db-backup 4.x signature)
# #### $1=EXIT_CODE
# #### $2=DB_TYPE
# #### $3=DB_HOST
# #### $4=DB_NAME (the dump's owner database)
# #### $5=BACKUP_START_TIME
# #### $6=BACKUP_FINISH_TIME
# #### $7=BACKUP_TOTAL_TIME
# #### $8=BACKUP_FILENAME   <-- file under ${DEFAULT_FILESYSTEM_PATH}
# #### $9=BACKUP_FILESIZE
# #### $10=HASH (if CHECKSUM enabled)
# #### $11=MOVE_EXIT_CODE

. /venv/bin/activate

# -----------------------------------------------------------------------------
# Strip Drupal transient tables (cache_*, sessions, watchdog, ...) BEFORE rotate
# so rotated archives don't carry rebuildable row data.
#
# We do it HERE (post-hook) rather than via -apply-strip-cache-patch.py because
# tiredofit/db-backup 4.1.100 renamed EXTRA_DUMP_OPTS → EXTRA_BACKUP_OPTS and
# switched mysqldump from a bare 'mysqldump' to '${_mysql_prefix}${_mysql_bin_prefix}dump'
# (i.e. mariadb-dump / mysql-dump), so the patcher's anchors never resolve and
# it silently no-ops — the env vars DEFAULT_STRIP_CACHE_DATA / DB##_STRIP_CACHE_DATA
# are then unread on 4.1.100. See commit 248d065.
#
# Env precedence (matches 4.x semantics: per-instance overrides DEFAULT first):
#     DB01_STRIP_CACHE_DATA    →    DEFAULT_STRIP_CACHE_DATA    →    FALSE
#     DB01_STRIP_CACHE_TABLES  →    DEFAULT_STRIP_CACHE_TABLES  →    hard-coded default
#
# To disable, set STRIP_CACHE_DATA=FALSE (or DB##_STRIP_CACHE_DATA=FALSE).
# To customize the table list, override STRIP_CACHE_TABLES (or DB##_STRIP_CACHE_TABLES).
# Tables support a trailing % wildcard (matches LIKE 'prefix%'); other entries are exact.
# -----------------------------------------------------------------------------

_strip_enable="${DB01_STRIP_CACHE_DATA:-${STRIP_CACHE_DATA:-${DEFAULT_STRIP_CACHE_DATA:-FALSE}}}"
_strip_tables="${DB01_STRIP_CACHE_TABLES:-${STRIP_CACHE_TABLES:-${DEFAULT_STRIP_CACHE_TABLES:-cache_%,sessions,watchdog,queue,batch,flood,http_client_log}}}"

if [ "${_strip_enable}" = "TRUE" ] && [ -n "${_strip_tables}" ] ; then
    _src="${DEFAULT_FILESYSTEM_PATH}/$8"
    if [ -f "${_src}" ] ; then
        # Build a single extended-regex from STRIP_CACHE_TABLES:
        #   foo%  → ^INSERT INTO `foo<rest>`     (LIKE prefix)
        #   bar   → ^INSERT INTO `bar`
        _pat=""
        IFS=, read -ra _items <<< "${_strip_tables}"
        for _i in "${_items[@]}" ; do
            _i="${_i// /}"
            [ -z "${_i}" ] && continue
            if [[ "${_i}" == *% ]] ; then
                _root="${_i%?}"                    # drop trailing %
                _seg="^INSERT INTO \`${_root}[^\`]*\`"
            else
                _seg="^INSERT INTO \`${_i}\`"
            fi
            if [ -z "${_pat}" ] ; then
                _pat="${_seg}"
            else
                _pat="${_pat}|${_seg}"
            fi
        done

        if [ -n "${_pat}" ] ; then
            _tmp="${_src}.strip.tmp"
            case "${_src}" in
                *.gz)
                    if gunzip -c "${_src}" | grep -v -E "${_pat}" | gzip > "${_tmp}" ; then
                        mv "${_tmp}" "${_src}"
                    else
                        rm -f "${_tmp}"
                        echo "[rotate-dbbackups] WARN: strip-cache failed on ${_src} — leaving dump untouched" >&2
                    fi
                    ;;
                *.sql|*)
                    if grep -v -E "${_pat}" "${_src}" > "${_tmp}" ; then
                        mv "${_tmp}" "${_src}"
                    else
                        rm -f "${_tmp}"
                        echo "[rotate-dbbackups] WARN: strip-cache failed on ${_src} — leaving dump untouched" >&2
                    fi
                    ;;
            esac
        fi
    fi
fi

# --- Original behavior: move each dump into its own per-db dir, then rotate ---
mv "${DEFAULT_FILESYSTEM_PATH}/$8" "${DEFAULT_FILESYSTEM_PATH}/$4"
rotate-backups $ROTATE_OPTIONS "${DEFAULT_FILESYSTEM_PATH}/$4"
