#!/usr/bin/env bash
# ==============================================================================
# 示例：用 ide-services-cli 下载最新版 IntelliJ IDEA，并上传到 MinIO 已有 bucket，
#       使其可在终端用户的 Toolbox App 中下载。
#
# 参考: https://www.jetbrains.com/help/ide-services/offline-mode.html
#
# 用法:
#   ./download-and-publish-idea.sh                 # 默认 IntelliJ IDEA Ultimate (IDEA-U)
#   PRODUCT=IDEA-C ./download-and-publish-idea.sh   # 社区版
#   CLI_BIN=/path/to/ide-services-cli ./download-and-publish-idea.sh
#
# 前置:
#   - 根目录 docker-compose 栈已启动（MinIO 在运行）
#   - 已从 Web UI 下载并解压 ide-services-cli 到本目录（见下方提示）
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")"
WORKDIR="$PWD"

# 从根目录 .env 读取所需变量。
# 注意：这里用逐键解析而非 `source .env`，因为某些值（如中文占位符）含空格，
#       会导致 shell source 出错；docker compose 读取则不受影响。
ROOT_DIR="$(cd ../.. && pwd)"
env_get() { grep -E "^$1=" "$ROOT_DIR/.env" | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

IDE_SERVICES_PORT="$(env_get IDE_SERVICES_PORT)"
MINIO_MC_IMAGE="$(env_get MINIO_MC_IMAGE)"
MINIO_ROOT_USER="$(env_get MINIO_ROOT_USER)"
MINIO_ROOT_PASSWORD="$(env_get MINIO_ROOT_PASSWORD)"
MINIO_BUCKET="$(env_get MINIO_BUCKET)"

CLI_BIN="${CLI_BIN:-./ide-services-cli}"
PRODUCT="${PRODUCT:-IDEA-U}"        # IDEA-U=Ultimate, IDEA-C=Community
COMPOSE_PROJECT="tbe-offline"       # 与 docker-compose.yml 的 name: 一致
NETWORK="${COMPOSE_PROJECT}_tbe-net"

# ------------------------------------------------------------------------------
# 0) 检查 ide-services-cli 是否就位
#    该二进制只能从已运行 + 已激活 License 的 Web UI 获取，无法随项目预置。
# ------------------------------------------------------------------------------
if [[ ! -x "$CLI_BIN" ]]; then
  cat <<EOF
[✗] 未找到可执行的 ide-services-cli: $CLI_BIN

获取步骤：
  1. 浏览器打开 http://localhost:${IDE_SERVICES_PORT}
  2. 以 root admin 登录并导入 License
  3. Configuration → Offline mode → 点击 "Download ide-services-cli"
  4. 解压下载的 zip，把其中的 ide-services-cli 放到本目录：
        $WORKDIR/ide-services-cli
  5. chmod +x "$WORKDIR/ide-services-cli"
  6. 重新运行本脚本

（也可通过 CLI_BIN=/绝对路径/ide-services-cli 指定其他位置）
EOF
  exit 1
fi

# ------------------------------------------------------------------------------
# 1) init：下载核心 artifacts 并生成 ./ide-services/offline/ 与 offline.json
# ------------------------------------------------------------------------------
echo ">>> [1/3] $CLI_BIN init"
"$CLI_BIN" init

# ------------------------------------------------------------------------------
# 2) 下载最新版 IntelliJ IDEA（不指定 build 即为最新版；覆盖全部 OS）
#    如需筛选 OS/版本，可用 filter：$CLI_BIN tool download --filter tool-filter.example.json
# ------------------------------------------------------------------------------
echo ">>> [2/3] $CLI_BIN tool download $PRODUCT （最新版）"
"$CLI_BIN" tool download "$PRODUCT"

OFFLINE_DIR="$WORKDIR/ide-services/offline"
if [[ ! -d "$OFFLINE_DIR" ]]; then
  echo "[✗] 未找到 $OFFLINE_DIR —— init/download 似乎未成功。"
  exit 1
fi

# ------------------------------------------------------------------------------
# 3) 上传到 MinIO 已有 bucket
#    使用 dockerized mc 接入 compose 网络，离线环境也可用（无需宿主机装 aws/mc）。
#    把 offline/ 的【内容】镜像到 bucket 根，以匹配 offline.json 中默认的
#    "to": "tbe-s3://<资源>" 前缀（tbe-s3:// 解析为已配置的 bucket 根）。
# ------------------------------------------------------------------------------
echo ">>> [3/3] 上传 offline artifacts -> MinIO bucket: ${MINIO_BUCKET}"
docker run --rm \
  --network "$NETWORK" \
  -v "$OFFLINE_DIR:/offline:ro" \
  --entrypoint /bin/sh \
  "$MINIO_MC_IMAGE" \
  -c "
    until mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}'; do
      echo 'waiting for minio...'; sleep 2;
    done;
    mc mirror --overwrite /offline local/${MINIO_BUCKET};
    echo '--- bucket 中的对象（前 40 条）---';
    mc ls -r local/${MINIO_BUCKET} | head -40;
  "

cat <<EOF

[✓] 完成。让服务端与终端用户生效的后续步骤：
  1. config/application.yaml 中 tbe.offline.enabled: true（本项目已配好）
  2. cd "$ROOT_DIR" && docker compose restart ide-services
  3. Web UI → Configuration → License & Activation → IDE Provisioner → Enable
  4. 终端用户的 Toolbox App 连接本 IDE Services 后，即可看到并下载 IntelliJ IDEA

提示：若 ./ide-services/offline/offline.json 中 "to" 路径用了非 tbe-s3:// 根前缀，
     请相应调整上传目标（mirror 的目的路径）或 offline.json，保证二者一致。
EOF
