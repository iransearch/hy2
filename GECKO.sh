#!/bin/bash

source <(curl -sSL https://raw.githubusercontent.com/TheyCallMeSecond/config-examples/main/Sing-Box_Config_Installer/Source.sh)

root_check
add_alias
get_cpu_usage
get_ram_usage
get_storage_usage
check_system_info
check_system_ip

processes=("SH:Hysteria2:/etc/hysteria2/server.json" "ST:ShadowTLS:/etc/shadowtls/config.json" "WS:WebSocket:/etc/ws/config.json" "RS:Reality:/etc/reality/config.json" "NS:Naive:/etc/naive/config.json" "TS:TUIC:/etc/tuic/server.json" "GS:gRPC:/etc/grpc/config.json")


apply_hy2_network_and_limits_optimize() {
  echo "======================================================="
  echo " Apply Optimize 10 + 12: Network Settings + System Limits"
  echo "======================================================="

  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    return 1
  fi

  BACKUP_DIR="/root/hy2-optimize-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"

  echo "Creating backups in: $BACKUP_DIR"
  [ -f /etc/sysctl.conf ] && cp -a /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak"
  [ -f /etc/security/limits.conf ] && cp -a /etc/security/limits.conf "$BACKUP_DIR/limits.conf.bak"
  [ -f /etc/profile ] && cp -a /etc/profile "$BACKUP_DIR/profile.bak"

  echo
  echo "[1/2] Applying Network settings optimization..."
  cat > /etc/sysctl.d/99-hysteria2-network-optimize.conf <<'EOF_SYSCTL'
# Hysteria2 / QUIC network optimization
# Equivalent target: Linux Optimizer menu option 10 - Network settings

fs.file-max = 67108864

net.core.default_qdisc = fq
net.core.netdev_max_backlog = 32768
net.core.optmem_max = 262144
net.core.somaxconn = 65536
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576

net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 16384 1048576 33554432
net.ipv4.tcp_wmem = 16384 1048576 33554432
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_orphans = 819200
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 32768
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_syncookies = 1

net.unix.max_dgram_qlen = 256

vm.min_free_kbytes = 65536
vm.swappiness = 10
vm.vfs_cache_pressure = 250
vm.dirty_ratio = 20

net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 16384
net.ipv4.neigh.default.gc_stale_time = 60
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
kernel.panic = 1
EOF_SYSCTL

  # udp_mem exists on many kernels, but not all. Apply only when available to avoid noisy failures.
  if [ -e /proc/sys/net/ipv4/udp_mem ]; then
    cat >> /etc/sysctl.d/99-hysteria2-network-optimize.conf <<'EOF_UDP'
net.ipv4.udp_mem = 65536 1048576 33554432
EOF_UDP
  fi

  modprobe tcp_bbr >/dev/null 2>&1 || true
  echo tcp_bbr > /etc/modules-load.d/99-hysteria2-bbr.conf 2>/dev/null || true

  sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-hysteria2-network-optimize.conf || true

  echo
  echo "[2/2] Applying System Limits optimization..."
  cat > /etc/security/limits.d/99-hysteria2-limits.conf <<'EOF_LIMITS'
# Hysteria2 / high connection count limits
# Equivalent target: Linux Optimizer menu option 12 - System Limits

* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576

* soft nproc 1048576
* hard nproc 1048576
root soft nproc 1048576
root hard nproc 1048576

* soft memlock unlimited
* hard memlock unlimited
root soft memlock unlimited
root hard memlock unlimited
EOF_LIMITS

  mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d
  cat > /etc/systemd/system.conf.d/99-hysteria2-limits.conf <<'EOF_SYSTEMD_SYSTEM'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
EOF_SYSTEMD_SYSTEM

  cat > /etc/systemd/user.conf.d/99-hysteria2-limits.conf <<'EOF_SYSTEMD_USER'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
EOF_SYSTEMD_USER

  # Keep profile ulimit idempotent: remove old block and append a clean one.
  sed -i '/# BEGIN HYSTERIA2 OPTIMIZE LIMITS/,/# END HYSTERIA2 OPTIMIZE LIMITS/d' /etc/profile 2>/dev/null || true
  cat >> /etc/profile <<'EOF_PROFILE'
# BEGIN HYSTERIA2 OPTIMIZE LIMITS
ulimit -n 1048576 2>/dev/null || true
ulimit -u 1048576 2>/dev/null || true
ulimit -l unlimited 2>/dev/null || true
# END HYSTERIA2 OPTIMIZE LIMITS
EOF_PROFILE

  systemctl daemon-reexec >/dev/null 2>&1 || systemctl daemon-reload >/dev/null 2>&1 || true

  # Ensure the custom Hysteria service also has explicit runtime limits.
  if [ -f /etc/systemd/system/hysteria2-gecko.service ]; then
    mkdir -p /etc/systemd/system/hysteria2-gecko.service.d
    cat > /etc/systemd/system/hysteria2-gecko.service.d/override.conf <<'EOF_HY2_LIMITS'
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
EOF_HY2_LIMITS
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl restart hysteria2-gecko.service >/dev/null 2>&1 || true
  fi

  echo
  echo "======================================================="
  echo "Optimize 10 + 12 applied successfully."
  echo "Network sysctl: /etc/sysctl.d/99-hysteria2-network-optimize.conf"
  echo "Limits file:     /etc/security/limits.d/99-hysteria2-limits.conf"
  echo "Backups:         $BACKUP_DIR"
  echo "BBR status:      $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  echo "Current nofile:  $(ulimit -n 2>/dev/null || echo unknown)"
  echo "======================================================="
  echo
  read -rp "Reboot now to fully apply system/user limits? [y/N]: " REBOOT_NOW
  case "$REBOOT_NOW" in
    y|Y|yes|YES|Yes)
      echo "Rebooting..."
      reboot
      ;;
    *)
      echo "Reboot skipped. Recommended: reboot once later."
      ;;
  esac
}


install_hysteria2_gecko_v292() {
  set -e
  HYSTERIA_BIN="/usr/local/bin/hysteria"
  HYSTERIA_DIR="/etc/hysteria2"
  HYSTERIA_CONFIG="$HYSTERIA_DIR/server.yaml"
  HYSTERIA_SERVICE="/etc/systemd/system/hysteria2-gecko.service"
  HYSTERIA_VERSION="v2.9.2"

  detect_hysteria_arch() {
    case "$(uname -m)" in
      x86_64|amd64) echo "amd64" ;;
      aarch64|arm64) echo "arm64" ;;
      armv7l|armv7) echo "armv7" ;;
      armv6l|armv6) echo "armv6" ;;
      i386|i686) echo "386" ;;
      *) echo "unsupported" ;;
    esac
  }

  HY2_ARCH="$(detect_hysteria_arch)"
  if [ "$HY2_ARCH" = "unsupported" ]; then
    echo "Unsupported architecture: $(uname -m)"
    return 1
  fi

  HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/app%2F${HYSTERIA_VERSION}/hysteria-linux-${HY2_ARCH}"

  echo "======================================================="
  echo " Hysteria2 v2.9.2 + Gecko Obfuscation Installer"
  echo "======================================================="

  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    return 1
  fi

  command -v curl >/dev/null 2>&1 || { apt update -y && apt install -y curl; }
  command -v openssl >/dev/null 2>&1 || { apt update -y && apt install -y openssl; }
  command -v python3 >/dev/null 2>&1 || { apt update -y && apt install -y python3; }

  read -rp "Port [2020]: " HY2_PORT
  HY2_PORT="${HY2_PORT:-2020}"
  if ! [[ "$HY2_PORT" =~ ^[0-9]+$ ]] || [ "$HY2_PORT" -lt 1 ] || [ "$HY2_PORT" -gt 65535 ]; then
    echo "Invalid port."
    return 1
  fi

  DEFAULT_AUTH="$(openssl rand -hex 16)"
  read -rp "Auth password [$DEFAULT_AUTH]: " HY2_AUTH
  HY2_AUTH="${HY2_AUTH:-$DEFAULT_AUTH}"

  DEFAULT_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"
  read -rp "Gecko obfs password [$DEFAULT_OBFS]: " HY2_OBFS
  HY2_OBFS="${HY2_OBFS:-$DEFAULT_OBFS}"

  read -rp "SNI / certificate CN [www.google.com]: " HY2_SNI
  HY2_SNI="${HY2_SNI:-www.google.com}"

  # Gecko packet sizes are intentionally not asked from the user.
  # Hysteria defaults are used: minPacketSize=512, maxPacketSize=1200.
  # The official share URI only carries obfs type + password, not packet sizes.
  GECKO_MIN=512
  GECKO_MAX=1200

  read -rp "Remark [HY2-GECKO]: " HY2_REMARK
  HY2_REMARK="${HY2_REMARK:-HY2-GECKO}"

  echo
  echo "Masquerade mode:"
  echo "  1) Disable / default 404"
  echo "  2) Static file website"
  echo "  3) Reverse proxy to a website"
  echo "  4) Simple string response"
  read -rp "Choose masquerade mode [3]: " MASQ_MODE
  MASQ_MODE="${MASQ_MODE:-3}"

  MASQ_CONFIG=""
  case "$MASQ_MODE" in
    1)
      echo "Masquerade disabled. Hysteria will use the default 404 behavior for normal HTTP/3 requests."
      ;;
    2)
      read -rp "Static website directory [/var/www/hysteria2-masq]: " MASQ_DIR
      MASQ_DIR="${MASQ_DIR:-/var/www/hysteria2-masq}"
      mkdir -p "$MASQ_DIR"
      if [ ! -f "$MASQ_DIR/index.html" ]; then
        cat > "$MASQ_DIR/index.html" <<'EOF_STATIC_INDEX'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Welcome</title></head>
