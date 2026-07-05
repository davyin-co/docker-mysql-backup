#!/bin/bash
# strip-cache-data.sh
#
# Source from tiredofit/db-backup's backup_mysql(). Sets:
#   extra_backup_opts   — {db} substituted + per-table --ignore-table args
#   _STRIP_SCHEMA_FILE  — schema-only dump of stripped tables, prepended to
#                         the main dump by apply-strip-cache-patch.py
#
# Two pieces of behaviour:
#   1. {db} placeholder substitution — equivalent of
#      github.com/nfrastack/container-db-backup PR #477.
#   2. STRIP_CACHE_DATA-driven transient-table stripping for Drupal (cache_*,
#      sessions, watchdog, queue, batch, flood, http_client_log). The CSV list
#      accepts '%' as a LIKE prefix; bare names are exact matches. An
#      information_schema query expands them per-DB, so Drupal table prefixes
#      and per-site customisations don't need to be enumerated manually.

extra_backup_opts="${backup_job_extra_backup_opts//\{db\}/$db}"
[ "${backup_job_strip_cache_data:-FALSE}" = "TRUE" ] || return 0

# Translate STRIP_CACHE_TABLES (CSV; '%' = LIKE prefix) into a WHERE fragment.
_sql=""
IFS=, read -ra _items <<< "${backup_job_strip_cache_tables:-cache_%,sessions,watchdog,queue,batch,flood,http_client_log}"
for _i in "${_items[@]}" ; do
    _i="${_i// /}"
    case "${_i}" in
        *%) _sql="${_sql:+${_sql} OR }TABLE_NAME LIKE '${_i//%/}%'";;
        *)  _sql="${_sql:+${_sql} OR }TABLE_NAME='${_i}'";;
    esac
done
[ -n "${_sql}" ] || return 0

# Enumerate matching tables in the current DB. MYSQL_PWD is normally exported
# upstream in parse_variables(); we re-export here so older base images (or
# tests) that don't pre-set it still work, and so mysqldump below also picks
# it up.
export MYSQL_PWD="${MYSQL_PWD:-${backup_job_db_pass:-}}"
_strip_tbls=$(${run_as_user} mysql -h "${backup_job_db_host}" \
    -P "${backup_job_db_port}" -u "${backup_job_db_user}" ${mysql_tls_args} \
    -N -B -ss \
    -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='${db}' AND (${_sql})" \
    2>/dev/null) || _strip_tbls=""
[ -n "${_strip_tbls}" ] || return 0

# Tell the main mysqldump to skip those tables entirely.
for _t in ${_strip_tbls} ; do
    extra_backup_opts="${extra_backup_opts} --ignore-table=${db}.${_t}"
done

# Schema-only dump of the stripped tables; the patch prepends this file to
# the main dump so CREATE TABLE statements survive while INSERTs do not.
_STRIP_SCHEMA_FILE="${temporary_directory}/${backup_job_filename}.schema_prefix"
${run_as_user} ${_mysql_prefix}mysqldump --no-data --skip-comments \
    --skip-add-drop-table --skip-add-locks --skip-tz-utc --compact \
    -h "${backup_job_db_host}" -P "${backup_job_db_port}" -u "${backup_job_db_user}" \
    ${mysql_tls_args} ${backup_job_extra_opts} "${db}" ${_strip_tbls} \
    > "${_STRIP_SCHEMA_FILE}" 2>/dev/null || rm -f "${_STRIP_SCHEMA_FILE}"
export _STRIP_SCHEMA_FILE