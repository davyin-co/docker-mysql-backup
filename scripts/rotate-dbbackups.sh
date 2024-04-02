#!/bin/bash
export PATH="$PATH:/root/.local/bin"

# #### Example Post Script
# # #### (=EXIT_CODE (After running backup routine)
# # #### [=DB_TYPE (Type of Backup)
# # #### {=DB_HOST (Backup Host)
# # #### #4=DB_NAME (Name of Database backed up
# # #### $5=BACKUP START TIME (Seconds since Epoch)
# # #### $6=BACKUP FINISH TIME (Seconds since Epoch)
# # #### $7=BACKUP TOTAL TIME (Seconds between Start and Finish)
# # #### $8=BACKUP FILENAME (Filename)
# # #### $9=BACKUP FILESIZE
# # #### (0=HASH (If CHECKSUM enabled)))}])

## mv each db to own dir, so that rotate-backups can works good on each files.

mv ${DB_DUMP_TARGET}/$8 ${DB_DUMP_TARGET}/$4
/usr/bin/rotate-backups $ROTATE_OPTIONS ${DB_DUMP_TARGET}/$4