<body><h1>Welcome</h1></body>
</html>
EOF_STATIC_INDEX
      fi
      MASQ_DIR_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$MASQ_DIR")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: file
  file:
    dir: $MASQ_DIR_YAML
EOF_MASQ
)
      ;;
    3)
      read -rp "Proxy target URL [https://www.google.com/]: " MASQ_URL
      MASQ_URL="${MASQ_URL:-https://www.google.com/}"
      read -rp "Rewrite Host header? [Y/n]: " MASQ_REWRITE
      MASQ_REWRITE="${MASQ_REWRITE:-Y}"
      case "$MASQ_REWRITE" in
        n|N|no|NO|No) MASQ_REWRITE_BOOL="false" ;;
        *) MASQ_REWRITE_BOOL="true" ;;
      esac
      read -rp "Allow insecure upstream TLS? [y/N]: " MASQ_INSECURE
      MASQ_INSECURE="${MASQ_INSECURE:-N}"
      case "$MASQ_INSECURE" in
        y|Y|yes|YES|Yes) MASQ_INSECURE_BOOL="true" ;;
        *) MASQ_INSECURE_BOOL="false" ;;
      esac
      MASQ_URL_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$MASQ_URL")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL_YAML
    rewriteHost: $MASQ_REWRITE_BOOL
    insecure: $MASQ_INSECURE_BOOL
EOF_MASQ
)
      ;;
    4)
      read -rp "Response text [hello]: " MASQ_TEXT
      MASQ_TEXT="${MASQ_TEXT:-hello}"
      read -rp "HTTP status code [200]: " MASQ_STATUS
      MASQ_STATUS="${MASQ_STATUS:-200}"
      if ! [[ "$MASQ_STATUS" =~ ^[0-9]+$ ]] || [ "$MASQ_STATUS" -lt 100 ] || [ "$MASQ_STATUS" -gt 599 ]; then
        echo "Invalid status code. Using 200."
        MASQ_STATUS=200
      fi
      read -rp "Content-Type [text/plain]: " MASQ_CONTENT_TYPE
      MASQ_CONTENT_TYPE="${MASQ_CONTENT_TYPE:-text/plain}"
      MASQ_TEXT_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$MASQ_TEXT")"
      MASQ_CT_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$MASQ_CONTENT_TYPE")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: string
  string:
    content: $MASQ_TEXT_YAML
    statusCode: $MASQ_STATUS
    headers:
      content-type: $MASQ_CT_YAML
EOF_MASQ
)
      ;;
    *)
      echo "Invalid masquerade mode. Using reverse proxy default."
      MASQ_URL="https://www.google.com/"
      MASQ_URL_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$MASQ_URL")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL_YAML
    rewriteHost: true
    insecure: false
EOF_MASQ
)
      ;;
  esac

  AUTH_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$HY2_AUTH")"
  OBFS_YAML="$(python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$HY2_OBFS")"

  echo "Preparing Hysteria binary install..."
  systemctl stop hysteria2-gecko.service >/dev/null 2>&1 || true
  systemctl stop hysteria-server.service >/dev/null 2>&1 || true
  systemctl stop hysteria.service >/dev/null 2>&1 || true

  # If an old Hysteria process is still running from another service/manual start, stop it.
  if command -v pgrep >/dev/null 2>&1 && pgrep -x hysteria >/dev/null 2>&1; then
    pkill -x hysteria >/dev/null 2>&1 || true
    sleep 1
  fi

  echo "Downloading Hysteria v2.9.2 linux-${HY2_ARCH}..."
  TMP_BIN="$(mktemp /tmp/hysteria-v292.XXXXXX)"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP_BIN" "$HYSTERIA_URL"; then
    rm -f "$TMP_BIN"
    echo "Download failed."
    return 1
  fi
  chmod +x "$TMP_BIN"

  # Atomic replacement prevents 'Text file busy' when the old binary was recently running.
  install -m 0755 "$TMP_BIN" "$HYSTERIA_BIN.new"
  mv -f "$HYSTERIA_BIN.new" "$HYSTERIA_BIN"
  rm -f "$TMP_BIN"

  mkdir -p "$HYSTERIA_DIR"
  echo "Generating self-signed certificate..."
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$HYSTERIA_DIR/server.key" \
    -out "$HYSTERIA_DIR/server.crt" \
    -subj "/CN=$HY2_SNI" \
    -days 3650 >/dev/null 2>&1
  chmod 600 "$HYSTERIA_DIR/server.key"

  cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$HY2_PORT

tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
  sniGuard: disable

auth:
  type: password
  password: $AUTH_YAML

obfs:
  type: gecko
  gecko:
    password: $OBFS_YAML
    minPacketSize: $GECKO_MIN
    maxPacketSize: $GECKO_MAX${MASQ_CONFIG}

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
EOF

  cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria2 Gecko v2.9.2 Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $HYSTERIA_CONFIG
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now hysteria2-gecko.service
  systemctl restart hysteria2-gecko.service

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$HY2_PORT/udp" >/dev/null 2>&1 || true
  fi
  if command -v csf >/dev/null 2>&1; then
    if ! grep -q "^UDP_IN.*$HY2_PORT" /etc/csf/csf.conf 2>/dev/null; then
      sed -i "s/^UDP_IN = \"\(.*\)\"/UDP_IN = \"\1,$HY2_PORT\"/" /etc/csf/csf.conf || true
      csf -r >/dev/null 2>&1 || true
    fi
  fi

  SERVER_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  EN_AUTH="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$HY2_AUTH")"
  EN_OBFS="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$HY2_OBFS")"
  EN_SNI="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$HY2_SNI")"
  EN_REMARK="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$HY2_REMARK")"
  HY2_LINK="hy2://$EN_AUTH@$SERVER_IP:$HY2_PORT?sni=$EN_SNI&insecure=1&Insecure=1&obfs=gecko&obfs-password=$EN_OBFS#$EN_REMARK"

  cat > "$HYSTERIA_DIR/client-link.txt" <<EOF
$HY2_LINK
EOF

  echo
  echo "======================================================="
  echo "Hysteria2 Gecko installed."
  echo "Service: hysteria2-gecko.service"
  echo "Config: $HYSTERIA_CONFIG"
  echo "Link saved: $HYSTERIA_DIR/client-link.txt"
  echo "Note: Gecko packet sizes are server/config defaults and are NOT included in the client URI."
  echo "-------------------------------------------------------"
  echo "$HY2_LINK"
  echo "======================================================="
  echo
  echo "Useful commands:"
  echo "  systemctl status hysteria2-gecko --no-pager"
  echo "  journalctl -u hysteria2-gecko -f"
}


detect_hysteria_arch_global() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    armv6l|armv6) echo "armv6" ;;
    i386|i686) echo "386" ;;
    *) echo "unsupported" ;;
  esac
}

