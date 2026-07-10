#!/usr/bin/env bash
# ==============================================================================
# 为 HTTPS 反向代理生成自签名证书（离线/评估环境用）。
# 生产环境请换成企业 CA / 正式证书，只需替换 nginx/certs/tls.crt 与 tls.key。
#
# 用法: ./scripts/gen-certs.sh [CN]
#   CN 默认 localhost，可传入你的服务器域名，如 ./scripts/gen-certs.sh ide.example.com
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CN="${1:-localhost}"
CERT_DIR="nginx/certs"
mkdir -p "$CERT_DIR"

if [[ -f "$CERT_DIR/tls.crt" && -f "$CERT_DIR/tls.key" ]]; then
  echo "证书已存在: $CERT_DIR/tls.crt —— 如需重建请先删除该目录下文件。"
  exit 0
fi

echo ">>> 为 CN=$CN 生成自签名证书（有效期 825 天）..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$CERT_DIR/tls.key" \
  -out "$CERT_DIR/tls.crt" \
  -days 825 \
  -subj "/CN=$CN" \
  -addext "subjectAltName=DNS:$CN,DNS:localhost,IP:127.0.0.1"

chmod 600 "$CERT_DIR/tls.key"
echo ">>> 完成:"
echo "    $CERT_DIR/tls.crt"
echo "    $CERT_DIR/tls.key"
echo ">>> 浏览器首次访问 https://$CN 时会提示证书不受信任，评估环境手动放行即可。"
