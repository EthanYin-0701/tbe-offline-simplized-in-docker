# JetBrains IDE Services — 离线 docker-compose 环境

一套**完全自托管、无需外网**的 JetBrains IDE Services（原 Toolbox Enterprise）
评估环境，通过 `docker compose` 一键拉起。

参考文档：<https://www.jetbrains.com/help/ide-services/docker-installation.html>

## 架构组成

| 服务 | 作用 | 镜像 |
|------|------|------|
| `ide-services` | IDE Services 服务端 | `jetbrains/ide-services` |
| `postgres` | 元数据库（PostgreSQL 13+） | `postgres:16` |
| `minio` | S3 兼容对象存储 | `minio/minio` |
| `minio-init` | 一次性任务，创建 `toolbox` bucket | `minio/mc` |
| `keycloak` | 内置 OAuth2/OIDC 认证服务（替代 Google/Okta，保证离线） | `quay.io/keycloak/keycloak` |

> **为什么“离线”还需要 Keycloak？**
> IDE Services 强制要求一个外部 OAuth2 认证提供方。为了不依赖公网的 Google/Okta，
> 这里内置了一个预配置好 realm/client/管理员用户的 Keycloak，使整套环境自成闭环。

## 目录结构

```
.
├── docker-compose.yml          # 编排入口
├── .env                        # 镜像版本、端口、凭据（改这里即可）
├── config/
│   └── application.yaml        # IDE Services 服务端配置
├── keycloak/
│   └── realm-export.json       # 预置 realm(toolbox)+client(tbe-server)+管理员
├── nginx/
│   ├── nginx.conf              # 反向代理 + TLS 终止配置
│   └── certs/                  # 证书目录（由 gen-certs.sh 生成，勿提交私钥）
├── scripts/
│   ├── save-images.sh          # 有网机器：拉取并打包镜像
│   ├── load-images.sh          # 离线机器：导入镜像
│   └── gen-certs.sh            # 生成自签名证书（HTTPS 用）
├── kubernetes/
│   ├── values.yaml             # Helm Chart 配置示例
│   └── README.md               # K8s 部署指南
└── examples/
    └── ide-services-cli/       # 示例：用 CLI 下载 IntelliJ IDEA 并发布到 MinIO
```

## 一、离线部署步骤（air-gapped）

### 1. 在【有网】机器上打包镜像

```bash
./scripts/save-images.sh
```

产出 `offline-images/tbe-images.tar`。

### 2. 拷贝到【离线】机器

把**整个项目目录** + `offline-images/tbe-images.tar` 一起拷过去。

### 3. 在离线机器导入镜像并启动

```bash
./scripts/load-images.sh
./scripts/gen-certs.sh     # 生成 HTTPS 自签名证书（反向代理需要）
docker compose up -d
```

## 二、直接启动（当前机器已有镜像 / 允许联网评估）

```bash
./scripts/gen-certs.sh                # 生成 HTTPS 自签名证书（首次必须，反向代理需要）
docker compose up -d
docker compose logs -f ide-services   # 观察启动日志
```

> HTTPS 反向代理 (nginx) 已内置于 `docker-compose.yml`，因此 **`up` 之前必须先执行
> `gen-certs.sh`**，否则 `reverse-proxy` 会因找不到证书而启动失败。

首次启动 `ide-services` 会自动在 PostgreSQL 中执行数据库迁移，耗时约 1–2 分钟。

## 三、访问入口

| 入口 | 地址 | 凭据 |
|------|------|------|
| IDE Services Web UI（HTTPS，正式入口） | <https://localhost> | 用 Keycloak 用户登录 |
| IDE Services 直连 http（调试用） | <http://localhost:8080> | 同上 |
| Keycloak 管理控制台 | <http://localhost:8085> | `admin` / `admin` |
| MinIO 控制台 | <http://localhost:9001> | `minioadmin` / `minioadmin` |
| PostgreSQL | `localhost:5432` | `toolbox` / `toolbox_pwd` |

