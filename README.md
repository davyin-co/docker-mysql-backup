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

剥离在镜像自带的 **post-hook `rotate-dbbackups.sh`** 里完成（在 mysqldump
写完 `.sql.gz` 后做一次流式过滤，再 move+rotate）。这条路不再依赖
`assets/apply-strip-cache-patch.py` 向上游 `/assets/functions/10-db-backup`
注入代码——因为 4.1.100 上游把 `EXTRA_DUMP_OPTS` 改名为 `EXTRA_BACKUP_OPTS`，且
裸 `mysqldump` 改成了 `${_mysql_prefix}${_mysql_bin_prefix}dump`
（即 `mariadb-dump` / `mysql-dump`），导致 patcher 的两个锚点都失效，patcher
静默 `return 0`、`DEFAULT_STRIP_CACHE_*` env vars 从未被读取。

#### 当前实现（post-hook）

1. 每次 `pre_dbbackup "${db}"` 调用 `/assets/scripts/pre/pre-backup.sh`，只为后续
   的过滤打一行 `[pre-backup] strip-cache ENABLED for db='X' tables='…'` 日志
   （不修改 mysqldump）。
2. 每次 `post_dbbackup "${db}"` 调用 `/assets/scripts/post/rotate-dbbackups.sh`：
   - 解析 `_strip_enable`（`DB01_STRIP_CACHE_DATA → STRIP_CACHE_DATA → DEFAULT_STRIP_CACHE_DATA → FALSE`），
     `_strip_tables` 同款链路，默认
     `cache_%,sessions,watchdog,queue,batch,flood,http_client_log`。
   - 把列表展开成 `grep -E` 的多分支正则（`foo%` → `^INSERT INTO \`foo[^\`]*\``、
     `bar` → `^INSERT INTO \`bar\``），用
     `gunzip -c src | grep -v -E PATTERN | gzip > src.strip.tmp && mv` 替换源文件。
   - 然后保持原有的 `mv ${DEFAULT_FILESYSTEM_PATH}/$8 ${DEFAULT_FILESYSTEM_PATH}/$4` +
     `rotate-backups $ROTATE_OPTIONS` 行为。
3. 失败保护：filter 链路任何一步出错时打印 `WARN: strip-cache failed … leaving
   dump untouched` 并 `rm -f` 临时文件，不影响最终 dump 完整性。

> `assets/apply-strip-cache-patch.py` + `assets/strip-cache-data.sh` 仍保留在镜像
> 里作为 legacy——一旦上游某天重新引入 Patcher 可识别的锚点，注入版本仍然有效。
> 当前 4.1.100 build 上 patcher 会 silent no-op，剥离完全由 post-hook 负责。

#### 旧实现（已废弃，仅记录）

1. 镜像构建时，`apply-strip-cache-patch.py` 向上游 `10-db-backup` 注入三处代码：
   - `bootstrap_init` 里给 `transform_backup_instance_variable` 注册
     `STRIP_CACHE_DATA` / `STRIP_CACHE_TABLES`，让 `DB##_` / `DEFAULT_` 前缀
     自动解析。
   - 在 `backup_mysql()` 调用 mysqldump **之前** `source` `strip-cache-data.sh`。
   - 在 mysqldump **之后** 把 schema-only 前缀文件 prepend 到主 dump 文件。
2. `strip-cache-data.sh` 在每次备份时通过 `information_schema` 查表名，追加
   `--ignore-table=<db>.<table>` 让 mysqldump 跳过，并 dump 一份 schema-only 给 prepend。
3. dump 完成后 post-mysqldump 注入块把 schema-only 文件 prepend 到主 dump 前。

—— 这套在 4.x 早期分支可用，但与 `tiredofit/db-backup:4.1.100` 不兼容，
**所有此前的 4.x 备份都漏剥了 cache_* / watchdog / sessions**；切换到 post-hook
后立即生效。

### 排错

```bash
# 1. 确认镜像里有新版 post-hook（看注释头部的 phase signature）
docker run --rm davyinsa/mysql-backup-rotate:4.1.100 \
    head -20 /assets/scripts/post/rotate-dbbackups.sh

# 2. 实际验：找一台 Drupal 站点最新一次备份，看 cache_* INSERT 有没有剥
gunzip -c /backup/<db>/mariadb_<db>_*.sql.gz > /tmp/dump.sql
echo "cache_* INSERT 行数 (期望 0) : $(grep -c '^INSERT INTO `cache_' /tmp/dump.sql)"
echo "cache_* CREATE 表数 (期望 >=1): $(grep -c '^CREATE TABLE `cache_' /tmp/dump.sql)"
echo "watchdog INSERT 行数 (期望 0) : $(grep -c '^INSERT INTO `watchdog`' /tmp/dump.sql)"

# 3. 看 post-hook 失败告警
docker logs db-backup-rotate-freq 2>&1 | grep -E 'strip-cache|WARN' | tail -20
#   期望：下一次轮转后能看到 "[pre-backup] strip-cache ENABLED for db='…' tables='…'"
```