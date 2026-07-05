#!/usr/bin/env python3
"""
apply-strip-cache-patch.py — injects three code blocks into upstream
/assets/functions/10-db-backup at build time (4.x line only).

If the required anchors aren't found (old image version), exits 0
without modifying the file — the build continues, just without the
strip-cache feature for that image tag.

Idempotent: re-runs bail out at the first sentinel marker.
"""
import re
import sys

TARGET = "/assets/functions/10-db-backup"
MARKERS = (
    ("# >>> STRIP_CACHE_DATA_REGISTER_BEGIN", "# <<< STRIP_CACHE_DATA_REGISTER_END"),
    ("# >>> STRIP_CACHE_DATA_INJECTION_BEGIN", "# <<< STRIP_CACHE_DATA_INJECTION_END"),
    ("# >>> STRIP_CACHE_DATA_POSTDUMP_BEGIN", "# <<< STRIP_CACHE_DATA_POSTDUMP_END"),
)


def main() -> int:
    with open(TARGET, encoding="utf-8") as f:
        src = f.read()

    for begin, _ in MARKERS:
        if begin in src:
            print(f"apply-strip-cache-patch: '{begin}' present, skipping", flush=True)
            return 0

    # ---- A: register STRIP_CACHE_DATA / STRIP_CACHE_TABLES ---------------
    m = re.search(
        r"^(?P<i>[ \t]+)transform_backup_instance_variable "
        r"\"\$\{backup_instance_number\}\" EXTRA_DUMP_OPTS "
        r"backup_job_extra_dump_opts\b",
        src, re.MULTILINE,
    )
    if not m:
        print("apply-strip-cache-patch: EXTRA_DUMP_OPTS anchor not found "
              "(old image), skipping", flush=True)
        return 0
    ai = m.group("i")
    a_begin, a_end = MARKERS[0]
    src = (
        src[: m.end()] + f"\n{ai}{a_begin}\n"
        + f'{ai}transform_backup_instance_variable '
          f'"${{backup_instance_number}}" STRIP_CACHE_DATA '
          f"backup_job_strip_cache_data\n"
        + f'{ai}transform_backup_instance_variable '
          f'"${{backup_instance_number}}" STRIP_CACHE_TABLES '
          f"backup_job_strip_cache_tables\n"
        + f"{ai}{a_end}\n" + src[m.end():]
    )

    # ---- B: source helper + rewrite mysqldump opts token -----------------
    m = re.search(
        r"^(?P<i>[ \t]+)run_as_user \$\{play_fair\} mysqldump[^\n]*",
        src, re.MULTILINE,
    )
    if not m:
        print("apply-strip-cache-patch: mysqldump anchor not found, skipping",
              flush=True)
        return 0
    bi = m.group("i")
    b_begin, b_end = MARKERS[1]
    patched_line = m.group(0).replace(
        "${backup_job_extra_dump_opts}", "${extra_backup_opts}"
    )

    src = (
        src[: m.start()]
        + f"{bi}{b_begin}\n{bi}source /assets/strip-cache-data.sh\n{bi}{b_end}\n"
        + patched_line + src[m.end():]
    )
    # Rewrite any OTHER mysqldump lines (combined --databases branch).
    src = re.sub(
        r"^(?P<i>[ \t]+)run_as_user \$\{play_fair\} mysqldump[^\n]*",
        lambda mm: mm.group(0).replace(
            "${backup_job_extra_dump_opts}", "${extra_backup_opts}"
        ),
        src, flags=re.MULTILINE,
    )

    # ---- C: prepend schema-only dump after exit_code ---------------------
    # Re-find the *first* mysqldump line in the patched src (avoids offset
    # arithmetic from the injection that was inserted before it).
    first_after = re.search(
        r"run_as_user \$\{play_fair\} mysqldump[^\n]*",
        src, re.MULTILINE,
    )
    if not first_after:
        print("apply-strip-cache-patch: mysqldump line not found after "
              "patch, skipping", flush=True)
        return 0
    rest = src[first_after.end():]
    exit_m = re.search(r"^(?P<i>[ \t]+)exit_code=", rest, re.MULTILINE)
    if not exit_m:
        print("apply-strip-cache-patch: exit_code line after mysqldump not "
              "found, skipping", flush=True)
        return 0
    ci = exit_m.group("i")
    abs_end = first_after.end() + exit_m.end()
    c_begin, c_end = MARKERS[2]
    src = (
        src[:abs_end]
        + f"\n{ci}{c_begin}\n"
        + f'{ci}if [ -n "${{_STRIP_SCHEMA_FILE:-}}" ] && '
          f'[ -f "${{_STRIP_SCHEMA_FILE}}" ] ; then\n'
        + f'{ci}    _main_dump="${{TEMP_PATH}}/${{backup_job_filename}}"\n'
        + f'{ci}    if [ -f "${{_main_dump}}" ] ; then\n'
        + f'{ci}        cat "${{_STRIP_SCHEMA_FILE}}" "${{_main_dump}}" '
          f'> "${{_main_dump}}.combined"\n'
        + f'{ci}        mv "${{_main_dump}}.combined" "${{_main_dump}}"\n'
        + f'{ci}    fi\n'
        + f'{ci}    rm -f "${{_STRIP_SCHEMA_FILE}}"\n'
        + f'{ci}    unset _STRIP_SCHEMA_FILE\n'
        + f'{ci}fi\n'
        + f"{ci}{c_end}\n"
        + src[abs_end:]
    )

    with open(TARGET, "w", encoding="utf-8") as f:
        f.write(src)
    print("apply-strip-cache-patch: patched successfully", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())