install_hysteria_binary_multiarch_global() {
  HYSTERIA_VERSION_GLOBAL="v2.9.2"
  HYSTERIA_BIN_GLOBAL="/usr/local/bin/hysteria"
  HY2_ARCH_GLOBAL="$(detect_hysteria_arch_global)"

  if [ "$HY2_ARCH_GLOBAL" = "unsupported" ]; then
    echo "Unsupported architecture: $(uname -m)"
    return 1
  fi

  command -v curl >/dev/null 2>&1 || { apt update -y && apt install -y curl; }
  command -v openssl >/dev/null 2>&1 || { apt update -y && apt install -y openssl; }
  command -v python3 >/dev/null 2>&1 || { apt update -y && apt install -y python3; }

  HYSTERIA_URL_GLOBAL="https://github.com/apernet/hysteria/releases/download/app%2F${HYSTERIA_VERSION_GLOBAL}/hysteria-linux-${HY2_ARCH_GLOBAL}"
  echo "Downloading Hysteria ${HYSTERIA_VERSION_GLOBAL} linux-${HY2_ARCH_GLOBAL}..."
  TMP_BIN_GLOBAL="$(mktemp /tmp/hysteria-global.XXXXXX)"

  if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP_BIN_GLOBAL" "$HYSTERIA_URL_GLOBAL"; then
    rm -f "$TMP_BIN_GLOBAL"
    echo "Download failed: $HYSTERIA_URL_GLOBAL"
    return 1
  fi

  chmod +x "$TMP_BIN_GLOBAL"
  install -m 0755 "$TMP_BIN_GLOBAL" "$HYSTERIA_BIN_GLOBAL.new"
  mv -f "$HYSTERIA_BIN_GLOBAL.new" "$HYSTERIA_BIN_GLOBAL"
  rm -f "$TMP_BIN_GLOBAL"
}

install_socat_dep_global() {
  command -v socat >/dev/null 2>&1 && return 0

  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y socat curl python3 ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y socat curl python3 ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum install -y socat curl python3 ca-certificates
  else
    echo "Unsupported package manager. Install socat manually."
    return 1
  fi
}

yaml_quote_hy2_global() {
  python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$1"
}

urlencode_hy2_global() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

b64url_decode_hy2_global() {
  python3 - "$1" <<'PY'
import sys, base64
s = sys.argv[1].strip()
s += "=" * (-len(s) % 4)
print(base64.urlsafe_b64decode(s.encode()).decode())
PY
}

json_get_hy2_global() {
  python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get(sys.argv[1], ""))' "$1"
}

create_hy2_relay_link_global() {
  python3 - "$@" <<'PY'
import sys, json, base64
keys = ["server","port","auth","obfs","obfs_password","sni","remark","version"]
obj = dict(zip(keys, sys.argv[1:]))
obj["obfs"] = "gecko"
raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode()
print("hy2relay://" + base64.urlsafe_b64encode(raw).decode().rstrip("="))
PY
}

parse_hy2_relay_link_to_env_global() {
  LINK="$1"
  if ! echo "$LINK" | grep -q '^hy2relay://'; then
    echo "Invalid relay link. It must start with hy2relay://"
    return 1
  fi

  PAYLOAD="${LINK#hy2relay://}"
  JSON_PAYLOAD="$(b64url_decode_hy2_global "$PAYLOAD")"

  RELAY_KHAREJ_SERVER="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global server)"
  RELAY_KHAREJ_PORT="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global port)"
  RELAY_AUTH="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global auth)"
  RELAY_OBFS="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global obfs)"
  RELAY_OBFS_PASSWORD="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global obfs_password)"
  RELAY_SNI="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global sni)"
  RELAY_REMARK="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global remark)"

  if [ "$RELAY_OBFS" != "gecko" ]; then
    echo "Invalid relay link. Only Gecko obfuscation is allowed."
    return 1
  fi

  if [ -z "$RELAY_KHAREJ_SERVER" ] || [ -z "$RELAY_KHAREJ_PORT" ] || [ -z "$RELAY_AUTH" ] || [ -z "$RELAY_OBFS_PASSWORD" ] || [ -z "$RELAY_SNI" ]; then
    echo "Invalid relay link. Missing required fields."
    return 1
  fi

  export RELAY_KHAREJ_SERVER RELAY_KHAREJ_PORT RELAY_AUTH RELAY_OBFS RELAY_OBFS_PASSWORD RELAY_SNI RELAY_REMARK
}

make_hy2_client_link_global() {
  SERVER_ADDR="$1"
  SERVER_PORT="$2"
  AUTH_VALUE="$3"
  OBFS_VALUE="$4"
  SNI_VALUE="$5"
  REMARK_VALUE="$6"

  EN_AUTH="$(urlencode_hy2_global "$AUTH_VALUE")"
  EN_OBFS="$(urlencode_hy2_global "$OBFS_VALUE")"
  EN_SNI="$(urlencode_hy2_global "$SNI_VALUE")"
  EN_REMARK="$(urlencode_hy2_global "$REMARK_VALUE")"

  echo "hy2://$EN_AUTH@$SERVER_ADDR:$SERVER_PORT?sni=$EN_SNI&insecure=1&Insecure=1&obfs=gecko&obfs-password=$EN_OBFS#$EN_REMARK"
}

install_kharej_main_hysteria_gecko_with_relay_link() {
  clear
  echo "======================================================="
  echo " Install Main Hysteria2 Gecko Server - Kharej"
  echo "======================================================="
  echo "This is the real Hysteria2 Gecko server."
  echo "It generates a hy2relay:// link for the Iran UDP relay."
  echo "======================================================="

  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    return 1
  fi

  HYSTERIA_BIN="/usr/local/bin/hysteria"
  HYSTERIA_DIR="/etc/hysteria2-gecko-main"
  HYSTERIA_CONFIG="$HYSTERIA_DIR/server.yaml"
  HYSTERIA_SERVICE="/etc/systemd/system/hysteria2-gecko-main.service"

  if [ -f "$HYSTERIA_SERVICE" ] || [ -f "$HYSTERIA_CONFIG" ]; then
    echo "Main Gecko server already seems installed."
    read -rp "Reinstall and overwrite config/link? [y/N]: " REINSTALL_MAIN_GECKO
    case "$REINSTALL_MAIN_GECKO" in
      y|Y|yes|YES|Yes) ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  install_hysteria_binary_multiarch_global

  read -rp "Hysteria UDP port on Kharej server [443]: " HY2_SERVER_PORT
  HY2_SERVER_PORT="${HY2_SERVER_PORT:-443}"
  if ! [[ "$HY2_SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$HY2_SERVER_PORT" -lt 1 ] || [ "$HY2_SERVER_PORT" -gt 65535 ]; then
    echo "Invalid port."
    return 1
  fi

  DEFAULT_AUTH="$(openssl rand -hex 16)"
  DEFAULT_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"

  read -rp "Auth password [$DEFAULT_AUTH]: " HY2_AUTH
  HY2_AUTH="${HY2_AUTH:-$DEFAULT_AUTH}"

  read -rp "Gecko obfs password [$DEFAULT_OBFS]: " HY2_OBFS
  HY2_OBFS="${HY2_OBFS:-$DEFAULT_OBFS}"

  read -rp "SNI / certificate CN [www.google.com]: " HY2_SNI
  HY2_SNI="${HY2_SNI:-www.google.com}"

  read -rp "Remark [GECKO-RELAY]: " HY2_REMARK
  HY2_REMARK="${HY2_REMARK:-GECKO-RELAY}"

  echo
  echo "Masquerade mode:"
  echo "  1) Disable / default 404"
  echo "  2) Static file website"
  echo "  3) Reverse proxy to a website"
  echo "  4) Simple string response"
  read -rp "Choose masquerade mode [3]: " MASQ_MODE
  MASQ_MODE="${MASQ_MODE:-3}"

  MASQ_CONFIG=""
  case "$MASQ_MODE" in
    1)
      echo "Masquerade disabled."
      ;;
    2)
      read -rp "Static website directory [/var/www/hysteria2-masq]: " MASQ_DIR
      MASQ_DIR="${MASQ_DIR:-/var/www/hysteria2-masq}"
      mkdir -p "$MASQ_DIR"
      if [ ! -f "$MASQ_DIR/index.html" ]; then
        echo "Welcome" > "$MASQ_DIR/index.html"
      fi
      MASQ_DIR_YAML="$(yaml_quote_hy2_global "$MASQ_DIR")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: file
  file:
    dir: $MASQ_DIR_YAML
EOF_MASQ
)
      ;;
    3)
      read -rp "Proxy target URL [https://www.google.com/]: " MASQ_URL
      MASQ_URL="${MASQ_URL:-https://www.google.com/}"
      MASQ_URL_YAML="$(yaml_quote_hy2_global "$MASQ_URL")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: proxy
  proxy:
    url: $MASQ_URL_YAML
    rewriteHost: true
    insecure: false
