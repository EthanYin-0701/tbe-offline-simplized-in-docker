#!/bin/bash

# JetBrains IDE Services Minikube 部署演示脚本
# 本脚本旨在展示如何在本地 Minikube 环境中快速拉起 IDE Services 及其依赖组件。

set -e

NAMESPACE="ide-services"

install_minikube() {
    echo "正在检查 Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "错误: 未找到 Homebrew。请先安装 Homebrew (https://brew.sh/) 或通过以下链接手动安装 minikube:"
        echo "https://minikube.sigs.k8s.io/docs/start/"
        exit 1
    fi
    echo "正在通过 Homebrew 安装 minikube..."
    brew install minikube
}

echo "=== 1. 检查环境 ==="

# 检查并安装 minikube
if ! command -v minikube &> /dev/null; then
    echo "检测到系统中未安装 minikube。"
    read -p "是否立即安装？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_minikube
    else
        echo "已取消安装。请手动安装 minikube 后重新运行此脚本。"
        exit 1
    fi
fi

# 检查其他必要工具
for cmd in kubectl helm; do
    if ! command -v $cmd &> /dev/null; then
        echo "错误: 未找到 $cmd，请先安装。"
        exit 1
    fi
done

echo "=== 2. 启动 Minikube ==="
# 建议至少 4 CPU 和 8G 内存以运行整套服务
minikube start --cpus=4 --memory=8192
minikube addons enable ingress

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")

echo "=== 3. 准备命名空间 ==="
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "=== 4. 安装基础依赖 (使用 Helm) ==="

# 添加 Bitnami 仓库 (用于 Postgres 和 MinIO)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 安装 PostgreSQL
echo "安装 PostgreSQL..."
helm upgrade --install postgres bitnami/postgresql \
    --namespace $NAMESPACE \
    --set global.postgresql.auth.database=ide_services \
    --set global.postgresql.auth.password=postgres-password

# 安装 MinIO
# 注意: 2025 年 8 月起 Bitnami 将带版本号的镜像迁移至 docker.io/bitnamilegacy,
# docker.io/bitnami 下仅保留 latest 标签。这里显式指向 legacy 仓库以避免 ImagePullBackOff。
echo "安装 MinIO..."
helm upgrade --install minio bitnami/minio \
    --namespace $NAMESPACE \
    --set auth.rootUser=minio-admin \
    --set auth.rootPassword=minio-password \
    --set defaultBuckets="ide-services" \
    --set image.registry=docker.io \
    --set image.repository=bitnamilegacy/minio \
    --set image.tag=2024.11.7-debian-12-r0 \
    --set clientImage.registry=docker.io \
    --set clientImage.repository=bitnamilegacy/minio-client \
    --set console.image.registry=docker.io \
    --set console.image.repository=bitnamilegacy/minio-object-browser

echo "=== 5. 部署内置 Keycloak (OIDC 认证) ==="
# IDE Services 必须配置一个 OIDC 提供方才能启动, 这里部署一个预置 realm 的 Keycloak,
# 配置与仓库根目录 docker-compose.yml 保持一致 (realm=toolbox, client=tbe-server)。
kubectl apply -f keycloak-minikube.yaml
echo "等待 Keycloak 就绪 (导入 realm 可能需要 1-2 分钟)..."
kubectl rollout status deployment/keycloak -n $NAMESPACE --timeout=300s

echo "=== 6. 安装 JetBrains IDE Services ==="

# 添加 JetBrains 仓库
helm repo add jetbrains https://download.jetbrains.com/ide-services/charts/stable
helm repo update

# 执行安装
# 单节点 Minikube 无法满足默认的 2 副本 Pod 反亲和性调度, 这里改为单副本。
echo "安装 IDE Services..."
helm upgrade --install ide-services jetbrains/ide-services-helm \
    --namespace $NAMESPACE \
    --set ides.replicaCount=1 \
    -f values-minikube.yaml

echo ""
echo "================================================================"
echo "部署指令已发送！"
echo "1. 请等待所有 Pod 启动: kubectl get pods -n $NAMESPACE -w"
echo "2. 配置域名解析: 建议将以下内容加入你的 /etc/hosts:"
echo "   $(minikube ip) ide-services.local keycloak.ide-services.local"
echo "   (macOS + docker 驱动时 minikube IP 不可直连, 请改为映射到 127.0.0.1"
echo "    并在另一个终端执行: minikube tunnel)"
echo "3. 访问服务: http://ide-services.local"
echo "   使用内置 Keycloak 账号登录: admin / admin (邮箱 toolbox.admin@example.com)"
echo "================================================================"
echo "说明: 本脚本已内置 Keycloak (realm=toolbox, client=tbe-server), IDE Services"
echo "可直接启动并完成登录。首个以 toolbox.admin@example.com 登录的用户为超级管理员。"
echo "注意: 完整激活 IDE Services 仍需导入有效的 JetBrains License。"
echo "================================================================"
