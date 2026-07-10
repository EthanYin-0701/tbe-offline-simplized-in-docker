#!/usr/bin/env bash
# ==============================================================================
# 在【有网】的机器上执行：拉取所有镜像并打包成 tar，供离线机器导入。
# 用法: ./scripts/save-images.sh
# 产物: offline-images/tbe-images.tar  (以及各镜像单独的 .tar)
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

# 读取 .env 中定义的镜像变量。
# 用逐键解析而非 `source .env`：某些值（如中文占位符）含空格会让 shell source 出错。
env_get() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

IMAGES=(
  "$(env_get IDE_SERVICES_IMAGE)"
  "$(env_get POSTGRES_IMAGE)"
  "$(env_get MINIO_IMAGE)"
  "$(env_get MINIO_MC_IMAGE)"
  "$(env_get KEYCLOAK_IMAGE)"
  "$(env_get NGINX_IMAGE)"
)

OUT_DIR="offline-images"
mkdir -p "$OUT_DIR"

echo ">>> 拉取镜像..."
for img in "${IMAGES[@]}"; do
  echo "  pulling $img"
  docker pull "$img"
done

echo ">>> 打包为单个归档 $OUT_DIR/tbe-images.tar ..."
docker save -o "$OUT_DIR/tbe-images.tar" "${IMAGES[@]}"

echo ">>> 完成。请将以下内容整体拷贝到离线机器："
echo "    - 整个项目目录 (docker-compose.yml / .env / config / keycloak / scripts)"
echo "    - $OUT_DIR/tbe-images.tar"
echo ">>> 在离线机器上执行: ./scripts/load-images.sh && docker compose up -d"
