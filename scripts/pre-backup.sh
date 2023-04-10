#!/bin/bash

# #### Example Pre Script
# #### $1=DB_TYPE (Type of Backup)
# #### $2=DB_HOST (Backup Host)
# #### $3=DB_NAME (Name of Database backed up
# #### $4=BACKUP START TIME (Seconds since Epoch)ff
# #### $5=BACKUP FILENAME (Filename)
mkdir -p ${DB_DUMP_TARGET}/$3
