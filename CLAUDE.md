# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目性质

这是一个**自定义 Docker 镜像构建仓库**，用于在 Docker 容器中执行 MySQL/MariaDB/PostgreSQL 数据库备份，并结合 `rotate-backups` Python 工具实现按时间维度的备份轮转（每天/每周/每月保留若干份）。镜像同时发布到 DockerHub (`davyinsa/mysql-backup-rotate`) 和阿里云容器镜像服务 (`registry.cn-hangzhou.aliyuncs.com/davyin/mysql-backup-rotate`)。

> **上游已停更（重要）**：上游 `tiredofit/db-backup` 于 2026-03-12 EOL，4.x 标签已从 Docker Hub 全部删除（`latest` 被重发布为无 shell 的 scratch 占位镜像），项目迁移更名为 [`nfrastack/db-backup`](https://github.com/nfrastack/db-backup) 并用 Go 重写（5.x）。本仓库目前**冻结在最后的 4.x 基础上**，迁移 5.x 另行立项。

## 核心架构

### 镜像层次
- `Dockerfile` 基础镜像冻结为自托管的 `davyinsa/mysql-backup-rotate:4.1.100`（2026-09-09 从最后的 `tiredofit/db-backup:4.1.100` 构建，包含完整 Alpine 4.x 层）。可用 `ARG BASE_IMAGE` / `ARG BASE_VERSION` 覆盖。
- 冻结基础已包含：`/venv`（含 `rotate-backups`）、`Asia/Shanghai` 时区、钩子脚本。当前构建只重新应用 ENV 默认值、刷新 `scripts/` 钩子脚本并 `chmod +x`（`rotate-dbbackups.sh` 在 git 中是 100644，chmod 层不可省略）。
- `assets/`（strip-cache patcher）已不参与构建——在 4.1.100 上 patcher 本就 silent no-op，strip-cache 完全由 post-hook 的 perl 过滤器实现。文件保留供 5.x 迁移参考。

### 备份流程
上游 `db-backup` 对每个数据库生成一个 dump 文件。`pre-backup.sh` 在 `/backup/<DB_NAME>` 下创建子目录；`rotate-dbbackups.sh` 在 dump 完成后把它移动到对应子目录并在该子目录内执行 `rotate-backups`。**这种"按库分子目录再轮转"的设计是整个项目的核心——必须保留才能让 `rotate-backups` 正确工作。**

### 3.x 与 4.x 环境变量差异
- **3.x**（`docker-compose.yml`, `docker-compose-pgsql.yml`）：使用单数 `DB_*` 前缀的环境变量，单一数据库连接。
- **4.x**（`docker-compose-v4.yml`, `docker-compose-rotate-interval*.yml`）：使用 `DB01_*` 前缀的多数据库（numbered），并大量使用 `DEFAULT_*` 前缀设置全局默认值。新增 `MODE=MANUAL`、`CONTAINER_ENABLE_SCHEDULING=FALSE` 等模式控制。
- README 明确标注：**4.x 改动较大，尚未完整测试验证**，暂时推荐使用 `3-3.12.2`。

### docker-compose 部署场景
- `docker-compose.yml` — 3.x 单库，按 schema 备份
- `docker-compose-v4.yml` — 4.x + DB01 多库示例
- `docker-compose-rotate-interval.yml` — 4.x 周期调度 + DB01 多库
- `docker-compose-rotate-interval-manual.yml` — 3.x 一次性备份（外部 cron 触发，`command: [backup-now]`）
- `docker-compose-pgsql.yml` — PostgreSQL 备份

## 常用命令

### 构建与发布
本地构建（不再传 `VERSION`，基础镜像由 Dockerfile 内 ARG 默认值锁定）：
```bash
# 本地构建
docker build -t davyinsa/mysql-backup-rotate:latest .
# 多平台构建（与 CI 一致）
docker buildx build --platform linux/amd64,linux/arm64 -t davyinsa/mysql-backup-rotate:latest .
```

CI 触发：push 到 `master`/`main`、每周三 05:00 (`cron: "0 5 * * 3"`) 自动重建、`workflow_dispatch` 手动触发。CI 只构建 `latest` 一个标签，推 DockerHub 和阿里云 CR。

### 本地运行
每个 compose 文件代表一种部署模式，按需选择：
```bash
docker compose -f docker-compose-v4.yml up -d
docker compose -f docker-compose-rotate-interval-manual.yml run --rm db-backup-rotate-freq-manual backup-now
```

### 修改轮转策略
轮转通过 `ROTATE_OPTIONS` 环境变量控制，常用格式：
```
--daily=N --weekly=N --monthly=N --prefer-recent
```
支持 `minutely` / `hourly` / `daily` / `weekly` / `monthly` 任意组合。修改后需重新构建镜像（默认值硬编码在 `Dockerfile`），或在 compose 中通过环境变量覆盖。

## 关键设计约束

- `scripts/pre-backup.sh` 和 `scripts/rotate-dbbackups.sh` 强依赖 `tiredofit/db-backup` 注入的 9 个位置参数顺序（`$1..$9` 见脚本注释），不要重排参数引用。`$8` 是 BACKUP FILENAME，`$4` 是 DB_NAME。
- `rotate-dbbackups.sh` 中 `mv ${DEFAULT_FILESYSTEM_PATH}/$8 ${DEFAULT_FILESYSTEM_PATH}/$4` 把文件按库分目录；删除这条 `mv` 会破坏轮转。
- `pip install rotate-backups` 必须在 venv 中（`. /venv/bin/activate`），直接 pip install 会因 PEP 668 失败。
- `.gitignore` 排除了所有 `backup*` 和 `docker-compose*.yml`（除被追踪的），修改 compose 时注意它不会被默认提交。
