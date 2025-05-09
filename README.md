# 简介

基于docker的MySQL数据库备份程序, 支持高级备份策略设置.
该镜像包含：

* [databacker](https://github.com/tiredofit/docker-db-backup)
* [rotate backups](https://rotate-backups.readthedocs.io/en/latest/)
* Inspired by [Auto purge of older backups](https://github.com/databacker/mysql-backup/issues/9)

## Usage:

!!!由于tiredofit/db-backup 4.x改动较大，尚未经过完整测试验证与适配，暂时使用3-3.12.2!!!

docker-compose.yml 例子，周期性备份:

```yaml
services:
  db-backup-rotate-freq:
    container_name: db-backup-rotate-freq
    #image: tiredofit/db-backup
    image: registry.cn-hangzhou.aliyuncs.com/davyin/mysql-backup-rotate:4.1.17
    volumes:
      - ./backup:/backup
    #restart: always
    environment:
     ## 备份间隔时间，以分为单位,1440就是每天一个备份。
      - DB_DUMP_FREQ=1440
      ## mariadb有自己的client，用这个作区分。如果是mysql，改为mysql
      - DEFAULT_MYSQL_CLIENT=mariadb
     ## 如下配置，保留最近7天（每天一个备份），最近4周（每周一个备份），最近3个月的备份（每个月一个备份）
      - ROTATE_OPTIONS=--daily=7 --weekly=4 --monthly=3 --prefer-recent
      #- ROTATE_OPTIONS=--minutely=10 --hourly=5 --daily=7 --weekly=4 --monthly=3 --prefer-recent
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
services:
  db-backup-rotate-freq-manual:
    container_name: db-backup-rotate-freq-manual
    #image: tiredofit/db-backup
    registry.cn-hangzhou.aliyuncs.com/davyin/mysql-backup-rotate:4.1.17
    volumes:
      - ./backup-interval-manual:/backup
    #restart: always
    command: [backup-now]
    environment:
      - DEFAULT_MYSQL_CLIENT=mariadb
      - MODE=MANUAL
      - CONTAINER_ENABLE_SCHEDULING=FALSE
      - CONTAINER_ENABLE_MONITORING=FALSE
      - MANUAL_RUN_FOREVER=FALSE
      - ROTATE_OPTIONS=--daily=4 --weekly=4 --monthly=3 --prefer-recent
      - DEFAULT_BACKUP_LOCATION=FILESYSTEM
      - DEFAULT_FILESYSTEM_PATH=/backup
      - DB_TYPE=mysql
      - DB_HOST=mariadb
      - DB_NAME=yanfeng_uat,bjchy_intl
      - DB_NAME_EXCLUDE=mysql
      - DB_USER=root
      - DB_PASS=password
      - DB_CLEANUP_TIME=FALSE
      - ENABLE_CHECKSUM=FALSE
      - CREATE_LATEST_SYMLINK=FALSE
      - DEFAULT_COMPRESSION=GZ
      - DEFAULT_SPLIT_DB=TRUE
      - SIZE_VALUE=megabytes
      - ENABLE_SMTP=FALSE
      - ENABLE_ZABBIX=FALSE
      - ENABLE_LOGROTATE=FALSE

networks:
  default:
    name: proxy
    external: true
```
