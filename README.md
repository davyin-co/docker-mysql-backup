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

## Drupal 临时表剥离（默认开启）

镜像默认对 MySQL/MariaDB 启用「Drupal 临时表只导 schema、不导数据」的策略，避免
`cache_*`、`sessions`、`watchdog` 等可重建的临时表把备份体积撑大。

### 默认行为

- **业务表**（`node`、`users`、自定义表等）：schema + data 完整备份。
- **临时表**（`cache_*`、`sessions`、`watchdog`、`queue`、`batch`、`flood`、
  `http_client_log`）：只导出 `CREATE TABLE` 语句，`INSERT` 行数据被剥离。
- 非 Drupal 数据库（库里没有匹配的临时表）：**完全 no-op**，备份与上游行为一致。
- 仅影响 MySQL/MariaDB 路径；PostgreSQL 暂不支持表剥离（`{db}` 占位符替换仍可工作）。

### 关闭 / 自定义

镜像层只设了 4.x 的 `DEFAULT_*` 默认值；其它场景在 compose 里覆盖即可。

4.x 系列（`DEFAULT_*` 是镜像默认；`DB##_` 是 per-instance 覆盖，优先级最高）：

```yaml
environment:
  - DEFAULT_STRIP_CACHE_DATA=FALSE                # 全局关闭
  - DB01_STRIP_CACHE_DATA=FALSE                   # 只关闭 DB01 实例
  - DB01_STRIP_CACHE_TABLES=cache_%,sessions,watchdog,my_temp_%  # 自定义列表
```

3.x 系列（3.x 镜像不识别 `DEFAULT_*`，需要手动启用才能关闭）：

```yaml
environment:
  - DB_STRIP_CACHE_DATA=FALSE           # 关闭（如之前在某处启用过）
  # 启用 + 自定义列表：
  - DB_STRIP_CACHE_DATA=TRUE
  - DB_STRIP_CACHE_TABLES=cache_%,sessions,watchdog,my_temp_%
```

### 自定义临时表列表

`STRIP_CACHE_TABLES` 接受逗号分隔的列表，**`%` 后缀表示 LIKE 前缀匹配**，其它名字
按精确匹配。表名会通过 `information_schema.TABLES` 在每个备份运行时按当前 DB 动态
展开，所以 Drupal 表前缀（`cache_*`、`cache_views_data_*` 等）无需用户列举。

### `{db}` 占位符

这是上游 nfrastack/container-db-backup PR #477（"feat: support {db} placeholder
in EXTRA_BACKUP_OPTS for split-mode backup"）的等效实现。当一个 DB 实例有多库备份
（`DB01_NAME=ALL` 或 `DB_NAME=a,b,c`）时，`{db}` 会在每次 mysqldump 调用前被替换
为**当前正在备份的库名**，所以无需为每个库手写参数：

```yaml
environment:
  - EXTRA_BACKUP_OPTS=--ignore-table={db}.logs --ignore-table={db}.audit_trail
```

剥离逻辑会先把 `STRIP_CACHE_TABLES` 展开成具体的 `--ignore-table=<db>.<表名>` 再
拼到 `EXTRA_BACKUP_OPTS` 之后，所以两者可以共存。

### 工作原理（速览）

1. 镜像构建时，`assets/apply-strip-cache-patch.py` 向上游
   `/assets/functions/10-db-backup` 注入三处代码块：
   - 在 `bootstrap_init` 里给 `transform_backup_instance_variable` 注册
     `STRIP_CACHE_DATA` / `STRIP_CACHE_TABLES`，让 `DB##_` / `DEFAULT_` 前缀
     自动解析（与 `EXTRA_BACKUP_OPTS` 同款机制）。
   - 在 `backup_mysql()` 调用 mysqldump **之前** `source` 我们的
     `/assets/strip-cache-data.sh`。
   - 在 mysqldump **之后** 把 schema-only 前缀文件 prepend 到主 dump 文件。
2. `/assets/strip-cache-data.sh` 在每次备份运行时执行：
   - 把 `EXTRA_BACKUP_OPTS` 里的 `{db}` 替换成当前库名。
   - 通过 `information_schema` 查询该库匹配 `STRIP_CACHE_TABLES` 的实际表名。
   - 给每个匹配表追加 `--ignore-table=<db>.<table>`，让 mysqldump 跳过它们。
   - 同时 `mysqldump --no-data` 把这些表的 schema dump 到临时文件，供后续 prepend。
3. dump 完成后，post-mysqldump 注入块把 schema-only 文件 prepend 到主 dump 前。

### 排错

```bash
# 确认补丁是否注入
docker run --rm davyinsa/mysql-backup-rotate:4.1.17 \
    grep -E 'STRIP_CACHE_DATA_(REGISTER|INJECTION|POSTDUMP)_BEGIN' \
    /assets/functions/10-db-backup

# 确认备份里 cache_* 没有 INSERT，但有 CREATE TABLE
zcat /backup/<db_name>/mysql_*.sql.gz | grep -c '^INSERT INTO `cache_'
#   期望：0
zcat /backup/<db_name>/mysql_*.sql.gz | grep -c '^CREATE TABLE `cache_'
#   期望：≥1
```