EOF_MASQ
)
      ;;
    4)
      read -rp "Response text [hello]: " MASQ_TEXT
      MASQ_TEXT="${MASQ_TEXT:-hello}"
      MASQ_TEXT_YAML="$(yaml_quote_hy2_global "$MASQ_TEXT")"
      MASQ_CONFIG=$(cat <<EOF_MASQ

masquerade:
  type: string
  string:
    content: $MASQ_TEXT_YAML
    statusCode: 200
    headers:
      content-type: text/plain
EOF_MASQ
)
      ;;
    *)
      echo "Invalid masquerade mode."
      return 1
      ;;
  esac

  AUTH_YAML="$(yaml_quote_hy2_global "$HY2_AUTH")"
  OBFS_YAML="$(yaml_quote_hy2_global "$HY2_OBFS")"

  systemctl stop hysteria2-gecko-main.service >/dev/null 2>&1 || true
  mkdir -p "$HYSTERIA_DIR"

  echo "Generating self-signed certificate..."
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$HYSTERIA_DIR/server.key" \
    -out "$HYSTERIA_DIR/server.crt" \
    -subj "/CN=$HY2_SNI" \
    -days 3650 >/dev/null 2>&1
  chmod 600 "$HYSTERIA_DIR/server.key"

  cat > "$HYSTERIA_CONFIG" <<EOF
listen: :$HY2_SERVER_PORT

tls:
  cert: $HYSTERIA_DIR/server.crt
  key: $HYSTERIA_DIR/server.key
  sniGuard: disable

auth:
  type: password
  password: $AUTH_YAML

obfs:
  type: gecko
  gecko:
    password: $OBFS_YAML
    minPacketSize: 512
    maxPacketSize: 1200${MASQ_CONFIG}

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
EOF

  cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Main Hysteria2 Gecko Server for Iran Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $HYSTERIA_CONFIG
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now hysteria2-gecko-main.service
  systemctl restart hysteria2-gecko-main.service

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$HY2_SERVER_PORT/udp" >/dev/null 2>&1 || true
  fi
  if command -v csf >/dev/null 2>&1; then
    if ! grep -q "^UDP_IN.*$HY2_SERVER_PORT" /etc/csf/csf.conf 2>/dev/null; then
      sed -i "s/^UDP_IN = \"\(.*\)\"/UDP_IN = \"\1,$HY2_SERVER_PORT\"/" /etc/csf/csf.conf || true
      csf -r >/dev/null 2>&1 || true
    fi
  fi

  KHAREJ_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  RELAY_LINK="$(create_hy2_relay_link_global "$KHAREJ_IP" "$HY2_SERVER_PORT" "$HY2_AUTH" "gecko" "$HY2_OBFS" "$HY2_SNI" "$HY2_REMARK" "1")"
  DIRECT_CLIENT_LINK="$(make_hy2_client_link_global "$KHAREJ_IP" "$HY2_SERVER_PORT" "$HY2_AUTH" "$HY2_OBFS" "$HY2_SNI" "$HY2_REMARK")"

  cat > "$HYSTERIA_DIR/relay-link.txt" <<EOF
$RELAY_LINK
EOF

  cat > "$HYSTERIA_DIR/direct-client-link.txt" <<EOF
$DIRECT_CLIENT_LINK
EOF

  cat > "$HYSTERIA_DIR/server-info.txt" <<EOF
Kharej Server IP: $KHAREJ_IP
Hysteria UDP Port: $HY2_SERVER_PORT
Auth Password: $HY2_AUTH
Obfs Type: gecko
Gecko Obfs Password: $HY2_OBFS
SNI: $HY2_SNI
Remark: $HY2_REMARK

Relay Link for Iran:
$RELAY_LINK

Direct Client Link to Kharej:
$DIRECT_CLIENT_LINK
EOF

  echo
  echo "======================================================="
  echo "Main Hysteria2 Gecko server installed on KHAREJ."
  echo "Paste this RELAY link on IRAN server:"
  echo "-------------------------------------------------------"
  echo "$RELAY_LINK"
  echo "-------------------------------------------------------"
  echo "Direct client link to Kharej:"
  echo "$DIRECT_CLIENT_LINK"
  echo "Saved:"
  echo "  $HYSTERIA_DIR/relay-link.txt"
  echo "  $HYSTERIA_DIR/direct-client-link.txt"
  echo "======================================================="
}

install_iran_udp_gecko_relay_from_link() {
  clear
  echo "======================================================="
  echo " Install Iran NFTables UDP Relay for Hysteria2 Gecko"
  echo "======================================================="
  echo "Ubuntu optimized mode: nftables DNAT + masquerade + conntrack tuning"
  echo "Iran server does NOT terminate Hysteria."
  echo "Only one UDP input port is forwarded. No TUN, no full-system tunnel."
  echo "======================================================="

  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    return 1
  fi

  RELAY_DIR="/etc/hysteria2-gecko-udp-relay"
  RELAY_SERVICE="/etc/systemd/system/hysteria2-gecko-udp-relay.service"
  RELAY_ENV="$RELAY_DIR/relay.env"
  NFT_CONF="/etc/nftables.d/hy2-gecko-relay.nft"
  RELAY_APPLY="/usr/local/sbin/hy2-gecko-relay-apply.sh"
  RELAY_REMOVE="/usr/local/sbin/hy2-gecko-relay-remove.sh"
  SYSCTL_CONF="/etc/sysctl.d/99-hy2-gecko-relay-optimize.conf"

  if [ -f "$RELAY_SERVICE" ] || [ -d "$RELAY_DIR" ]; then
    echo "Iran UDP relay already seems installed."
    read -rp "Reinstall and overwrite relay config? [y/N]: " REINSTALL_IRAN_RELAY
    case "$REINSTALL_IRAN_RELAY" in
      y|Y|yes|YES|Yes)
        systemctl disable --now hysteria2-gecko-udp-relay.service >/dev/null 2>&1 || true
        [ -x "$RELAY_REMOVE" ] && "$RELAY_REMOVE" >/dev/null 2>&1 || true
        ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y nftables curl python3 ca-certificates conntrack iproute2
  else
    echo "This optimized relay mode is prepared for Ubuntu/Debian apt systems."
    return 1
  fi

  read -rp "Paste hy2relay:// link from Kharej: " RELAY_LINK_INPUT
  parse_hy2_relay_link_to_env_global "$RELAY_LINK_INPUT" || return 1

  echo
  echo "Parsed Gecko relay link:"
  echo "  Kharej Hysteria Server: $RELAY_KHAREJ_SERVER:$RELAY_KHAREJ_PORT"
  echo "  Obfs:                   gecko"
  echo "  SNI:                    $RELAY_SNI"
  echo

  read -rp "Iran input UDP port for users [${RELAY_KHAREJ_PORT}]: " IRAN_INPUT_PORT
  IRAN_INPUT_PORT="${IRAN_INPUT_PORT:-$RELAY_KHAREJ_PORT}"
  if ! [[ "$IRAN_INPUT_PORT" =~ ^[0-9]+$ ]] || [ "$IRAN_INPUT_PORT" -lt 1 ] || [ "$IRAN_INPUT_PORT" -gt 65535 ]; then
    echo "Invalid Iran input port."
    return 1
  fi

  DEFAULT_IFACE="$(ip route get "$RELAY_KHAREJ_SERVER" 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
  DEFAULT_IFACE="${DEFAULT_IFACE:-$(ip route | awk '/default/ {print $5; exit}')}"
  read -rp "Iran outgoing interface [$DEFAULT_IFACE]: " RELAY_IFACE
  RELAY_IFACE="${RELAY_IFACE:-$DEFAULT_IFACE}"

  if [ -z "$RELAY_IFACE" ]; then
    echo "Could not detect outgoing interface."
    return 1
  fi

  read -rp "Apply UDP/conntrack performance tuning? [Y/n]: " APPLY_TUNE
  APPLY_TUNE="${APPLY_TUNE:-Y}"

  mkdir -p "$RELAY_DIR" /etc/nftables.d

  cat > "$RELAY_ENV" <<EOF
IRAN_INPUT_PORT="$IRAN_INPUT_PORT"
KHAREJ_IP="$RELAY_KHAREJ_SERVER"
KHAREJ_PORT="$RELAY_KHAREJ_PORT"
RELAY_IFACE="$RELAY_IFACE"
NFT_CONF="$NFT_CONF"
EOF

  cat > "$NFT_CONF" <<EOF
