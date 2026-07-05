#!/usr/bin/env python3
"""
apply-strip-cache-patch.py — idempotently injects three code blocks into
the upstream /assets/functions/10-db-backup at image build time:

  A. Register STRIP_CACHE_DATA / STRIP_CACHE_TABLES with the upstream
     per-instance variable transform (so DB##_/DB_/DEFAULT_ env vars funnel
     into the internal backup_job_strip_cache_* variables, the same way
     EXTRA_BACKUP_OPTS does today).

  B. Source /assets/strip-cache-data.sh before mysqldump and rewrite the
     ${backup_job_extra_backup_opts} token in the mysqldump command line
     to ${extra_backup_opts}. Equivalent of nfrastack/container-db-backup
     PR #477 ({db} placeholder substitution).

  C. After PIPESTATUS exit_code, prepend the schema-only prefix file
     (set by strip-cache-data.sh when STRIP_CACHE_DATA=TRUE) to the main
     dump so CREATE TABLE statements for stripped tables survive while
     their INSERT statements are dropped.

Each block is wrapped in a sentinel comment pair so re-runs are no-ops.
"""
import re
import sys

TARGET = "/assets/functions/10-db-backup"
MARKERS = {
    "A": ("# >>> STRIP_CACHE_DATA_REGISTER_BEGIN", "# <<< STRIP_CACHE_DATA_REGISTER_END"),
    "B": ("# >>> STRIP_CACHE_DATA_INJECTION_BEGIN", "# <<< STRIP_CACHE_DATA_INJECTION_END"),
    "C": ("# >>> STRIP_CACHE_DATA_POSTDUMP_BEGIN", "# <<< STRIP_CACHE_DATA_POSTDUMP_END"),
}


def find(src, regex, desc):
    """Locate the regex in src; abort the script if missing."""
    m = regex.search(src)
    if not m:
        print(f"apply-strip-cache-patch: anchor '{desc}' not found in {TARGET}",
              file=sys.stderr)
        sys.exit(1)
    return m


def main() -> int:
    with open(TARGET, encoding="utf-8") as f:
        src = f.read()

    # Bail out if any previous run left a sentinel.
    for begin, _ in MARKERS.values():
        if begin in src:
            print(f"apply-strip-cache-patch: '{begin}' already present, skipping",
                  flush=True)
            return 0

    a_begin, a_end = MARKERS["A"]
    # ---- A: register STRIP_CACHE_DATA / STRIP_CACHE_TABLES transforms ----
    em = find(
        src,
        re.compile(
            r"^(?P<indent>[ \t]+)transform_backup_instance_variable "
            r"\"\$\{backup_instance_number\}\" EXTRA_BACKUP_OPTS "
            r"backup_job_extra_backup_opts\b",
            re.MULTILINE,
        ),
        desc="EXTRA_BACKUP_OPTS transform call",
    )
    ai = em.group("indent")
    src = (
        src[:em.end()]
        + f"\n{ai}{a_begin}\n"
        + f'{ai}transform_backup_instance_variable '
          f'"${{backup_instance_number}}" STRIP_CACHE_DATA '
          f"backup_job_strip_cache_data\n"
        + f'{ai}transform_backup_instance_variable '
          f'"${{backup_instance_number}}" STRIP_CACHE_TABLES '
          f"backup_job_strip_cache_tables\n"
        + f"{ai}{a_end}\n"
        + src[em.end():]
    )

    b_begin, b_end = MARKERS["B"]
    # ---- B: source the helper + rewrite mysqldump opts token ------------
    # Match the entire mysqldump invocation line (anchored at `dump`,
    # extending to the line end) so we can rewrite the trailing
    # ${backup_job_extra_backup_opts} token.
    mysqldump_re = re.compile(
        r"^(?P<indent>[ \t]+)run_as_user \$\{play_fair\} "
        r"\$\{_mysql_prefix\}\$\{_mysql_bin_prefix\}dump[^\n]*",
        re.MULTILINE,
    )
    bm = find(src, mysqldump_re, desc="mysqldump invocation")
    bi = bm.group("indent")
    # First mysqldump line gets: sentinel block + the same line with the
    # ${backup_job_extra_backup_opts} token rewritten to ${extra_backup_opts}.
    patched = bm.group(0).replace(
        "${backup_job_extra_backup_opts}", "${extra_backup_opts}"
    )
    src = (
        src[:bm.start()]
        + f"{bi}{b_begin}\n{bi}source /assets/strip-cache-data.sh\n{bi}{b_end}\n"
        + patched
        + src[bm.end():]
    )
    # Any OTHER mysqldump line (the combined --databases branch) just gets
    # the token rewrite, no extra source line.
    src = mysqldump_re.sub(
        lambda mm: mm.group(0).replace(
            "${backup_job_extra_backup_opts}", "${extra_backup_opts}"
        ),
        src,
    )

    c_begin, c_end = MARKERS["C"]
    # ---- C: prepend schema-only dump to the main dump --------------------
    cm = find(
        src,
        re.compile(
            r"^(?P<indent>[ \t]+)exit_code=\$\(\(PIPESTATUS\[0\] \+ "
            r"PIPESTATUS\[1\] \+ PIPESTATUS\[2\]\)\)",
            re.MULTILINE,
        ),
        desc="PIPESTATUS exit_code line",
    )
    ci = cm.group("indent")
    src = (
        src[:cm.end()]
        + f"\n{ci}{c_begin}\n"
        + f'{ci}if [ -n "${{_STRIP_SCHEMA_FILE:-}}" ] && '
          f'[ -f "${{_STRIP_SCHEMA_FILE}}" ] ; then\n'
        + f'{ci}    _main_dump="${{temporary_directory}}/${{backup_job_filename}}"\n'
        + f'{ci}    if [ -f "${{_main_dump}}" ] ; then\n'
        + f'{ci}        cat "${{_STRIP_SCHEMA_FILE}}" "${{_main_dump}}" '
          f'> "${{_main_dump}}.combined"\n'
        + f'{ci}        mv "${{_main_dump}}.combined" "${{_main_dump}}"\n'
        + f'{ci}    fi\n'
        + f'{ci}    rm -f "${{_STRIP_SCHEMA_FILE}}"\n'
        + f'{ci}    unset _STRIP_SCHEMA_FILE\n'
        + f'{ci}fi\n'
        + f"{ci}{c_end}\n"
        + src[cm.end():]
    )

    with open(TARGET, "w", encoding="utf-8") as f:
        f.write(src)
    print("apply-strip-cache-patch: patched successfully", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())