#!/bin/bash

# ==============================================================================
# 切换 /etc/hosts 中 Minikube IDE Services 演示域名的解析
#
# 用法:
#   ./toggle-hosts.sh on       # 添加/更新解析 (指向当前 minikube ip)
#   ./toggle-hosts.sh off      # 移除解析, 恢复原样
#   ./toggle-hosts.sh status   # 查看当前状态
#
# 可选:
#   ./toggle-hosts.sh on 127.0.0.1     # 指定 IP (macOS + docker 驱动需配合
#                                      #  `minikube tunnel`, 此时映射到 127.0.0.1)
#   HOSTS_IP=1.2.3.4 ./toggle-hosts.sh on
#
# 说明: 修改 /etc/hosts 需要管理员权限, 脚本会在需要时调用 sudo。
#       所有条目都写在一对标记之间, on/off 只影响这块内容, 不会破坏其它条目。
# ==============================================================================

set -e

# 需要解析的域名
HOSTNAMES="ide-services.local keycloak.ide-services.local"

# /etc/hosts 中的标记块 (off 时按标记整段删除)
BEGIN_MARK="# >>> minikube ide-services (managed by toggle-hosts.sh) >>>"
END_MARK="# <<< minikube ide-services <<<"

HOSTS_FILE="/etc/hosts"

# ---- 解析目标 IP: 参数 > 环境变量 > minikube ip > 默认值 --------------------
resolve_ip() {
    if [[ -n "$1" ]]; then
        echo "$1"
    elif [[ -n "$HOSTS_IP" ]]; then
        echo "$HOSTS_IP"
    elif command -v minikube &> /dev/null && minikube ip &> /dev/null; then
        minikube ip
    else
        echo "192.168.49.2"
    fi
}

# ---- 若无写权限则用 sudo -----------------------------------------------------
maybe_sudo() {
    if [[ -w "$HOSTS_FILE" ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ---- 输出去掉标记块之后的 hosts 内容 ----------------------------------------
strip_block() {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        index($0, b) { skip = 1; next }
        index($0, e) { skip = 0; next }
        !skip        { print }
    ' "$HOSTS_FILE"
}

# ---- 备份一次 (带时间戳) -----------------------------------------------------
backup_hosts() {
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    maybe_sudo cp "$HOSTS_FILE" "${HOSTS_FILE}.bak.${ts}"
    echo "已备份: ${HOSTS_FILE}.bak.${ts}"
}

# ---- 刷新 DNS 缓存 (仅 macOS) ------------------------------------------------
flush_dns() {
    if [[ "$(uname)" == "Darwin" ]]; then
        maybe_sudo dscacheutil -flushcache 2>/dev/null || true
        maybe_sudo killall -HUP mDNSResponder 2>/dev/null || true
    fi
}

# ---- 写入新的 hosts 内容 -----------------------------------------------------
write_hosts() {
    local content="$1"
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$content" > "$tmp"
    maybe_sudo cp "$tmp" "$HOSTS_FILE"
    rm -f "$tmp"
}

cmd_on() {
    local ip
    ip=$(resolve_ip "$1")
    backup_hosts

    local base block
    base=$(strip_block)                     # 先移除旧块 (幂等)
    block="${BEGIN_MARK}
${ip} ${HOSTNAMES}
${END_MARK}"

    write_hosts "${base}
${block}"
    flush_dns

    echo "已启用解析 -> ${ip}:"
    for h in $HOSTNAMES; do echo "  ${ip} ${h}"; done
}

cmd_off() {
    if ! grep -qF "$BEGIN_MARK" "$HOSTS_FILE"; then
        echo "未发现由本脚本管理的条目, 无需改动。"
        return 0
    fi
    backup_hosts
    write_hosts "$(strip_block)"
    flush_dns
    echo "已移除解析, /etc/hosts 恢复原样。"
}

cmd_status() {
    if grep -qF "$BEGIN_MARK" "$HOSTS_FILE"; then
        echo "状态: 已启用。当前条目:"
        awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
            index($0, b) { show = 1; next }
            index($0, e) { show = 0 }
            show         { print "  " $0 }
        ' "$HOSTS_FILE"
    else
        echo "状态: 未启用 (/etc/hosts 中无相关条目)。"
    fi
}

case "${1:-}" in
    on|add|enable)     cmd_on "$2" ;;
    off|remove|disable) cmd_off ;;
    status|"")         cmd_status ;;
    *)
        echo "用法: $0 {on|off|status} [ip]"
        echo "  on [ip]  添加/更新解析 (默认使用 minikube ip)"
        echo "  off      移除解析"
        echo "  status   查看当前状态"
        exit 1
        ;;
esac