table inet hy2_gecko_relay {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$RELAY_IFACE" udp dport $IRAN_INPUT_PORT dnat ip to $RELAY_KHAREJ_SERVER:$RELAY_KHAREJ_PORT
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "$RELAY_IFACE" ip daddr $RELAY_KHAREJ_SERVER udp dport $RELAY_KHAREJ_PORT masquerade
  }

  chain forward {
    type filter hook forward priority filter; policy accept;
    ip daddr $RELAY_KHAREJ_SERVER udp dport $RELAY_KHAREJ_PORT accept
    ip saddr $RELAY_KHAREJ_SERVER udp sport $RELAY_KHAREJ_PORT accept
  }
}
EOF

  cat > "$RELAY_APPLY" <<'EOF'
#!/usr/bin/env bash
set -e
. /etc/hysteria2-gecko-udp-relay/relay.env

sysctl -w net.ipv4.ip_forward=1 >/dev/null

nft delete table inet hy2_gecko_relay >/dev/null 2>&1 || true
nft -f "$NFT_CONF"
EOF
  chmod +x "$RELAY_APPLY"

  cat > "$RELAY_REMOVE" <<'EOF'
#!/usr/bin/env bash
set +e
nft delete table inet hy2_gecko_relay >/dev/null 2>&1 || true
EOF
  chmod +x "$RELAY_REMOVE"

  if [[ "$APPLY_TUNE" =~ ^[Yy] ]]; then
    cat > "$SYSCTL_CONF" <<'EOF_SYSCTL'
# Hysteria2 Gecko UDP relay tuning
net.ipv4.ip_forward = 1

# UDP/QUIC buffers
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Queue/backlog
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# Conntrack for UDP relay
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180

# Avoid strict reverse-path filtering breaking NAT/relay on some VPS networks
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# General
net.ipv4.ip_local_port_range = 1024 65535
EOF_SYSCTL

    modprobe nf_conntrack >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true
  else
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
  fi

  systemctl enable --now nftables >/dev/null 2>&1 || true

  cat > "$RELAY_SERVICE" <<EOF
[Unit]
Description=Iran NFTables UDP Relay to Kharej Hysteria2 Gecko Server
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=$RELAY_ENV
ExecStart=$RELAY_APPLY
ExecStop=$RELAY_REMOVE

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now hysteria2-gecko-udp-relay.service

  # Persist custom nft include if not already referenced
  if [ -f /etc/nftables.conf ] && ! grep -q 'include "/etc/nftables.d/\*.nft"' /etc/nftables.conf; then
    cp -a /etc/nftables.conf "/etc/nftables.conf.bak.$(date +%Y%m%d-%H%M%S)" || true
    printf '\ninclude "/etc/nftables.d/*.nft"\n' >> /etc/nftables.conf
  fi

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$IRAN_INPUT_PORT/udp" >/dev/null 2>&1 || true
    ufw route allow proto udp to "$RELAY_KHAREJ_SERVER" port "$RELAY_KHAREJ_PORT" >/dev/null 2>&1 || true
  fi

  IRAN_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  FINAL_REMARK="${RELAY_REMARK:-GECKO-IRAN-RELAY}"
  FINAL_CLIENT_LINK="$(make_hy2_client_link_global "$IRAN_IP" "$IRAN_INPUT_PORT" "$RELAY_AUTH" "$RELAY_OBFS_PASSWORD" "$RELAY_SNI" "$FINAL_REMARK")"

  cat > "$RELAY_DIR/relay-info.txt" <<EOF
Relay Type: nftables DNAT UDP optimized
Kharej Hysteria Gecko Server: $RELAY_KHAREJ_SERVER:$RELAY_KHAREJ_PORT
Iran UDP Listen Port: $IRAN_INPUT_PORT
Iran Interface: $RELAY_IFACE
Auth Password: $RELAY_AUTH
Gecko Obfs Password: $RELAY_OBFS_PASSWORD
SNI: $RELAY_SNI
Remark: $FINAL_REMARK
NFT Config: $NFT_CONF
Sysctl Config: $SYSCTL_CONF

Client link through Iran:
$FINAL_CLIENT_LINK

Original Relay Link:
$RELAY_LINK_INPUT
EOF

  cat > "$RELAY_DIR/client-link-through-iran.txt" <<EOF
$FINAL_CLIENT_LINK
EOF

  echo
  echo "======================================================="
  echo "Iran NFTables UDP Gecko relay installed."
  echo "Users should connect to IRAN, not Kharej:"
  echo "-------------------------------------------------------"
  echo "$FINAL_CLIENT_LINK"
  echo "-------------------------------------------------------"
  echo "Meaning:"
  echo "  Client Address:     $IRAN_IP"
  echo "  Client UDP Port:    $IRAN_INPUT_PORT"
  echo "  Backend Kharej:     $RELAY_KHAREJ_SERVER:$RELAY_KHAREJ_PORT"
  echo "  Relay Interface:    $RELAY_IFACE"
  echo "  Relay Type:         nftables DNAT + masquerade"
  echo "======================================================="
  echo "Recommended next step on Kharej: run Optimize menu option 4 once."
  echo "======================================================="
}

show_kharej_relay_link() {
  clear
  echo "======================================================="
  echo " Kharej Relay Link"
  echo "======================================================="
  if [ -f /etc/hysteria2-gecko-main/relay-link.txt ]; then
    cat /etc/hysteria2-gecko-main/relay-link.txt
  else
    echo "Relay link not found. Install Main Gecko Server on Kharej first."
  fi
}

show_iran_client_link() {
  clear
  echo "======================================================="
  echo " Client Link Through Iran Relay"
  echo "======================================================="
  if [ -f /etc/hysteria2-gecko-udp-relay/client-link-through-iran.txt ]; then
    cat /etc/hysteria2-gecko-udp-relay/client-link-through-iran.txt
  else
    echo "Client link not found. Install Iran UDP Relay first."
  fi
}

show_gecko_relay_status() {
  clear
  echo "======================================================="
  echo " Gecko Relay Status"
  echo "======================================================="
  echo
  echo "[Kharej Main Hysteria2 Gecko Server]"
  systemctl status hysteria2-gecko-main.service --no-pager 2>/dev/null || echo "hysteria2-gecko-main.service not installed."
  echo
  echo "[Iran UDP Relay]"
  systemctl status hysteria2-gecko-udp-relay.service --no-pager 2>/dev/null || echo "hysteria2-gecko-udp-relay.service not installed."
}

restart_gecko_relay_services() {
  clear
  systemctl restart hysteria2-gecko-main.service >/dev/null 2>&1 || true
  systemctl restart hysteria2-gecko-udp-relay.service >/dev/null 2>&1 || true
  show_gecko_relay_status
}

stop_gecko_relay_services() {
  clear
  systemctl stop hysteria2-gecko-main.service >/dev/null 2>&1 || true
  systemctl stop hysteria2-gecko-udp-relay.service >/dev/null 2>&1 || true
  show_gecko_relay_status
}

uninstall_gecko_relay_services() {
  clear
  echo "======================================================="
  echo " Uninstall Gecko Relay Services"
  echo "======================================================="
  echo "This removes only:"
  echo "  - hysteria2-gecko-main.service"
  echo "  - hysteria2-gecko-udp-relay.service"
  echo "It does NOT remove the old /etc/hysteria2 installation."
  read -rp "Continue? [y/N]: " CONFIRM
  case "$CONFIRM" in
    y|Y|yes|YES|Yes)
      systemctl disable --now hysteria2-gecko-main.service >/dev/null 2>&1 || true
      systemctl disable --now hysteria2-gecko-udp-relay.service >/dev/null 2>&1 || true
      [ -x /usr/local/sbin/hy2-gecko-relay-remove.sh ] && /usr/local/sbin/hy2-gecko-relay-remove.sh >/dev/null 2>&1 || true
      rm -f /usr/local/sbin/hy2-gecko-relay-apply.sh /usr/local/sbin/hy2-gecko-relay-remove.sh
      rm -f /etc/nftables.d/hy2-gecko-relay.nft /etc/sysctl.d/99-hy2-gecko-relay-optimize.conf
      rm -f /etc/systemd/system/hysteria2-gecko-main.service
      rm -f /etc/systemd/system/hysteria2-gecko-udp-relay.service
      rm -rf /etc/hysteria2-gecko-main
      rm -rf /etc/hysteria2-gecko-udp-relay
      systemctl daemon-reload
      echo "Gecko relay services removed."
      ;;
    *)
      echo "Cancelled."
      ;;
  esac
}

