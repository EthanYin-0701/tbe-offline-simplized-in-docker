# 在 Kubernetes 上部署 JetBrains IDE Services

本文档介绍如何使用 Helm 在 Kubernetes 集群中部署 JetBrains IDE Services。

## 前置要求

- **Kubernetes**: 1.27 或更高版本。
- **Helm**: 3.12 或更高版本。
- **命名空间**: 建议准备一个专用的命名空间（如 `ide-services`）。
- **外部组件**:
  - **PostgreSQL**: 13 或更高版本。
  - **对象存储**: S3 兼容（如 MinIO、AWS S3、Azure Blob）。
  - **认证服务**: OIDC 兼容（如 Keycloak、Okta、Google）。
- **Ingress Controller**: 如 Nginx Ingress，并配置好 DNS。

## 部署步骤 (在线环境)

### 1. 添加 Helm 仓库

```bash
helm repo add jetbrains https://download.jetbrains.com/ide-services/charts/stable
helm repo update
```

### 2. 准备配置文件

参考本仓库的 `kubernetes/values-minikube.yaml` 修改你的配置。注意最新的
`ide-services-helm` 将所有键置于 `ides.*` 下（`ides.config.db` /
`ides.config.storage.s3` / `ides.config.auth` / `ides.ingress` 等），修改时重点关注
数据库连接、S3 存储凭据和 OIDC 认证信息。

### 3. 安装 Chart

```bash
# 创建命名空间
kubectl create namespace ide-services

# 安装
helm install ide-services jetbrains/ide-services-helm \
  --namespace ide-services \
  -f values-minikube.yaml
```

## 部署步骤 (离线环境/Air-gapped)

如果你的 K8s 集群无法访问公网，请按照以下步骤操作：

### 1. 下载 Chart 包 (在有网机器)

```bash
helm pull jetbrains/ide-services-helm --version <VERSION>
# 或者直接从官网下载 tgz 包
```

### 2. 下载并导入镜像

运行以下命令获取所需镜像列表：

```bash
helm template ide-services jetbrains/ide-services-helm | grep "image:"
```

在有网机器拉取这些镜像并导出：
```bash
docker pull <IMAGE>
docker save <IMAGE> -o <IMAGE_FILE>.tar
```

在内网环境导入镜像到你的私有镜像仓库或节点的 Docker 中。

### 3. 部署

将解压后的 Chart 文件夹拷贝到内网，并修改 `values-minikube.yaml` 中的镜像仓库地址（如果有）。

```bash
helm install ide-services ./ide-services-helm \
  --namespace ide-services \
  -f values-minikube.yaml
```

## 验证部署

查看 Pod 状态：

```bash
kubectl get pods -n ide-services
```

确保所有 Pod 都处于 `Running` 状态。

## 快速演示 (Minikube)

为了方便在本地快速体验，我们提供了一个自动化脚本，它会：
1. 启动 Minikube 并启用 Ingress。
2. 使用 Helm 安装简易版的 PostgreSQL 和 MinIO（Bitnami）作为依赖。
3. 部署预置 realm 的内置 Keycloak（`keycloak-minikube.yaml`，realm=toolbox，client=tbe-server）作为 OIDC 认证。
4. 使用 `values-minikube.yaml` 部署 IDE Services（单节点 Minikube 改为单副本）。

**运行方法：**

```bash
cd kubernetes
./minikube-demo.sh
```

**注意事项：**
- 脚本会自动检查 `minikube`，若未安装则会提示通过 Homebrew 进行安装。
- 仍需确保本地已安装 `kubectl` 和 `helm`。
- 默认配置在 `values-minikube.yaml` 中，服务域名为 `ide-services.local`，Keycloak 域名为 `keycloak.ide-services.local`。
- 部署完成后，可用 `./toggle-hosts.sh on` 自动写入 `/etc/hosts`（`off` 移除、`status` 查看，默认指向当前 minikube ip）；脚本输出也会给出手动配置提示。
- 使用内置 Keycloak 账号登录：`admin` / `admin`（邮箱 `toolbox.admin@example.com`，首个以该邮箱登录的用户即超级管理员）。
- 完整激活 IDE Services 仍需导入有效的 JetBrains License。

## 更多参考

- [官方文档: Kubernetes Helm installation](https://www.jetbrains.com/help/ide-services/install-instance-in-kubernetes-cluster.html)
- [官方文档: Values file configuration](https://www.jetbrains.com/help/ide-services/values-file.html)
