#!/bin/bash
# strip-cache-data.sh — sourced from backup_mysql() on tiredofit/db-backup 4.x.
# Sets:
#   extra_backup_opts   — {db}-substituted + per-table --ignore-table args
#   _STRIP_SCHEMA_FILE  — schema-only dump of stripped tables

extra_backup_opts="${backup_job_extra_dump_opts//\{db\}/$db}"
[ "${backup_job_strip_cache_data:-FALSE}" = "TRUE" ] || return 0

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

export MYSQL_PWD="${MYSQL_PWD:-${backup_job_db_pass:-}}"
_strip_tbls=$(${run_as_user} mysql -h "${backup_job_db_host}" \
    -P "${backup_job_db_port}" -u "${backup_job_db_user}" ${mysql_tls_args} \
    -N -B -ss \
    -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='${db}' AND (${_sql})" \
    2>/dev/null) || _strip_tbls=""
[ -n "${_strip_tbls}" ] || return 0

for _t in ${_strip_tbls} ; do
    extra_backup_opts="${extra_backup_opts} --ignore-table=${db}.${_t}"
done

_STRIP_SCHEMA_FILE="${TEMP_PATH}/${backup_job_filename}.schema_prefix"
${run_as_user} mysqldump --no-data --skip-comments --skip-add-drop-table \
    --skip-add-locks --skip-tz-utc --compact \
    -h "${backup_job_db_host}" -P "${backup_job_db_port}" -u "${backup_job_db_user}" \
    ${mysql_tls_args} ${backup_job_extra_opts} "${db}" ${_strip_tbls} \
    > "${_STRIP_SCHEMA_FILE}" 2>/dev/null || rm -f "${_STRIP_SCHEMA_FILE}"
export _STRIP_SCHEMA_FILE