hysteria2_gecko_relay_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " Hysteria2 Gecko Two-Server Relay Menu"
    echo "======================================================="
    echo "Architecture:"
    echo "  Client -> Iran NFTables UDP Relay -> Kharej Hysteria2 Gecko Server"
    echo
    echo " 1) Kharej: Install Main Hysteria2 Gecko Server + Generate Relay Link"
    echo " 2) Kharej: Show Relay Link"
    echo " 3) Iran:   Install UDP Relay from Relay Link"
    echo " 4) Iran:   Show Final Client Link Through Iran"
    echo " 5) Status"
    echo " 6) Restart services"
    echo " 7) Stop services"
    echo " 8) Uninstall relay services"
    echo " 0) Back"
    echo "======================================================="
    echo "Gecko-only: no normal/no-obfs mode."
    echo "Iran changes no system route; only one UDP input port is relayed."
    echo "======================================================="
    read -rp "Choose: " RELAY_CHOICE

    case "$RELAY_CHOICE" in
      1) install_kharej_main_hysteria_gecko_with_relay_link; read -rp "Press Enter to return to relay menu..." ;;
      2) show_kharej_relay_link; read -rp "Press Enter to return to relay menu..." ;;
      3) install_iran_udp_gecko_relay_from_link; read -rp "Press Enter to return to relay menu..." ;;
      4) show_iran_client_link; read -rp "Press Enter to return to relay menu..." ;;
      5) show_gecko_relay_status; read -rp "Press Enter to return to relay menu..." ;;
      6) restart_gecko_relay_services; read -rp "Press Enter to return to relay menu..." ;;
      7) stop_gecko_relay_services; read -rp "Press Enter to return to relay menu..." ;;
      8) uninstall_gecko_relay_services; read -rp "Press Enter to return to relay menu..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
}


# =======================================================
# Hysteria2 Gecko Port Hop - Kharej only
# =======================================================
urlencode_hy2_porthop() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

extract_hy2_server_config_values_porthop() {
  python3 <<'PY'
import os, re, sys, subprocess

files = [
    "/etc/hysteria2-gecko-main/server.yaml",
    "/etc/hysteria2/server.yaml",
    "/etc/hysteria2-gecko-tunnel-server/server.yaml",
]
cfg = next((p for p in files if os.path.exists(p)), "")
if not cfg:
    raise SystemExit(1)

text = open(cfg, encoding="utf-8", errors="ignore").read()

def sh(s):
    return "'" + str(s).replace("'", "'\"'\"'") + "'"

def clean(v):
    v = (v or "").strip()
    if "#" in v:
        v = v.split("#", 1)[0].strip()
    if len(v) >= 2 and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
        v = v[1:-1]
    return v.strip()

def top_value(key):
    m = re.search(r'(?m)^\s*' + re.escape(key) + r'\s*:\s*(.+?)\s*$', text)
    return clean(m.group(1)) if m else ""

listen = top_value("listen")
port = ""
m = re.search(r':\s*(\d+)', listen)
if m:
    port = m.group(1)

# Auth password: prefer password inside auth block; fallback to first password in file
auth = ""
m = re.search(r'(?ms)^\s*auth\s*:\s*\n(?P<body>.*?)(?=^\S|\Z)', text)
if m:
    mm = re.search(r'(?m)^\s+password\s*:\s*(.+?)\s*$', m.group("body"))
    if mm:
        auth = clean(mm.group(1))

all_passwords = [clean(x) for x in re.findall(r'(?m)^\s*password\s*:\s*(.+?)\s*$', text)]
if not auth and all_passwords:
    auth = all_passwords[0]

# Gecko obfs password:
# 1) Prefer password in obfs/gecko area before quic/masquerade/etc.
obfs = ""
m = re.search(r'(?ms)^\s*obfs\s*:\s*\n(?P<body>.*?)(?=^(?:quic|bandwidth|ignoreClientBandwidth|disableUDP|masquerade|tls|auth|listen)\s*:|\Z)', text)
if m:
    body = m.group("body")
    # password may be under gecko/password or directly under obfs in some builds
    mm = re.search(r'(?m)^\s*password\s*:\s*(.+?)\s*$', body)
    if mm:
        obfs = clean(mm.group(1))

# 2) If there are two password keys, usually auth is first and obfs is second
if not obfs and len(all_passwords) >= 2:
    obfs = all_passwords[1]

# 3) Some files may include obfs-password in comments/link text
if not obfs:
    mm = re.search(r'obfs-password=([^&#\s]+)', text)
    if mm:
        import urllib.parse
        obfs = urllib.parse.unquote(mm.group(1))

# SNI:
sni = ""
m = re.search(r'(?ms)^\s*tls\s*:\s*\n(?P<body>.*?)(?=^(?:auth|obfs|quic|bandwidth|masquerade|listen)\s*:|\Z)', text)
if m:
    mm = re.search(r'(?m)^\s*sni\s*:\s*(.+?)\s*$', m.group("body"))
    if mm:
        sni = clean(mm.group(1))

# If sni not explicitly in yaml, try reading CN from cert file
if not sni:
    for cert in ["/etc/hysteria2-gecko-main/server.crt", "/etc/hysteria2/server.crt", "/etc/hysteria2-gecko-tunnel-server/server.crt"]:
        if os.path.exists(cert):
            try:
                out = subprocess.check_output(["openssl", "x509", "-noout", "-subject", "-in", cert], text=True, stderr=subprocess.DEVNULL)
                mm = re.search(r'CN\s*=\s*([^,\n/]+)', out)
                if mm:
                    sni = clean(mm.group(1))
                    break
            except Exception:
                pass

print("PH_CONFIG_FILE=" + sh(cfg))
print("PH_MAIN_PORT=" + sh(port))
print("PH_AUTH=" + sh(auth))
print("PH_OBFS_PASS=" + sh(obfs))
print("PH_SNI=" + sh(sni))
PY
}

extract_hy2_link_values_porthop() {
  python3 <<'PY'
import os, re, urllib.parse, sys

files = [
    "/etc/hysteria2-gecko-main/direct-client-link.txt",
    "/etc/hysteria2/client-link.txt",
    "/etc/hysteria2-gecko-main/server-info.txt",
    "/etc/hysteria2-gecko-main/relay-info.txt",
    "/etc/hysteria2-gecko-tunnel-server/tunnel-server-info.txt",
    "/etc/hysteria2-gecko-tunnel-server/tunnel-link.txt",
    "/etc/hysteria2-gecko-porthop/mport-link.txt",
    "/etc/hysteria2-gecko-porthop/info.txt",
]

def sh(s):
    return "'" + str(s).replace("'", "'\"'\"'") + "'"

def clean(s):
    s = (s or "").strip()
    if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        s = s[1:-1]
    return s.strip()

combined = ""
for p in files:
    if os.path.exists(p):
        combined += "\n" + open(p, encoding="utf-8", errors="ignore").read()

link = ""
m = re.search(r'hy2://[^\s]+', combined)
if m:
    link = m.group(0).strip()

if link:
    try:
        rest = link[len("hy2://"):]
        before, after = rest.split("?", 1)
        auth, hostport = before.split("@", 1)
        auth = urllib.parse.unquote(auth)
        if "#" in after:
            query, remark = after.split("#", 1)
            remark = urllib.parse.unquote(remark)
        else:
            query, remark = after, ""
        qs = urllib.parse.parse_qs(query)
        server, port = hostport.rsplit(":", 1)
        # if port is a range in a previous mport link, main port is still before ? not mport; keep as-is if numeric only
        print("PH_SERVER=" + sh(server))
        print("PH_MAIN_PORT=" + sh(port))
        print("PH_AUTH=" + sh(auth))
        print("PH_SNI=" + sh(qs.get("sni", [""])[0]))
        print("PH_OBFS_PASS=" + sh(qs.get("obfs-password", [""])[0]))
        print("PH_REMARK=" + sh(remark or "HY2"))
        raise SystemExit(0)
    except Exception:
        pass

# Fallback: parse server-info style labels
labels = {
    "PH_SERVER": [r'Kharej Server IP:\s*(\S+)', r'Outside Server IP:\s*(\S+)', r'Server IP:\s*(\S+)'],
    "PH_MAIN_PORT": [r'Hysteria UDP Port:\s*(\d+)', r'Main Hysteria Port:\s*(\d+)'],
    "PH_AUTH": [r'Auth Password:\s*(\S+)'],
    "PH_OBFS_PASS": [r'Gecko Obfs Password:\s*(\S+)', r'Obfs Password:\s*(\S+)', r'Gecko Password:\s*(\S+)'],
    "PH_SNI": [r'SNI:\s*(\S+)'],
    "PH_REMARK": [r'Remark:\s*(.+)'],
}
found = {}
for k, pats in labels.items():
    for pat in pats:
        mm = re.search(pat, combined)
        if mm:
            found[k] = clean(mm.group(1))
            break

if not found:
    raise SystemExit(1)

for k in ["PH_SERVER", "PH_MAIN_PORT", "PH_AUTH", "PH_SNI", "PH_OBFS_PASS", "PH_REMARK"]:
    print(k + "=" + sh(found.get(k, "")))
PY
}

