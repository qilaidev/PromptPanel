# PromptPanel 开源自托管云同步服务端 (`server/`)

`PromptPanel` 作为开源项目，允许任何用户在自己的云服务器、NAS 或内网主机上一键部署完全私有的云端同步服务，与 macOS 桌面端和 Android / iOS 手机端无缝协同。

## 架构特点（高性能 + 严格隔离）
1. **零外部依赖、极低资源占用**：基于 Python 3 标准库 + SQLite WAL 模式构建，内存占用仅 ~12MB，响应延迟 < 2ms。
2. **Token 命名空间物理隔离**：
   - 每个 `Bearer Token` 通过 `SHA-256` 派生出独立的命名空间（`namespaces/<sha256>.db`），不同 Token 之间在数据库文件层级 **100% 物理隔离**，且磁盘上不存储明文 Token。
   - 支持通过 `PP_SYNC_ALLOWED_TOKENS` 环境变量配置私有白名单（常量时间 HMAC 校验）。
3. **服务端冲突版本自动保护**：
   - 当手机端与 macOS 端并发推送修改时，服务端会在合并时自动将被覆盖的差异文本转存为 `EntryVersion` 历史版本，并返回最新合并后的完整快照，**绝不丢失任何一端的文字**。
4. **Systemd / Docker 双重沙箱隔离**：
   - Systemd 部署默认启用独立无特权系统用户 `promptpanel-sync`、`ProtectSystem=strict`、`ProtectHome=yes`、`PrivateTmp=yes`、`NoNewPrivileges=yes`，并限制 `MemoryMax=128M`、`CPUQuota=50%`，完全不影响宿主机其他业务。

## 部署方式

### 方式一：Systemd 沙箱一键部署（推荐 Ubuntu / Debian 云主机）
```bash
sudo PP_SYNC_PORT=18787 ./deploy-systemd.sh
```

### 方式二：Docker Compose 部署
```bash
docker compose up -d --build
```

## 接口协议
- `GET /v1/health`：连通性、延迟与 Token 鉴权状态检测
- `GET /v1/sync`：拉取当前 Token 命名空间下的完整同步信封 (`CloudSyncEnvelope v2`)
- `POST /v1/sync`：双向智能合并客户端信封并返回合并后的最新信封（支持 Gzip 压缩）