> `http://localhost` 会 301 跳转到 `https://localhost`；自签证书浏览器会告警，评估环境手动放行即可。

**登录 IDE Services 的业务账号（预置）：**

- 邮箱：`toolbox.admin@example.com`
- 密码：`admin`

该邮箱已写入 `application.yaml` 的 `root-admin-emails`，首次登录即为超级管理员。

> **关于 License（重要）**
> IDE Services 是商业产品，启动后仍需一份 JetBrains License 才能启用完整功能
> （未激活时 `/api/auth/login` 会返回 `402`，日志中出现 `No valid license found`）。
> 以 root admin 登录 Web UI 后，在管理界面按提示导入试用/正式 License 即可。
> License 需向 JetBrains 申请，这一步不属于 docker-compose 可自动完成的范围。

## 三点五、HTTPS（反向代理，已内置）

> JetBrains **推荐通过外部反向代理**实现 HTTPS，而非在服务端内置 SSL：
> <https://www.jetbrains.com/help/ide-services/system-requirements.html#high-availability>

`docker-compose.yml` 已内置一个 `reverse-proxy`(nginx) 服务，在 IDE Services 前面终止
TLS，后端仍走容器内 http；`:8080` 直连 http 入口保留用于调试。

内置的关键配置：
- `reverse-proxy` 监听宿主机 `443`/`80`（可用 `.env` 的 `HTTPS_PORT`/`HTTP_REDIRECT_PORT` 调整），`http://localhost` 自动 301 跳 `https://localhost`；
- IDE Services 公开 URL 为 `TBE_DEPLOYMENT_URL=https://localhost`，并设 `SERVER_FORWARD-HEADERS-STRATEGY=FRAMEWORK` 识别反代转发头；
- Keycloak client 的 `redirectUris`/`webOrigins` 已预置 `https://localhost/*`。

### 证书

启动前必须生成证书（`reverse-proxy` 依赖 `nginx/certs/tls.crt`、`tls.key`）：

```bash
./scripts/gen-certs.sh                 # 默认 CN=localhost
# ./scripts/gen-certs.sh ide.example.com   # 指定域名
```

- 自签名证书浏览器会告警，评估环境手动放行即可；
- **生产**：直接用企业 CA / 正式证书替换 `nginx/certs/tls.crt`、`tls.key`，无需改 compose；
- 更换域名/端口时，需同步更新 `docker-compose.yml` 里的 `TBE_DEPLOYMENT_URL` 与
  `keycloak/realm-export.json` 的 `redirectUris`（改后 `docker compose up -d --force-recreate keycloak`）。

> 如果你**不需要 HTTPS**：删掉 `docker-compose.yml` 里的 `reverse-proxy` 服务，
> 并把 `TBE_DEPLOYMENT_URL` 改回 `http://localhost:${IDE_SERVICES_PORT}` 即可。

## 四、配置说明与自定义

所有可变项集中在 `.env`，`config/application.yaml` 与 `docker-compose.yml`
仅通过 `${...}` 引用，改配置无需动这两个文件：

- **改端口**：`IDE_SERVICES_PORT` / `KEYCLOAK_PORT` 等。
- **改密码/密钥**：`POSTGRES_PASSWORD`、`MINIO_ROOT_*`、`KEYCLOAK_CLIENT_SECRET` 等
  （改 client secret 时需同步修改 `keycloak/realm-export.json` 里的 `secret` 并重建 keycloak volume）。
- **改管理员邮箱**：`ROOT_ADMIN_EMAIL`，并同步修改 `keycloak/realm-export.json` 里的用户 `email`。
- **升级 IDE Services 版本**：修改 `.env` 的 `IDE_SERVICES_IMAGE` tag。

### 认证 URL 的前端/后端拆分（重要）

Keycloak 在 Docker 内有“浏览器地址”与“容器间地址”不一致的经典问题，本环境已处理：

- `login-url`（**浏览器**跳转）→ `http://localhost:8085/...`
- `token-url` / `jwt-certs-url`（**ide-services 容器** backchannel）→ `http://keycloak:8080/...`

