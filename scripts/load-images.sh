#!/usr/bin/env bash
# ==============================================================================
# 在【离线】机器上执行：从归档导入所有镜像。
# 用法: ./scripts/load-images.sh
# 前置: offline-images/tbe-images.tar 已随项目一起拷贝到本机。
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="offline-images/tbe-images.tar"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "错误: 未找到 $ARCHIVE"
  echo "请先在有网机器上执行 ./scripts/save-images.sh 并拷贝归档到此目录。"
  exit 1
fi

echo ">>> 从 $ARCHIVE 导入镜像..."
docker load -i "$ARCHIVE"

echo ">>> 已导入镜像列表:"
docker images | grep -E "ide-services|postgres|minio|keycloak" || true

echo ">>> 完成。现在可执行: docker compose up -d"