detect_hy2_gecko_values_porthop() {
  PH_CONFIG_FILE=""; PH_SERVER=""; PH_MAIN_PORT=""; PH_AUTH=""; PH_OBFS_PASS=""; PH_SNI=""; PH_REMARK="HY2"
  if extract_hy2_server_config_values_porthop >/tmp/hy2_porthop_cfg.env 2>/dev/null; then . /tmp/hy2_porthop_cfg.env; fi
  if extract_hy2_link_values_porthop >/tmp/hy2_porthop_link.env 2>/dev/null; then . /tmp/hy2_porthop_link.env; fi
  [ -n "$PH_SERVER" ] || PH_SERVER="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  [ -n "$PH_SNI" ] || PH_SNI="www.google.com"
  [ -n "$PH_REMARK" ] || PH_REMARK="HY2"
  export PH_CONFIG_FILE PH_SERVER PH_MAIN_PORT PH_AUTH PH_OBFS_PASS PH_SNI PH_REMARK
}

validate_port_hop_values() {
  [ -n "$PH_MAIN_PORT" ] && [[ "$PH_MAIN_PORT" =~ ^[0-9]+$ ]] || { echo "Could not detect Main Hysteria Port."; return 1; }
  [ -n "$PH_AUTH" ] || { echo "Could not detect Auth password."; return 1; }
  [ -n "$PH_OBFS_PASS" ] || { echo "Could not detect Gecko obfs password."; return 1; }
  [ -n "$PH_SNI" ] || { echo "Could not detect SNI."; return 1; }
}

make_gecko_mport_link_porthop() {
  EN_AUTH="$(urlencode_hy2_porthop "$PH_AUTH")"; EN_SNI="$(urlencode_hy2_porthop "$PH_SNI")"; EN_OBFS="$(urlencode_hy2_porthop "$PH_OBFS_PASS")"; EN_REMARK="$(urlencode_hy2_porthop "$PH_REMARK")"
  echo "hy2://$EN_AUTH@$PH_SERVER:$PH_MAIN_PORT?sni=$EN_SNI&insecure=1&allowInsecure=1&obfs=gecko&obfs-password=$EN_OBFS&mport=$PH_HOP_START-$PH_HOP_END#$EN_REMARK"
}

enable_hysteria2_gecko_port_hop() {
  clear
  echo "======================================================="
  echo " Enable Hysteria2 Gecko Port Hop - Kharej only"
  echo "======================================================="
  echo "This is NOT tunnel/relay mode. It redirects UDP hop range to main local Hysteria port."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  detect_hy2_gecko_values_porthop
  if ! validate_port_hop_values; then
    echo
    echo "Auto-detection was incomplete. Please enter only missing values."
    [ -n "$PH_MAIN_PORT" ] || read -rp "Main Hysteria Port: " PH_MAIN_PORT
    [ -n "$PH_AUTH" ] || read -rp "Auth password: " PH_AUTH
    [ -n "$PH_OBFS_PASS" ] || read -rp "Gecko obfs password: " PH_OBFS_PASS
    [ -n "$PH_SNI" ] || read -rp "SNI [www.google.com]: " PH_SNI
    PH_SNI="${PH_SNI:-www.google.com}"
    validate_port_hop_values || { echo "Required values are still missing."; return 1; }
  fi
  echo "Detected: Server=$PH_SERVER MainPort=$PH_MAIN_PORT Obfs=gecko SNI=$PH_SNI Remark=$PH_REMARK"
  read -rp "Hop range start [30000]: " PH_HOP_START; PH_HOP_START="${PH_HOP_START:-30000}"
  read -rp "Hop range end [45000]: " PH_HOP_END; PH_HOP_END="${PH_HOP_END:-45000}"
  if ! [[ "$PH_HOP_START" =~ ^[0-9]+$ ]] || ! [[ "$PH_HOP_END" =~ ^[0-9]+$ ]] || [ "$PH_HOP_START" -lt 1 ] || [ "$PH_HOP_END" -gt 65535 ] || [ "$PH_HOP_START" -gt "$PH_HOP_END" ]; then echo "Invalid port range."; return 1; fi
  if [ "$PH_MAIN_PORT" -ge "$PH_HOP_START" ] && [ "$PH_MAIN_PORT" -le "$PH_HOP_END" ]; then echo "Main port must not be inside hop range."; return 1; fi
  command -v nft >/dev/null 2>&1 || { apt update -y && apt install -y nftables curl python3 ca-certificates; }
  mkdir -p /etc/nftables.d /etc/hysteria2-gecko-porthop
  cat > /etc/hysteria2-gecko-porthop/porthop.env <<EOF
PH_MAIN_PORT="$PH_MAIN_PORT"
PH_HOP_START="$PH_HOP_START"
PH_HOP_END="$PH_HOP_END"
PH_SERVER="$PH_SERVER"
PH_SNI="$PH_SNI"
PH_REMARK="$PH_REMARK"
EOF
  cat > /etc/nftables.d/hy2-gecko-porthop.nft <<EOF
table inet hy2_gecko_porthop {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    udp dport $PH_HOP_START-$PH_HOP_END redirect to :$PH_MAIN_PORT
  }
}
EOF
  cat > /usr/local/sbin/hy2-gecko-porthop-apply.sh <<'EOF'
#!/usr/bin/env bash
set -e
nft delete table inet hy2_gecko_porthop >/dev/null 2>&1 || true
nft -f /etc/nftables.d/hy2-gecko-porthop.nft
EOF
  chmod +x /usr/local/sbin/hy2-gecko-porthop-apply.sh
  cat > /usr/local/sbin/hy2-gecko-porthop-remove.sh <<'EOF'
#!/usr/bin/env bash
set +e
nft delete table inet hy2_gecko_porthop >/dev/null 2>&1 || true
EOF
  chmod +x /usr/local/sbin/hy2-gecko-porthop-remove.sh
  cat > /etc/systemd/system/hysteria2-gecko-porthop.service <<'EOF'
[Unit]
Description=Hysteria2 Gecko Port Hop NFT Redirect
After=network-online.target nftables.service
Wants=network-online.target nftables.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/hy2-gecko-porthop-apply.sh
ExecStop=/usr/local/sbin/hy2-gecko-porthop-remove.sh

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now nftables >/dev/null 2>&1 || true
  if [ -f /etc/nftables.conf ] && ! grep -q 'include "/etc/nftables.d/\*.nft"' /etc/nftables.conf; then cp -a /etc/nftables.conf "/etc/nftables.conf.bak.$(date +%Y%m%d-%H%M%S)" || true; printf '\ninclude "/etc/nftables.d/*.nft"\n' >> /etc/nftables.conf; fi
  systemctl daemon-reload; systemctl enable --now hysteria2-gecko-porthop.service; systemctl restart hysteria2-gecko-porthop.service
  if command -v ufw >/dev/null 2>&1; then ufw allow "$PH_MAIN_PORT/udp" >/dev/null 2>&1 || true; ufw allow "$PH_HOP_START:$PH_HOP_END/udp" >/dev/null 2>&1 || true; fi
  PH_LINK="$(make_gecko_mport_link_porthop)"
  echo "$PH_LINK" > /etc/hysteria2-gecko-porthop/mport-link.txt
  cat > /etc/hysteria2-gecko-porthop/info.txt <<EOF
Main Hysteria Port: $PH_MAIN_PORT
Hop Range: $PH_HOP_START-$PH_HOP_END
Server IP: $PH_SERVER
SNI: $PH_SNI
Remark: $PH_REMARK
Obfs: gecko
NFT Config: /etc/nftables.d/hy2-gecko-porthop.nft

mport Link:
$PH_LINK
EOF
  echo; echo "======================================================="; echo "Gecko Port Hop enabled."; echo "UDP $PH_HOP_START-$PH_HOP_END -> local UDP $PH_MAIN_PORT"; echo; echo "mport Link:"; echo "$PH_LINK"; echo "======================================================="
}