Keycloak 通过 `KC_HOSTNAME=http://localhost:8085` +
`KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true` 保证 token 的 issuer 前端一致、后端回调可达。

## 五、产品级「离线模式」(Offline Mode)

> 参考：<https://www.jetbrains.com/help/ide-services/offline-mode.html>

注意区分两层「离线」：

1. **部署离线（air-gapped）**——本项目的 DB / 存储 / 认证全自托管、镜像预加载，
   已默认满足。
2. **产品离线模式（`tbe.offline.enabled`）**——让 IDE Services 服务端**不再向
   JetBrains 外部服务发起任何请求**（marketplace、`account.jetbrains.com` 许可校验等）。

本项目已在 `config/application.yaml` 中开启第 2 层：

```yaml
tbe:
  offline:
    enabled: true
```

> `ides.config.offlineMode.enabled`（Values 文件）仅用于 Kubernetes/Helm 部署，
> docker-compose 无需配置。

### 开启后必须完成的工作

打开开关后服务端彻底不联网，因此 IDE / 插件 / 工具必须**预先灌入对象存储 (MinIO)**
才能下发给开发者：

1. 以 root admin 登录 Web UI → **Configuration → Offline mode** 下载 IDE Services CLI；
2. `ide-services-cli init`；
3. `ide-services-cli tool download`（下载所需 IDE / 工具）；
4. 将生成的 `/ide-services/offline/` 目录传入对象存储（本项目为 MinIO 的 `toolbox` bucket）；
5. **上传 JetBrains IDE Services 插件**到插件仓库（下发功能所必需）；
6. `docker compose restart ide-services`；
7. 组织级启用 **IDE Provisioner**：Configuration → License & Activation → IDE Provisioner → Enable。

> 📦 **可运行示例**：`examples/ide-services-cli/` 提供了上述 ②③④ 的一键脚本
> （用 `ide-services-cli` 下载最新版 IntelliJ IDEA 并发布到 MinIO 的 `toolbox` bucket，
> 供终端用户在 Toolbox App 下载）。详见 [examples/ide-services-cli/README.md](examples/ide-services-cli/README.md)。

### 仍需 License

离线模式只是不再「每次联网校验」，**仍需导入一份离线 License** 才能激活
（即 `.env` 中 `ROOT_ADMIN_EMAIL` 填 JetBrains 帐户管理员邮箱那一步的目的）。
只翻开关而不灌 artifacts 时，服务端可正常启动，只是「可下发的 IDE/工具列表为空」。

## 六、常用运维命令

```bash
docker compose ps                      # 查看状态
docker compose logs -f ide-services    # 跟踪日志
docker compose down                    # 停止（保留数据卷）
docker compose down -v                 # 停止并清空所有数据（含 DB / 对象存储）
docker compose restart ide-services    # 重启服务端
```

## 八、Kubernetes 部署

如果你需要在大规模生产环境或云原生环境中部署 IDE Services，请参考 `kubernetes/` 目录：

- **[kubernetes/README.md](kubernetes/README.md)**: 详细介绍了如何使用 Helm Chart 进行在线和离线部署。
- **[kubernetes/values-minikube.yaml](kubernetes/values-minikube.yaml)**: 提供了 K8s 部署所需的配置参数模板。

官方详细文档请参考：[Install IDE Services in a Kubernetes cluster](https://www.jetbrains.com/help/ide-services/install-instance-in-kubernetes-cluster.html)

## 九、故障排查

- **ide-services 启动即退出**：先确认 `postgres` 健康、`minio-init` 已成功创建 bucket，
  再看 `docker compose logs ide-services` 是否为 DB 连接或 auth 证书拉取失败。
- **登录后回调报 redirect_uri 错误**：检查 `keycloak/realm-export.json` 的 `redirectUris`
  是否包含当前 `IDE_SERVICES_PORT` 对应地址；改动后需 `docker compose down -v keycloak` 重新导入 realm。
- **端口占用**：改 `.env` 中对应 `*_PORT` 后 `docker compose up -d`。
