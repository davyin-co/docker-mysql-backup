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
        # Build a perl regex alternation from STRIP_CACHE_TABLES:
        #   foo%  → foo[^`]+                       (LIKE prefix on table name)
        #   bar   → bar
        # Then join with | for use in the perl state-machine below.
        _perl_pat=""
        IFS=, read -ra _items <<< "${_strip_tables}"
        for _i in "${_items[@]}" ; do
            _i="${_i// /}"
            [ -z "${_i}" ] && continue
            if [[ "${_i}" == *% ]] ; then
                _root="${_i%?}"                    # drop trailing %
                _seg="${_root}[^\`]+"
            else
                _seg="${_i}"
            fi
            if [ -z "${_perl_pat}" ] ; then
                _perl_pat="${_seg}"
            else
                _perl_pat="${_perl_pat}|${_seg}"
            fi
        done

        if [ -n "${_perl_pat}" ] ; then
            _tmp="${_src}.strip.tmp"

            # Strip transient-table data via a perl state machine. We need a
            # state machine (not just `grep -v ^INSERT INTO`) because
            # mariadb-dump's compact mode OMITS the `INSERT INTO` keyword for
            # tables that contain longblob/longtext columns (e.g. cache_*),
            # emitting just the trailing VALUES tuples inside a
            # LOCK TABLES ... UNLOCK TABLES block. Plain single-line grep -v
            # would silently leave those orphan tuples in the dump and break
            # any subsequent `restore`. See CLAUDE.md / project memory for the
            # full bug report.
            _perl_filter='
                BEGIN { $in_lock = 0; $in_insert = 0 }
                # State A: inside a LOCK TABLES block for a strip-table → drop
                #         every line until the matching UNLOCK TABLES.
                if ($in_lock) {
                    if (/^UNLOCK TABLES/) { $in_lock = 0 }
                    next
                }
                # Entering a strip-table LOCK block.
                if (/^LOCK TABLES `('"${_perl_pat}"')` WRITE/) {
                    $in_lock = 1; next
                }
                # State B: inside a multi-row INSERT INTO `<strip-tbl>`
                #         VALUES (...),(...);  → drop leading INSERT and
                #         trailing `(...)` tuples.
                if ($in_insert) {
                    if (/^\(/) { next }
                    $in_insert = 0
                }
                # Entering a strip-table INSERT (covers non-longblob tables
                # like sessions/watchdog/queue/batch/flood/http_client_log).
                if (/^INSERT INTO `('"${_perl_pat}"')`/) {
                    $in_insert = 1; next
                }
                print
            '

            case "${_src}" in
                *.gz)
                    if gunzip -c "${_src}" | perl -ne "${_perl_filter}" | gzip > "${_tmp}" ; then
                        mv "${_tmp}" "${_src}"
                    else
                        rm -f "${_tmp}"
                        echo "[rotate-dbbackups] WARN: strip-cache failed on ${_src} — leaving dump untouched" >&2
                    fi
                    ;;
                *.sql|*)
                    if perl -ne "${_perl_filter}" "${_src}" > "${_tmp}" ; then
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