disable_hysteria2_gecko_port_hop() {
  clear; echo "Disabling Hysteria2 Gecko Port Hop..."
  systemctl disable --now hysteria2-gecko-porthop.service >/dev/null 2>&1 || true
  [ -x /usr/local/sbin/hy2-gecko-porthop-remove.sh ] && /usr/local/sbin/hy2-gecko-porthop-remove.sh >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/hysteria2-gecko-porthop.service /usr/local/sbin/hy2-gecko-porthop-apply.sh /usr/local/sbin/hy2-gecko-porthop-remove.sh /etc/nftables.d/hy2-gecko-porthop.nft
  rm -rf /etc/hysteria2-gecko-porthop
  systemctl daemon-reload
  echo "Gecko Port Hop disabled."
}

show_hysteria2_gecko_port_hop() {
  clear; echo "======================================================="; echo " Hysteria2 Gecko Port Hop Status"; echo "======================================================="
  systemctl status hysteria2-gecko-porthop.service --no-pager 2>/dev/null || echo "hysteria2-gecko-porthop.service not installed."
  echo; echo "[NFT rules]"; nft list table inet hy2_gecko_porthop 2>/dev/null || echo "No hy2_gecko_porthop nft table."
  echo; echo "[Saved info]"; [ -f /etc/hysteria2-gecko-porthop/info.txt ] && cat /etc/hysteria2-gecko-porthop/info.txt || echo "No saved info."
}

generate_hysteria2_gecko_mport_link() {
  clear; echo "======================================================="; echo " Generate Hysteria2 Gecko mport Link"; echo "======================================================="
  detect_hy2_gecko_values_porthop
  if ! validate_port_hop_values; then
    echo
    echo "Auto-detection was incomplete. Please enter only missing values."
    [ -n "$PH_MAIN_PORT" ] || read -rp "Main Hysteria Port: " PH_MAIN_PORT
    [ -n "$PH_AUTH" ] || read -rp "Auth password: " PH_AUTH
    [ -n "$PH_OBFS_PASS" ] || read -rp "Gecko obfs password: " PH_OBFS_PASS
    [ -n "$PH_SNI" ] || read -rp "SNI [www.google.com]: " PH_SNI
    PH_SNI="${PH_SNI:-www.google.com}"
    validate_port_hop_values || return 1
  fi
  if [ -f /etc/hysteria2-gecko-porthop/porthop.env ]; then . /etc/hysteria2-gecko-porthop/porthop.env; else read -rp "Hop range start [30000]: " PH_HOP_START; PH_HOP_START="${PH_HOP_START:-30000}"; read -rp "Hop range end [45000]: " PH_HOP_END; PH_HOP_END="${PH_HOP_END:-45000}"; fi
  PH_LINK="$(make_gecko_mport_link_porthop)"
  echo "$PH_LINK"
  mkdir -p /etc/hysteria2-gecko-porthop; echo "$PH_LINK" > /etc/hysteria2-gecko-porthop/mport-link.txt
}

hysteria2_gecko_porthop_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " Hysteria2 Gecko Port Hop Menu - Kharej only"
    echo "======================================================="
    echo " 1) Enable Gecko Port Hop"
    echo " 2) Disable Gecko Port Hop"
    echo " 3) Show Port Hop Rules/Status"
    echo " 4) Generate Gecko mport Link"
    echo " 0) Back"
    echo "======================================================="
    echo "Auto-detects Main Port/Auth/Gecko Password/SNI/Remark. Only asks for Hop Range."
    echo "======================================================="
    read -rp "Choose: " PH_CHOICE
    case "$PH_CHOICE" in
      1) enable_hysteria2_gecko_port_hop; read -rp "Press Enter to return to Port Hop menu..." ;;
      2) disable_hysteria2_gecko_port_hop; read -rp "Press Enter to return to Port Hop menu..." ;;
      3) show_hysteria2_gecko_port_hop; read -rp "Press Enter to return to Port Hop menu..." ;;
      4) generate_hysteria2_gecko_mport_link; read -rp "Press Enter to return to Port Hop menu..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
}

while true; do
  echo "
╭━━━╮╱╱╱╱╱╱╱╱╱╭━━╮╱╱╱╱╱╱╱╭━━━╮╱╱╱╱╱╭━╮╱╱╱╱╭━━╮╱╱╱╱╱╭╮╱╱╱╭╮╭╮
┃╭━╮┃╱╱╱╱╱╱╱╱╱┃╭╮┃╱╱╱╱╱╱╱┃╭━╮┃╱╱╱╱╱┃╭╯╱╱╱╱╰┫┣╯╱╱╱╱╭╯╰╮╱╱┃┃┃┃
┃╰━━┳┳━╮╭━━╮╱╱┃╰╯╰┳━━┳╮╭╮┃┃╱╰╋━━┳━┳╯╰┳┳━━╮╱┃┃╭━╮╭━┻╮╭╋━━┫┃┃┃╭━━┳━╮
╰━━╮┣┫╭╮┫╭╮┣━━┫╭━╮┃╭╮┣╋╋╯┃┃╱╭┫╭╮┃╭╋╮╭╋┫╭╮┃╱┃┃┃╭╮┫━━┫┃┃╭╮┃┃┃┃┃┃━┫╭╯
┃╰━╯┃┃┃┃┃╰╯┣━━┫╰━╯┃╰╯┣╋╋╮┃╰━╯┃╰╯┃┃┃┃┃┃┃╰╯┃╭┫┣┫┃┃┣━━┃╰┫╭╮┃╰┫╰┫┃━┫┃
╰━━━┻┻╯╰┻━╮┃╱╱╰━━━┻━━┻╯╰╯╰━━━┻━━┻╯╰┻╯╰┻━╮┃╰━━┻╯╰┻━━┻━┻╯╰┻━┻━┻━━┻╯
╱╱╱╱╱╱╱╱╭━╯┃╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╭━╯┃
╱╱╱╱╱╱╱╱╰━━╯╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╱╰━━╯V6.1.0"

  echo "By theTCS"

  echo

  echo "#######################################################"
  echo "Operating System: $SYS"
  echo "Kernel: $KERNEL"
  echo "Architecture: $ARCHITECTURE"
  echo "Virtualization: $VIRT"
  echo "======================================================="
  echo "CPU Usage: $cpu_usage%"
  echo "Memory Usage: $memory_usage%"
  echo "Storage Usage: $storage_usage%"
  echo "======================================================="
  echo "IPv4: $WAN4"
  echo "IPv6: $WAN6"
  echo "Country/ISP: $COUNTRY $ISP"
  echo "======================================================="
  for process_info in "${processes[@]}"; do
    IFS=":" read -r process_name custom_name json_file <<<"$process_info"
    check_and_display_process_status "$process_name" "$custom_name" "$json_file"
  done
  echo "#######################################################"

  echo

  echo "
▒█▀▀▀█ █▀▀ █░░ █▀▀ █▀▀ ▀▀█▀▀ 　 █▀▄▀█ █▀▀ █▀▀▄ █░░█ 　 ▄ 
░▀▀▀▄▄ █▀▀ █░░ █▀▀ █░░ ░░█░░ 　 █░▀░█ █▀▀ █░░█ █░░█ 　 ░ 
▒█▄▄▄█ ▀▀▀ ▀▀▀ ▀▀▀ ▀▀▀ ░░▀░░ 　 ▀░░░▀ ▀▀▀ ▀░░▀ ░▀▀▀ 　 ▀"

  echo

  echo

  echo -e "1)  \e[93mTUI Menu\e[0m"
  echo -e "2)  \e[93mLegacy Menu\e[0m"
  echo -e "3)  \e[96mInstall Hysteria2 v2.9.2 + Gecko + Masquerade\e[0m"
  echo -e "4)  \e[92mApply Optimize 10 + 12 (Network + System Limits)\e[0m"
  echo -e "5)  \e[96mGecko Two-Server Relay Menu (Client -> Iran -> Kharej)\e[0m"
  echo -e "6)  \e[96mHysteria2 Gecko Port Hop Menu (Kharej only)\e[0m"
  echo -e "0)  \e[95mExit\e[0m"

  read -p "Enter your choice: " user_choice

  case $user_choice in

  1)
    check_dep
    clear    
    tui
    ;;
  2)
    check_dep
    clear
    legacy
    ;;
  3)
    clear
    install_hysteria2_gecko_v292
    read -rp "Press Enter to return to menu..."
    ;;
  4)
    clear
    apply_hy2_network_and_limits_optimize
    read -rp "Press Enter to return to menu..."
    ;;
  5)
    clear
    hysteria2_gecko_relay_menu
    ;;
  6)
    clear
    hysteria2_gecko_porthop_menu
    ;;
  0)
    clear
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "Invalid choice. Please select a valid option."
    ;;
  esac
done
