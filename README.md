# 简介
基于docker的MySQL数据库备份程序, 支持高级备份策略设置.
该镜像包含： 
* [databacker mysql-backup](https://github.com/databacker/mysql-backup)
* [rotate backups](https://rotate-backups.readthedocs.io/en/latest/)
* Inspired by [Auto purge of older backups](https://github.com/databacker/mysql-backup/issues/9)

## Usage:
docker-compose.yml 例子，周期性备份:
```yaml
version: "3"
services:
  db-backup-rotate-freq:
    container_name: db-backup-rotate-freq
    #image: tiredofit/db-backup
    image: davyinsa/mysql-backup-rotate
    volumes:
      - ./backup-interval:/backup
    #restart: always
    environment:
     ## 备份间隔时间，以分为单位,1440就是每天一个备份。
     - DB_DUMP_FREQ=1440
     ## 如下配置，保留最近7天（每天一个备份），最近4周（每周一个备份），最近3个月的备份（每个月一个备份）
     - ROTATE_OPTIONS=--daily=7 --weekly=4 --monthly=3 --prefer-recent
      - ROTATE_OPTIONS=--minutely=10 --hourly=5 --daily=7 --weekly=4 --monthly=3 --prefer-recent
      - CONTAINER_ENABLE_MONITORING=FALSE
      - TIMEZONE=Asia/Shanghai
      - BACKUP_LOCATION=FILESYSTEM
      - DB_TYPE=mysql
      - DB_DUMP_TARGET=/backup
      - DB_HOST=mariadb
      - DB_NAME=yanfeng_uat,bjchy_intl
      - DB_NAME_EXCLUDE=mysql
      - DB_USER=root
      - DB_PASS=password
      - DB_CLEANUP_TIME=FALSE
      - ENABLE_CHECKSUM=FALSE
      - COMPRESSION=GZ
      - SPLIT_DB=TRUE
      - SIZE_VALUE=megabytes
      - CREATE_LATEST_SYMLINK=FALSE
      - ENABLE_SMTP=FALSE
      - ENABLE_ZABBIX=FALSE
      - ENABLE_LOGROTATE=FALSE
     
```

docker-compose.yml, 一次性备份（依赖于外部的任务调度系统执行周期性备份任务，不是容器自身执行。例如kubernetes的cronjob）
```yaml
version: "3"
services:
  db-backup-rotate-once:
    container_name: db-backup-rotate-once
    image: davyinsa/mysql-backup-rotate
    volumes:
      - ./backup-once:/backup
    #restart: always
    command:
      - /bin/bash
      - /etc/services.available/10-db-backup/run
      - NOW
    environment:
      - MODE=MANUAL
      - MANUAL_RUN_FOREVER=FALSE
      - CONTAINER_ENABLE_SCHEDULING=FALSE
      - ROTATE_OPTIONS=--minutely=5 --hourly=3 --daily=7 --weekly=4 --monthly=3 --prefer-recent
      - CONTAINER_ENABLE_MONITORING=FALSE
      - TIMEZONE=Asia/Shanghai
      - BACKUP_LOCATION=FILESYSTEM
      - DB_TYPE=mysql
      - DB_DUMP_TARGET=/backup
      - DB_HOST=mariadb
      - DB_NAME=example
      - DB_NAME_EXCLUDE=mysql
      - DB_USER=root
      - DB_PASS=password
      - DB_CLEANUP_TIME=FALSE
      - ENABLE_CHECKSUM=FALSE
      - COMPRESSION=GZ
      - SPLIT_DB=TRUE
      - SIZE_VALUE=megabytes
      - CREATE_LATEST_SYMLINK=FALSE
      - ENABLE_SMTP=FALSE
      - ENABLE_ZABBIX=FALSE
      - ENABLE_LOGROTATE=FALSE
```