# Overview
docker based mysql backup, with backup stratigy supports.
Based on 
* [databacker mysql-backup](https://github.com/databacker/mysql-backup)
* [rotate backups](https://rotate-backups.readthedocs.io/en/latest/)
* Inspired by [Auto purge of older backups](https://github.com/databacker/mysql-backup/issues/9)

## Usage:
docker-compose example:
```yaml
version: '2.1'
services:
  backup:
    image: davyinsa/mysql-backup
    restart: always
    volumes:
     - /local/file/path:/db
    env:
     - DB_DUMP_TARGET=/db
     - DB_SERVER=mysql_db
     - DB_USER=user123
     - DB_PASS=pass123
     - ROTATE_OPTIONS=--daily=7 --weekly=4 --monthly=3 --prefer-recent
     - DB_DUMP_BY_SCHEMA=true
     - RUN_ONCE=true
     #- DB_DUMP_CRON="20, 2, * * *"
     - DB_DUMP_FREQ=60
     - DB_DUMP_BEGIN=2330
     
```