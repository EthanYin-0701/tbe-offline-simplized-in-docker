# 示例：用 ide-services-cli 发布 IntelliJ IDEA 到离线环境

本示例演示离线模式下的完整「灌 artifacts」链路：

> 用 `ide-services-cli` 下载**最新版 IntelliJ IDEA** → 上传到本项目 MinIO 里**已有的
> `toolbox` bucket** → 终端用户在 **Toolbox App** 中即可下载。

参考文档：<https://www.jetbrains.com/help/ide-services/offline-mode.html>

## 目录内容

```
download-and-publish-idea.sh   # 一键脚本：init + tool download + 上传 MinIO
tool-filter.example.json       # 可选：按产品/版本/OS 过滤下载，减小体积
```

## 前置条件

1. 根目录 docker-compose 栈已启动（`docker compose up -d`），MinIO 正在运行。
2. 服务端已开启离线模式（`config/application.yaml` 中 `tbe.offline.enabled: true`，本项目已配）。
3. 已获取 `ide-services-cli` 二进制（见下一节）。

## 获取 ide-services-cli

该二进制**只能从已运行且已激活 License 的 Web UI 下载**，无法随项目预置：

1. 浏览器打开 <http://localhost:8080>
2. 以 root admin（`toolbox.admin@example.com`）登录并导入 License
3. **Configuration → Offline mode → Download ide-services-cli**
4. 解压 zip，把其中的 `ide-services-cli` 放到本目录，并赋可执行权限：
   ```bash
   chmod +x ./ide-services-cli
   ```

## 运行

```bash
cd examples/ide-services-cli

# 默认下载 IntelliJ IDEA Ultimate 最新版
./download-and-publish-idea.sh

# 或下载社区版
PRODUCT=IDEA-C ./download-and-publish-idea.sh

# CLI 放在别处时
CLI_BIN=/opt/ide-services-cli/ide-services-cli ./download-and-publish-idea.sh
```

脚本做三件事：

| 步骤 | 命令 | 说明 |
|------|------|------|
| 1 | `ide-services-cli init` | 下载核心 artifacts，生成 `./ide-services/offline/`（含 `distributions/`、`feeds/`、`plugins/`、`offline.json`） |
| 2 | `ide-services-cli tool download IDEA-U` | 下载最新版 IntelliJ IDEA（全部 OS） |
| 3 | dockerized `mc mirror` | 把 `offline/` 内容镜像到 MinIO 的 `toolbox` bucket 根 |

> 上传用的是本项目已有的 `minio/mc` 镜像并接入 compose 网络，因此**离线机器上也能跑**，
> 无需宿主机额外安装 `aws` / `mc`。官方文档给出的等价命令是
> `aws s3 sync ./ide-services s3://<bucket> --endpoint-url http://<host>:9000`。

## 上传后让其对终端用户生效

```bash
cd ../..                              # 回到项目根目录
docker compose restart ide-services   # 让服务端重新加载 offline.json
```

然后在 Web UI：**Configuration → License & Activation → IDE Provisioner → Enable**
（组织级启用 IDE Provisioner，才会向用户下发 IDE/插件）。

完成后，终端用户的 **Toolbox App** 连接本 IDE Services，即可看到并下载 IntelliJ IDEA。

## 路径映射说明（重要）

`offline.json` 里每条映射的 `to` 默认形如 `tbe-s3://feeds/...`，其中 `tbe-s3://`
解析为**已配置的 bucket 根**（即 `toolbox`）。因此脚本把 `offline/` 的**内容**镜像到
bucket 根，得到 `toolbox/feeds/...`、`toolbox/distributions/...`、`toolbox/offline.json`，
与映射前缀一致。

若你的 `offline.json` 使用了不同前缀（例如指向内部 Artifactory/Nexus），
请相应调整脚本里 `mc mirror` 的目的路径，或修改 `offline.json`，保证两者对应。

## 维护提醒

`feeds/` 中的 feed 文件**有过期时间**，Toolbox App 会校验。过期前需重新
`ide-services-cli init` 生成新的 `offline.json` 与 feeds，重新上传并重启服务端。
