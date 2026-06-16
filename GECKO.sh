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
  maxIdleTimeout: 60s
  keepAlivePeriod: 10s
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

# =======================================================
# Hysteria2 Gecko App Relay Tunnel - Phormal-style, Gecko-only
# Replaces old nft/DNAT tunnel with Hysteria udpForwarding.
# =======================================================

create_hy2_relay_link_global() {
  python3 - "$@" <<'PY'
import sys, json, base64
keys = ["kharej_server","outer_listen","outer_auth","outer_obfs_password","outer_sni","real_port","user_port","client_auth","client_obfs_password","client_sni","remark","version"]
obj = dict(zip(keys, sys.argv[1:]))
obj["type"] = "gecko-app-relay"
obj["obfs"] = "gecko"
raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode()
print("hy2relay://" + base64.urlsafe_b64encode(raw).decode().rstrip("="))
PY
}

parse_hy2_relay_link_to_env_global() {
  LINK="$1"
  if ! echo "$LINK" | grep -q '^hy2relay://'; then echo "Invalid relay link. It must start with hy2relay://"; return 1; fi
  PAYLOAD="${LINK#hy2relay://}"
  JSON_PAYLOAD="$(b64url_decode_hy2_global "$PAYLOAD")"
  RELAY_TYPE="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global type)"
  RELAY_OBFS="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global obfs)"
  RELAY_KHAREJ_SERVER="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global kharej_server)"
  RELAY_OUTER_LISTEN="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global outer_listen)"
  RELAY_OUTER_AUTH="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global outer_auth)"
  RELAY_OUTER_OBFS_PASSWORD="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global outer_obfs_password)"
  RELAY_OUTER_SNI="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global outer_sni)"
  RELAY_REAL_PORT="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global real_port)"
  RELAY_USER_PORT="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global user_port)"
  RELAY_CLIENT_AUTH="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global client_auth)"
  RELAY_CLIENT_OBFS_PASSWORD="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global client_obfs_password)"
  RELAY_CLIENT_SNI="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global client_sni)"
  RELAY_REMARK="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global remark)"
  if [ "$RELAY_OBFS" != "gecko" ]; then echo "Invalid relay link. Only Gecko obfuscation is allowed."; return 1; fi
  if [ -z "$RELAY_KHAREJ_SERVER" ] || [ -z "$RELAY_OUTER_LISTEN" ] || [ -z "$RELAY_OUTER_AUTH" ] || [ -z "$RELAY_OUTER_OBFS_PASSWORD" ] || [ -z "$RELAY_REAL_PORT" ] || [ -z "$RELAY_CLIENT_AUTH" ] || [ -z "$RELAY_CLIENT_OBFS_PASSWORD" ]; then
    echo "Invalid relay link. Missing required fields."; return 1
  fi
  RELAY_OUTER_SNI="${RELAY_OUTER_SNI:-www.google.com}"
  RELAY_CLIENT_SNI="${RELAY_CLIENT_SNI:-www.google.com}"
  RELAY_REMARK="${RELAY_REMARK:-GECKO-APP-RELAY}"
  RELAY_USER_PORT="${RELAY_USER_PORT:-$RELAY_REAL_PORT}"
  export RELAY_TYPE RELAY_OBFS RELAY_KHAREJ_SERVER RELAY_OUTER_LISTEN RELAY_OUTER_AUTH RELAY_OUTER_OBFS_PASSWORD RELAY_OUTER_SNI RELAY_REAL_PORT RELAY_USER_PORT RELAY_CLIENT_AUTH RELAY_CLIENT_OBFS_PASSWORD RELAY_CLIENT_SNI RELAY_REMARK
}

make_hy2_client_link_global() {
  SERVER_ADDR="$1"; SERVER_PORT="$2"; AUTH_VALUE="$3"; OBFS_VALUE="$4"; SNI_VALUE="$5"; REMARK_VALUE="$6"; EXTRA_QUERY="$7"
  EN_AUTH="$(urlencode_hy2_global "$AUTH_VALUE")"; EN_OBFS="$(urlencode_hy2_global "$OBFS_VALUE")"; EN_SNI="$(urlencode_hy2_global "$SNI_VALUE")"; EN_REMARK="$(urlencode_hy2_global "$REMARK_VALUE")"
  if [ -n "$EXTRA_QUERY" ]; then echo "hy2://$EN_AUTH@$SERVER_ADDR:$SERVER_PORT?sni=$EN_SNI&insecure=1&allowInsecure=1&obfs=gecko&obfs-password=$EN_OBFS&$EXTRA_QUERY#$EN_REMARK"; else echo "hy2://$EN_AUTH@$SERVER_ADDR:$SERVER_PORT?sni=$EN_SNI&insecure=1&allowInsecure=1&obfs=gecko&obfs-password=$EN_OBFS#$EN_REMARK"; fi
}

validate_port_or_range_hy2_global() {
  VALUE="$1"
  if [[ "$VALUE" =~ ^[0-9]+$ ]]; then [ "$VALUE" -ge 1 ] && [ "$VALUE" -le 65535 ] && return 0; fi
  if [[ "$VALUE" =~ ^([0-9]+)-([0-9]+)$ ]]; then A="${BASH_REMATCH[1]}"; B="${BASH_REMATCH[2]}"; [ "$A" -ge 1 ] && [ "$B" -le 65535 ] && [ "$A" -lt "$B" ] && return 0; fi
  return 1
}

open_udp_firewall_hy2_global() {
  P="$1"
  if command -v ufw >/dev/null 2>&1; then
    if [[ "$P" =~ ^([0-9]+)-([0-9]+)$ ]]; then ufw allow "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}/udp" >/dev/null 2>&1 || true; else ufw allow "$P/udp" >/dev/null 2>&1 || true; fi
  fi
}

install_kharej_main_hysteria_gecko_with_relay_link() {
  clear
  echo "======================================================="
  echo " Kharej: Install GECKO App Relay Exit"
  echo "======================================================="
  echo "This replaces the old nft/DNAT tunnel."
  echo "Services on Kharej: Real Gecko server + Outer Hysteria relay server."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  HYSTERIA_BIN="/usr/local/bin/hysteria"
  BASE_DIR="/etc/hysteria2-gecko-app-relay"; REAL_DIR="$BASE_DIR/real-gecko"; OUTER_DIR="$BASE_DIR/outer-relay"
  REAL_CONFIG="$REAL_DIR/server.yaml"; OUTER_CONFIG="$OUTER_DIR/server.yaml"
  REAL_SERVICE="/etc/systemd/system/hysteria2-gecko-real.service"; OUTER_SERVICE="/etc/systemd/system/hysteria2-gecko-app-relay-server.service"
  if [ -f "$REAL_SERVICE" ] || [ -f "$OUTER_SERVICE" ] || [ -d "$BASE_DIR" ]; then
    echo "GECKO App Relay exit already seems installed."; read -rp "Reinstall and overwrite configs/links? [y/N]: " REINSTALL_APP_RELAY
    case "$REINSTALL_APP_RELAY" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  fi
  install_hysteria_binary_multiarch_global || return 1
  read -rp "Real Gecko port on Kharej [9898]: " REAL_PORT; REAL_PORT="${REAL_PORT:-9898}"
  if ! [[ "$REAL_PORT" =~ ^[0-9]+$ ]] || [ "$REAL_PORT" -lt 1 ] || [ "$REAL_PORT" -gt 65535 ]; then echo "Invalid real port."; return 1; fi
  read -rp "Bind real Gecko only to 127.0.0.1? [Y/n]: " LOCAL_ONLY; LOCAL_ONLY="${LOCAL_ONLY:-Y}"
  if [[ "$LOCAL_ONLY" =~ ^[Nn] ]]; then REAL_LISTEN=":$REAL_PORT"; REAL_PUBLIC="yes"; else REAL_LISTEN="127.0.0.1:$REAL_PORT"; REAL_PUBLIC="no"; fi
  read -rp "Outer relay listen port between Iran and Kharej [443]: " OUTER_LISTEN; OUTER_LISTEN="${OUTER_LISTEN:-443}"
  validate_port_or_range_hy2_global "$OUTER_LISTEN" || { echo "Invalid outer relay port/range. Example: 443 or 15000-25000"; return 1; }
  DEFAULT_CLIENT_AUTH="$(openssl rand -hex 16)"; DEFAULT_CLIENT_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"; DEFAULT_OUTER_AUTH="$(openssl rand -hex 16)"; DEFAULT_OUTER_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"
  echo; echo "User-facing Gecko credentials. These go inside the final client link."
  read -rp "Client Auth password [$DEFAULT_CLIENT_AUTH]: " CLIENT_AUTH; CLIENT_AUTH="${CLIENT_AUTH:-$DEFAULT_CLIENT_AUTH}"
  read -rp "Client Gecko obfs password [$DEFAULT_CLIENT_OBFS]: " CLIENT_OBFS; CLIENT_OBFS="${CLIENT_OBFS:-$DEFAULT_CLIENT_OBFS}"
  read -rp "Client SNI / certificate CN [www.google.com]: " CLIENT_SNI; CLIENT_SNI="${CLIENT_SNI:-www.google.com}"
  echo; echo "Outer relay credentials. These are only for Iran <-> Kharej server link."
  read -rp "Outer Relay Auth password [$DEFAULT_OUTER_AUTH]: " OUTER_AUTH; OUTER_AUTH="${OUTER_AUTH:-$DEFAULT_OUTER_AUTH}"
  read -rp "Outer Relay Gecko obfs password [$DEFAULT_OUTER_OBFS]: " OUTER_OBFS; OUTER_OBFS="${OUTER_OBFS:-$DEFAULT_OUTER_OBFS}"
  read -rp "Outer Relay SNI / certificate CN [www.google.com]: " OUTER_SNI; OUTER_SNI="${OUTER_SNI:-www.google.com}"
  read -rp "Iran user-facing UDP port [same as real: $REAL_PORT]: " USER_PORT; USER_PORT="${USER_PORT:-$REAL_PORT}"
  if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then echo "Invalid user port."; return 1; fi
  read -rp "Remark [GECKO-APP-RELAY]: " RELAY_REMARK; RELAY_REMARK="${RELAY_REMARK:-GECKO-APP-RELAY}"
  CLIENT_AUTH_YAML="$(yaml_quote_hy2_global "$CLIENT_AUTH")"; CLIENT_OBFS_YAML="$(yaml_quote_hy2_global "$CLIENT_OBFS")"; OUTER_AUTH_YAML="$(yaml_quote_hy2_global "$OUTER_AUTH")"; OUTER_OBFS_YAML="$(yaml_quote_hy2_global "$OUTER_OBFS")"; REAL_LISTEN_YAML="$(yaml_quote_hy2_global "$REAL_LISTEN")"
  systemctl disable --now hysteria2-gecko-real.service >/dev/null 2>&1 || true; systemctl disable --now hysteria2-gecko-app-relay-server.service >/dev/null 2>&1 || true
  mkdir -p "$REAL_DIR" "$OUTER_DIR"
  echo "Generating self-signed certificates..."
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$REAL_DIR/server.key" -out "$REAL_DIR/server.crt" -subj "/CN=$CLIENT_SNI" -days 3650 >/dev/null 2>&1; chmod 600 "$REAL_DIR/server.key"
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$OUTER_DIR/server.key" -out "$OUTER_DIR/server.crt" -subj "/CN=$OUTER_SNI" -days 3650 >/dev/null 2>&1; chmod 600 "$OUTER_DIR/server.key"
  cat > "$REAL_CONFIG" <<EOF
listen: $REAL_LISTEN_YAML

tls:
  cert: $REAL_DIR/server.crt
  key: $REAL_DIR/server.key
  sniGuard: disable

auth:
  type: password
  password: $CLIENT_AUTH_YAML

obfs:
  type: gecko
  gecko:
    password: $CLIENT_OBFS_YAML
    minPacketSize: 512
    maxPacketSize: 1200

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  keepAlivePeriod: 10s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: true
EOF
  cat > "$OUTER_CONFIG" <<EOF
listen: :$OUTER_LISTEN

tls:
  cert: $OUTER_DIR/server.crt
  key: $OUTER_DIR/server.key
  sniGuard: disable

auth:
  type: password
  password: $OUTER_AUTH_YAML

obfs:
  type: gecko
  gecko:
    password: $OUTER_OBFS_YAML
    minPacketSize: 512
    maxPacketSize: 1200

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  keepAlivePeriod: 10s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: true

bandwidth:
  up: 1 gbps
  down: 1 gbps
EOF
  cat > "$REAL_SERVICE" <<EOF
[Unit]
Description=GECKO Real Hysteria2 Server behind App Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $REAL_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  cat > "$OUTER_SERVICE" <<EOF
[Unit]
Description=GECKO App Relay Outer Hysteria2 Server for Iran
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $OUTER_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now hysteria2-gecko-real.service; systemctl enable --now hysteria2-gecko-app-relay-server.service; systemctl restart hysteria2-gecko-real.service; systemctl restart hysteria2-gecko-app-relay-server.service
  open_udp_firewall_hy2_global "$OUTER_LISTEN"; [ "$REAL_PUBLIC" = "yes" ] && open_udp_firewall_hy2_global "$REAL_PORT"
  KHAREJ_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  RELAY_LINK="$(create_hy2_relay_link_global "$KHAREJ_IP" "$OUTER_LISTEN" "$OUTER_AUTH" "$OUTER_OBFS" "$OUTER_SNI" "$REAL_PORT" "$USER_PORT" "$CLIENT_AUTH" "$CLIENT_OBFS" "$CLIENT_SNI" "$RELAY_REMARK" "2")"
  DIRECT_CLIENT_LINK="$(make_hy2_client_link_global "$KHAREJ_IP" "$REAL_PORT" "$CLIENT_AUTH" "$CLIENT_OBFS" "$CLIENT_SNI" "$RELAY_REMARK")"
  cat > "$BASE_DIR/relay-link.txt" <<EOF
$RELAY_LINK
EOF
  cat > "$BASE_DIR/direct-client-link.txt" <<EOF
$DIRECT_CLIENT_LINK
EOF
  cat > "$BASE_DIR/kharej-info.txt" <<EOF
Mode: GECKO App Relay Exit
Kharej IP: $KHAREJ_IP
Outer Relay Listen: $OUTER_LISTEN
Outer Relay Auth: $OUTER_AUTH
Outer Relay Gecko Password: $OUTER_OBFS
Outer Relay SNI: $OUTER_SNI
Real Gecko Listen: $REAL_LISTEN
Real Gecko Port: $REAL_PORT
Real Gecko Public: $REAL_PUBLIC
Client Auth: $CLIENT_AUTH
Client Gecko Password: $CLIENT_OBFS
Client SNI: $CLIENT_SNI
Iran User Port: $USER_PORT
Remark: $RELAY_REMARK

Relay Link for Iran:
$RELAY_LINK

Direct Kharej Link, only works if real port is public:
$DIRECT_CLIENT_LINK
EOF
  echo; echo "======================================================="; echo "GECKO App Relay Exit installed on KHAREJ."; echo "Paste this relay link on IRAN server:"; echo "-------------------------------------------------------"; echo "$RELAY_LINK"; echo "-------------------------------------------------------"; echo "Outer Iran<->Kharej listen: $KHAREJ_IP:$OUTER_LISTEN/udp"; echo "Real Gecko service: $REAL_LISTEN/udp"; echo "Saved: $BASE_DIR/relay-link.txt"; echo "======================================================="
}

install_iran_udp_gecko_relay_from_link() {
  clear
  echo "======================================================="; echo " Iran: Install GECKO App Relay Entry"; echo "======================================================="; echo "This runs Hysteria client with udpForwarding."; echo "No nft DNAT, no IP forwarding, no system route changes."; echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  HYSTERIA_BIN="/usr/local/bin/hysteria"; RELAY_DIR="/etc/hysteria2-gecko-app-relay-client"; RELAY_CONFIG="$RELAY_DIR/client.yaml"; RELAY_SERVICE="/etc/systemd/system/hysteria2-gecko-app-relay-client.service"
  if [ -f "$RELAY_SERVICE" ] || [ -d "$RELAY_DIR" ]; then echo "GECKO App Relay client already seems installed on Iran."; read -rp "Reinstall and overwrite config? [y/N]: " REINSTALL_IRAN_RELAY; case "$REINSTALL_IRAN_RELAY" in y|Y|yes|YES|Yes) systemctl disable --now hysteria2-gecko-app-relay-client.service >/dev/null 2>&1 || true ;; *) echo "Cancelled."; return 0 ;; esac; fi
  install_hysteria_binary_multiarch_global || return 1
  read -rp "Paste hy2relay:// link from Kharej: " RELAY_LINK_INPUT; parse_hy2_relay_link_to_env_global "$RELAY_LINK_INPUT" || return 1
  echo; echo "Parsed App Relay link:"; echo "  Kharej outer server: $RELAY_KHAREJ_SERVER:$RELAY_OUTER_LISTEN"; echo "  Kharej real Gecko:   127.0.0.1:$RELAY_REAL_PORT"; echo "  Iran user port:      $RELAY_USER_PORT"; echo "  Final client obfs:   gecko"; echo
  read -rp "Iran public UDP port for users [$RELAY_USER_PORT]: " IRAN_INPUT_PORT; IRAN_INPUT_PORT="${IRAN_INPUT_PORT:-$RELAY_USER_PORT}"
  if ! [[ "$IRAN_INPUT_PORT" =~ ^[0-9]+$ ]] || [ "$IRAN_INPUT_PORT" -lt 1 ] || [ "$IRAN_INPUT_PORT" -gt 65535 ]; then echo "Invalid Iran user port."; return 1; fi
  read -rp "UDP forwarding timeout [60s]: " UDP_TIMEOUT; UDP_TIMEOUT="${UDP_TIMEOUT:-60s}"
  OUTER_SERVER_ADDR="$RELAY_KHAREJ_SERVER:$RELAY_OUTER_LISTEN"; OUTER_AUTH_YAML="$(yaml_quote_hy2_global "$RELAY_OUTER_AUTH")"; OUTER_OBFS_YAML="$(yaml_quote_hy2_global "$RELAY_OUTER_OBFS_PASSWORD")"; OUTER_SNI_YAML="$(yaml_quote_hy2_global "$RELAY_OUTER_SNI")"; OUTER_SERVER_YAML="$(yaml_quote_hy2_global "$OUTER_SERVER_ADDR")"
  mkdir -p "$RELAY_DIR"
  cat > "$RELAY_CONFIG" <<EOF
server: $OUTER_SERVER_YAML

auth: $OUTER_AUTH_YAML

tls:
  sni: $OUTER_SNI_YAML
  insecure: true

obfs:
  type: gecko
  gecko:
    password: $OUTER_OBFS_YAML
    minPacketSize: 512
    maxPacketSize: 1200

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  keepAlivePeriod: 10s
  disablePathMTUDiscovery: true

udpForwarding:
  - listen: 0.0.0.0:$IRAN_INPUT_PORT
    remote: 127.0.0.1:$RELAY_REAL_PORT
    timeout: $UDP_TIMEOUT
EOF
  cat > "$RELAY_SERVICE" <<EOF
[Unit]
Description=GECKO App Relay Iran Entry Client udpForwarding
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN client -c $RELAY_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload; systemctl enable --now hysteria2-gecko-app-relay-client.service; systemctl restart hysteria2-gecko-app-relay-client.service
  open_udp_firewall_hy2_global "$IRAN_INPUT_PORT"
  IRAN_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"; FINAL_REMARK="${RELAY_REMARK:-GECKO-IRAN-APP-RELAY}"; FINAL_CLIENT_LINK="$(make_hy2_client_link_global "$IRAN_IP" "$IRAN_INPUT_PORT" "$RELAY_CLIENT_AUTH" "$RELAY_CLIENT_OBFS_PASSWORD" "$RELAY_CLIENT_SNI" "$FINAL_REMARK")"
  cat > "$RELAY_DIR/client-link-through-iran.txt" <<EOF
$FINAL_CLIENT_LINK
EOF
  cat > "$RELAY_DIR/relay-info.txt" <<EOF
Mode: GECKO App Relay Entry
Iran IP: $IRAN_IP
Iran User UDP Port: $IRAN_INPUT_PORT
Kharej Outer Server: $RELAY_KHAREJ_SERVER:$RELAY_OUTER_LISTEN
Kharej Real Gecko Remote: 127.0.0.1:$RELAY_REAL_PORT
UDP Forwarding Timeout: $UDP_TIMEOUT
Final Client SNI: $RELAY_CLIENT_SNI
Final Remark: $FINAL_REMARK

Final Client Link Through Iran:
$FINAL_CLIENT_LINK

Original Relay Link:
$RELAY_LINK_INPUT
EOF
  echo; echo "======================================================="; echo "GECKO App Relay Entry installed on IRAN."; echo "Users should connect to IRAN, not Kharej:"; echo "-------------------------------------------------------"; echo "$FINAL_CLIENT_LINK"; echo "-------------------------------------------------------"; echo "Path: Client -> Iran:$IRAN_INPUT_PORT -> HY2 App Relay -> Kharej 127.0.0.1:$RELAY_REAL_PORT"; echo "No nft/DNAT is used in this mode."; echo "Saved: $RELAY_DIR/client-link-through-iran.txt"; echo "======================================================="
}

show_kharej_relay_link() { clear; echo "======================================================="; echo " Kharej GECKO App Relay Link"; echo "======================================================="; if [ -f /etc/hysteria2-gecko-app-relay/relay-link.txt ]; then cat /etc/hysteria2-gecko-app-relay/relay-link.txt; elif [ -f /etc/hysteria2-gecko-main/relay-link.txt ]; then echo "Old relay link found:"; cat /etc/hysteria2-gecko-main/relay-link.txt; else echo "Relay link not found. Install GECKO App Relay Exit on Kharej first."; fi; }
show_iran_client_link() { clear; echo "======================================================="; echo " Client Link Through Iran GECKO App Relay"; echo "======================================================="; if [ -f /etc/hysteria2-gecko-app-relay-client/client-link-through-iran.txt ]; then cat /etc/hysteria2-gecko-app-relay-client/client-link-through-iran.txt; elif [ -f /etc/hysteria2-gecko-udp-relay/client-link-through-iran.txt ]; then echo "Old nft/DNAT relay client link found:"; cat /etc/hysteria2-gecko-udp-relay/client-link-through-iran.txt; else echo "Client link not found. Install Iran GECKO App Relay Entry first."; fi; }
show_gecko_relay_status() { clear; echo "======================================================="; echo " GECKO App Relay Status"; echo "======================================================="; echo; echo "[Kharej Real Gecko Server]"; systemctl status hysteria2-gecko-real.service --no-pager 2>/dev/null || echo "hysteria2-gecko-real.service not installed."; echo; echo "[Kharej Outer App Relay Server]"; systemctl status hysteria2-gecko-app-relay-server.service --no-pager 2>/dev/null || echo "hysteria2-gecko-app-relay-server.service not installed."; echo; echo "[Iran App Relay Client]"; systemctl status hysteria2-gecko-app-relay-client.service --no-pager 2>/dev/null || echo "hysteria2-gecko-app-relay-client.service not installed."; echo; echo "[Old nft/DNAT relay, if present]"; systemctl status hysteria2-gecko-udp-relay.service --no-pager 2>/dev/null || true; }
restart_gecko_relay_services() { clear; systemctl restart hysteria2-gecko-real.service >/dev/null 2>&1 || true; systemctl restart hysteria2-gecko-app-relay-server.service >/dev/null 2>&1 || true; systemctl restart hysteria2-gecko-app-relay-client.service >/dev/null 2>&1 || true; show_gecko_relay_status; }
stop_gecko_relay_services() { clear; systemctl stop hysteria2-gecko-real.service >/dev/null 2>&1 || true; systemctl stop hysteria2-gecko-app-relay-server.service >/dev/null 2>&1 || true; systemctl stop hysteria2-gecko-app-relay-client.service >/dev/null 2>&1 || true; show_gecko_relay_status; }

uninstall_gecko_relay_services() {
  clear; echo "======================================================="; echo " Uninstall GECKO App Relay Services"; echo "======================================================="; echo "This removes new App Relay services and also cleans old nft/DNAT relay if present."; read -rp "Continue? [y/N]: " CONFIRM
  case "$CONFIRM" in y|Y|yes|YES|Yes)
    systemctl disable --now hysteria2-gecko-real.service >/dev/null 2>&1 || true; systemctl disable --now hysteria2-gecko-app-relay-server.service >/dev/null 2>&1 || true; systemctl disable --now hysteria2-gecko-app-relay-client.service >/dev/null 2>&1 || true; systemctl disable --now hysteria2-gecko-main.service >/dev/null 2>&1 || true; systemctl disable --now hysteria2-gecko-udp-relay.service >/dev/null 2>&1 || true
    [ -x /usr/local/sbin/hy2-gecko-relay-remove.sh ] && /usr/local/sbin/hy2-gecko-relay-remove.sh >/dev/null 2>&1 || true; nft delete table inet hy2_gecko_relay >/dev/null 2>&1 || true
    rm -f /usr/local/sbin/hy2-gecko-relay-apply.sh /usr/local/sbin/hy2-gecko-relay-remove.sh /etc/nftables.d/hy2-gecko-relay.nft /etc/sysctl.d/99-hy2-gecko-relay-optimize.conf
    rm -f /etc/systemd/system/hysteria2-gecko-real.service /etc/systemd/system/hysteria2-gecko-app-relay-server.service /etc/systemd/system/hysteria2-gecko-app-relay-client.service /etc/systemd/system/hysteria2-gecko-main.service /etc/systemd/system/hysteria2-gecko-udp-relay.service
    rm -rf /etc/hysteria2-gecko-app-relay /etc/hysteria2-gecko-app-relay-client /etc/hysteria2-gecko-main /etc/hysteria2-gecko-udp-relay
    systemctl daemon-reload; echo "GECKO App Relay services removed.";; *) echo "Cancelled.";; esac
}

# =======================================================
# GECKO WARP Proxy Outbound - Kharej only
# Uses fscarmen/warp Cloudflare Client Proxy mode and routes
# only Real Gecko server outbound through local SOCKS5 proxy.
# =======================================================

GECKO_WARP_DEFAULT_PORT="40000"
GECKO_WARP_REAL_CONFIG="/etc/hysteria2-gecko-app-relay/real-gecko/server.yaml"
GECKO_WARP_REAL_SERVICE="hysteria2-gecko-real.service"
GECKO_WARP_ROUTES_FILE="/etc/hysteria2-gecko-app-relay/warp-routes.txt"

gecko_warp_require_kharej_config() {
  [ -f "$GECKO_WARP_REAL_CONFIG" ] || {
    echo "Real Gecko config not found: $GECKO_WARP_REAL_CONFIG"
    echo "Install GECKO App Relay Exit on Kharej first."
    return 1
  }
}

gecko_warp_detect_proxy_port() {
  for P in 40000 40001 1080 8086 8080; do
    if ss -lntup 2>/dev/null | grep -Eq "127\.0\.0\.1:$P|\[::1\]:$P|0\.0\.0\.0:$P|:$P"; then
      echo "$P"
      return 0
    fi
  done
  echo "$GECKO_WARP_DEFAULT_PORT"
}

install_cloudflare_warp_proxy_fscarmen_gecko() {
  clear
  echo "======================================================="
  echo " Install Cloudflare WARP Proxy - Kharej only"
  echo "======================================================="
  echo "This runs fscarmen/warp installer. In its menu choose:"
  echo "  Install CloudFlare Client and set mode to Proxy"
  echo "  MASQUE (default)"
  echo "  Use free account (default)"
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  echo
  read -rp "Run fscarmen WARP installer now? [Y/n]: " RUN_WARP_INSTALL
  RUN_WARP_INSTALL="${RUN_WARP_INSTALL:-Y}"
  case "$RUN_WARP_INSTALL" in
    y|Y|yes|YES|Yes)
      bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh)
      ;;
    *) echo "Cancelled."; return 0 ;;
  esac
  echo
  echo "After installation, test local proxy with menu option: Test WARP proxy."
}

remove_gecko_warp_block_from_config() {
  CFG="$1"
  python3 - "$CFG" <<'INNERPY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding='utf-8', errors='ignore')
text = re.sub(r'\n?# BEGIN GECKO WARP PROXY OUTBOUND\n.*?\n# END GECKO WARP PROXY OUTBOUND\n?', '\n', text, flags=re.S)
text = re.sub(r'\n?# BEGIN GECKO WARP SNI SNIFF\n.*?\n# END GECKO WARP SNI SNIFF\n?', '\n', text, flags=re.S)
p.write_text(text.rstrip() + '\n', encoding='utf-8')
INNERPY
}

write_default_gecko_warp_routes() {
  gecko_warp_detect_config_and_service
  mkdir -p "$(dirname "$GECKO_WARP_ROUTES_FILE")"
  cat > "$GECKO_WARP_ROUTES_FILE" <<'EOF'
suffix:google.com
suffix:gstatic.com
suffix:googleapis.com
suffix:googleusercontent.com
suffix:google-analytics.com
suffix:generativelanguage.googleapis.com
suffix:ai.google.dev
suffix:apple.com
suffix:icloud.com
suffix:cdn-apple.com
suffix:openai.com
suffix:chatgpt.com
suffix:showip.net
*.showip.net
showip.net
EOF
}

build_gecko_warp_acl_rules() {
  [ -f "$GECKO_WARP_ROUTES_FILE" ] || write_default_gecko_warp_routes
  while IFS= read -r RULE; do
    RULE="$(echo "$RULE" | sed 's/#.*$//' | xargs)"
    [ -z "$RULE" ] && continue
    echo "    - warp($RULE)"
  done < "$GECKO_WARP_ROUTES_FILE"
  echo "    - direct(all)"
}

show_default_gecko_warp_routes() {
  [ -f "$GECKO_WARP_ROUTES_FILE" ] || write_default_gecko_warp_routes
  cat "$GECKO_WARP_ROUTES_FILE"
}

enable_gecko_real_outbound_via_warp() {
  clear
  echo "======================================================="
  echo " Enable SELECTIVE Real Gecko Outbound via WARP Proxy"
  echo "======================================================="
  echo "Only selected domains/rules will use WARP. SNI/Host sniffing will be enabled for domain matching."
  echo "Everything else will use DIRECT outbound."
  echo "Iran<->Kharej outer relay routing will NOT be changed."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  gecko_warp_require_kharej_config || return 1

  write_default_gecko_warp_routes
  # Upgrade route files created by older versions.
  sed -i '/^keyword:showip$/d;/^geosite:youtube$/d' "$GECKO_WARP_ROUTES_FILE" 2>/dev/null || true
  grep -qxF 'suffix:showip.net' "$GECKO_WARP_ROUTES_FILE" 2>/dev/null || echo 'suffix:showip.net' >> "$GECKO_WARP_ROUTES_FILE"
  grep -qxF '*.showip.net' "$GECKO_WARP_ROUTES_FILE" 2>/dev/null || echo '*.showip.net' >> "$GECKO_WARP_ROUTES_FILE"
  grep -qxF 'showip.net' "$GECKO_WARP_ROUTES_FILE" 2>/dev/null || echo 'showip.net' >> "$GECKO_WARP_ROUTES_FILE"

  echo
  echo "Selective WARP route list:"
  echo "-------------------------------------------------------"
  show_default_gecko_warp_routes
  echo "-------------------------------------------------------"
  echo "These routes will be converted to warp(rule), then direct(all)."
  echo

  DETECTED_PORT="$(gecko_warp_detect_proxy_port)"
  read -rp "Local WARP SOCKS5 proxy port [$DETECTED_PORT]: " WARP_PROXY_PORT
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$DETECTED_PORT}"
  if ! [[ "$WARP_PROXY_PORT" =~ ^[0-9]+$ ]] || [ "$WARP_PROXY_PORT" -lt 1 ] || [ "$WARP_PROXY_PORT" -gt 65535 ]; then
    echo "Invalid proxy port."; return 1
  fi
  WARP_PROXY_ADDR="127.0.0.1:$WARP_PROXY_PORT"

  echo
  echo "Testing SOCKS5 proxy at $WARP_PROXY_ADDR ..."
  if command -v curl >/dev/null 2>&1; then
    if curl --socks5 "$WARP_PROXY_ADDR" --max-time 12 -fsSL https://www.cloudflare.com/cdn-cgi/trace >/tmp/gecko-warp-trace.txt 2>/tmp/gecko-warp-curl.err; then
      echo "Proxy test OK:"
      grep -E '^(ip|colo|warp)=' /tmp/gecko-warp-trace.txt || true
    else
      echo "WARNING: SOCKS5 proxy test failed."
      echo "You can still enable it, but selected Hysteria outbound may fail until WARP Proxy is working."
      [ -s /tmp/gecko-warp-curl.err ] && cat /tmp/gecko-warp-curl.err
      read -rp "Continue anyway? [y/N]: " CONT_WARP
      case "$CONT_WARP" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 1 ;; esac
    fi
  fi

  TS="$(date +%Y%m%d-%H%M%S)"
  cp -a "$GECKO_WARP_REAL_CONFIG" "$GECKO_WARP_REAL_CONFIG.bak-before-selective-warp-$TS"
  remove_gecko_warp_block_from_config "$GECKO_WARP_REAL_CONFIG"

  if grep -Eq '^[[:space:]]*(outbounds|acl|sniff):[[:space:]]*$' "$GECKO_WARP_REAL_CONFIG"; then
    echo
    echo "WARNING: Existing top-level outbounds/acl/sniff detected in real Gecko config."
    echo "To avoid duplicate YAML keys, this automatic patch will not continue."
    echo "Backup saved: $GECKO_WARP_REAL_CONFIG.bak-before-selective-warp-$TS"
    return 1
  fi

  {
    echo
    echo "# BEGIN GECKO WARP SNI SNIFF"
    echo "sniff:"
    echo "  enable: true"
    echo "  timeout: 2s"
    echo "  rewriteDomain: true"
    echo "  tcpPorts: 80,443"
    echo "  udpPorts: 443"
    echo "# END GECKO WARP SNI SNIFF"
    echo
    echo "# BEGIN GECKO WARP PROXY OUTBOUND"
    echo "outbounds:"
    echo "  - name: direct"
    echo "    type: direct"
    echo
    echo "  - name: warp"
    echo "    type: socks5"
    echo "    socks5:"
    echo "      addr: $WARP_PROXY_ADDR"
    echo
    echo "acl:"
    echo "  inline:"
    build_gecko_warp_acl_rules
    echo "# END GECKO WARP PROXY OUTBOUND"
  } >> "$GECKO_WARP_REAL_CONFIG"

  systemctl restart "$GECKO_WARP_REAL_SERVICE"
  sleep 1
  echo
  systemctl status "$GECKO_WARP_REAL_SERVICE" --no-pager || true
  echo
  echo "Selective WARP outbound enabled for Real Gecko server."
  echo "Only rules in $GECKO_WARP_ROUTES_FILE use WARP; everything else is direct. Sniffing is enabled for TUN/IP-only clients."
  echo "Backup: $GECKO_WARP_REAL_CONFIG.bak-before-selective-warp-$TS"
}

disable_gecko_real_outbound_via_warp() {
  clear
  echo "======================================================="
  echo " Disable Real Gecko Outbound via WARP Proxy"
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  gecko_warp_require_kharej_config || return 1
  TS="$(date +%Y%m%d-%H%M%S)"
  cp -a "$GECKO_WARP_REAL_CONFIG" "$GECKO_WARP_REAL_CONFIG.bak-disable-warp-$TS"
  remove_gecko_warp_block_from_config "$GECKO_WARP_REAL_CONFIG"
  systemctl restart "$GECKO_WARP_REAL_SERVICE" >/dev/null 2>&1 || true
  echo "WARP outbound block removed from Real Gecko config."
  echo "Backup: $GECKO_WARP_REAL_CONFIG.bak-disable-warp-$TS"
  systemctl status "$GECKO_WARP_REAL_SERVICE" --no-pager || true
}

show_gecko_warp_status() {
  clear
  echo "======================================================="
  echo " GECKO WARP Proxy Status - Kharej only"
  echo "======================================================="
  echo
  echo "[Real Gecko config]"
  if [ -f "$GECKO_WARP_REAL_CONFIG" ]; then
    if grep -q "BEGIN GECKO WARP PROXY OUTBOUND" "$GECKO_WARP_REAL_CONFIG"; then
      echo "WARP outbound block: ENABLED"
      sed -n '/BEGIN GECKO WARP SNI SNIFF/,/END GECKO WARP SNI SNIFF/p' "$GECKO_WARP_REAL_CONFIG"
      sed -n '/BEGIN GECKO WARP PROXY OUTBOUND/,/END GECKO WARP PROXY OUTBOUND/p' "$GECKO_WARP_REAL_CONFIG"
    else
      echo "WARP outbound block: DISABLED"
    fi
  else
    echo "Config not found: $GECKO_WARP_REAL_CONFIG"
  fi
  echo
  echo "[Selective WARP routes]"
  if [ -f "$GECKO_WARP_ROUTES_FILE" ]; then
    cat "$GECKO_WARP_ROUTES_FILE"
  else
    echo "Routes file not created yet: $GECKO_WARP_ROUTES_FILE"
  fi
  echo
  echo "[Listening proxy candidates]"
  ss -lntup 2>/dev/null | grep -E ':(40000|40001|1080|8086|8080)\b' || echo "No common local proxy port found."
  echo
  echo "[Cloudflare/WARP related services]"
  systemctl --no-pager --type=service --state=running 2>/dev/null | grep -Ei 'warp|cloudflare|wgcf' || true
  echo
  echo "[Real Gecko service]"
  systemctl status "$GECKO_WARP_REAL_SERVICE" --no-pager 2>/dev/null || echo "$GECKO_WARP_REAL_SERVICE not installed."
}

test_gecko_warp_proxy() {
  clear
  echo "======================================================="
  echo " Test WARP Local Proxy"
  echo "======================================================="
  DETECTED_PORT="$(gecko_warp_detect_proxy_port)"
  read -rp "Local WARP SOCKS5 proxy port [$DETECTED_PORT]: " WARP_PROXY_PORT
  WARP_PROXY_PORT="${WARP_PROXY_PORT:-$DETECTED_PORT}"
  WARP_PROXY_ADDR="127.0.0.1:$WARP_PROXY_PORT"
  echo
  echo "Direct server trace:"
  curl --max-time 12 -fsSL https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E '^(ip|colo|warp)=' || echo "Direct trace failed."
  echo
  echo "Via WARP SOCKS5 $WARP_PROXY_ADDR:"
  curl --socks5 "$WARP_PROXY_ADDR" --max-time 15 -fsSL https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E '^(ip|colo|warp)=' || echo "WARP SOCKS5 trace failed. Check fscarmen WARP Proxy mode."
}

edit_gecko_warp_routes() {
  clear
  echo "======================================================="
  echo " Edit SELECTIVE WARP route list"
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  write_default_gecko_warp_routes
  echo "Routes file: $GECKO_WARP_ROUTES_FILE"
  echo
  echo "Current routes:"
  echo "-------------------------------------------------------"
  cat "$GECKO_WARP_ROUTES_FILE"
  echo "-------------------------------------------------------"
  echo
  read -rp "Open editor now? [Y/n]: " EDIT_ROUTES
  EDIT_ROUTES="${EDIT_ROUTES:-Y}"
  case "$EDIT_ROUTES" in
    y|Y|yes|YES|Yes)
      "${EDITOR:-nano}" "$GECKO_WARP_ROUTES_FILE"
      ;;
    *) return 0 ;;
  esac
  echo
  echo "To apply changes, run: Enable SELECTIVE Real Gecko outbound via local WARP SOCKS5"
}

gecko_warp_proxy_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " GECKO WARP Proxy Outbound Menu - Kharej only"
    echo "======================================================="
    echo "Purpose: Client -> Iran -> Kharej Real Gecko -> WARP Proxy -> Internet"
    echo "This does NOT change server default route and does NOT touch Iran<->Kharej outer relay."
    echo
    echo " 1) Install Cloudflare WARP Proxy using fscarmen script"
    echo " 2) Enable SELECTIVE Real Gecko outbound via local WARP SOCKS5"
    echo " 3) Edit selective WARP route list"
    echo " 4) Disable Real Gecko outbound via WARP"
    echo " 5) Show WARP/Gecko status"
    echo " 6) Test local WARP SOCKS5 proxy"
    echo " 0) Back"
    echo "======================================================="
    read -rp "Choose: " WARP_CHOICE
    case "$WARP_CHOICE" in
      1) install_cloudflare_warp_proxy_fscarmen_gecko; read -rp "Press Enter to return to WARP menu..." ;;
      2) enable_gecko_real_outbound_via_warp; read -rp "Press Enter to return to WARP menu..." ;;
      3) edit_gecko_warp_routes; read -rp "Press Enter to return to WARP menu..." ;;
      4) disable_gecko_real_outbound_via_warp; read -rp "Press Enter to return to WARP menu..." ;;
      5) show_gecko_warp_status; read -rp "Press Enter to return to WARP menu..." ;;
      6) test_gecko_warp_proxy; read -rp "Press Enter to return to WARP menu..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
}


hysteria2_gecko_relay_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " Hysteria2 GECKO App Relay Tunnel Menu"
    echo "======================================================="
    echo "Architecture: Client -> Iran Hysteria udpForwarding -> Kharej Real Gecko"
    echo "Old nft/DNAT tunnel is replaced in this menu."
    echo
    echo " 1) Kharej: Install GECKO App Relay Exit + Generate Relay Link"
    echo " 2) Kharej: Show Relay Link"
    echo " 3) Iran:   Install GECKO App Relay Entry from Relay Link"
    echo " 4) Iran:   Show Final Client Link Through Iran"
    echo " 5) Status"
    echo " 6) Restart services"
    echo " 7) Stop services"
    echo " 8) Uninstall relay services"
    echo " 9) Kharej: WARP Proxy Outbound Menu"
    echo " 0) Back"
    echo "======================================================="
    echo "Gecko-only. No nft/DNAT. No IP forwarding."
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
      9) gecko_warp_proxy_menu ;;
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


patch_existing_gecko_quic_keepalive() {
  clear
  echo "======================================================="
  echo " Patch Existing GECKO/Hysteria QUIC KeepAlive"
  echo "======================================================="
  echo "This updates existing local config files:"
  echo "  maxIdleTimeout: 60s"
  echo "  keepAlivePeriod: 10s"
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }

  python3 <<'PY'
from pathlib import Path
import re, shutil, datetime

paths = [
    Path("/etc/hysteria2/server.yaml"),
    Path("/etc/hysteria2-gecko-main/server.yaml"),
    Path("/etc/hysteria2-gecko-app-relay-client/client.yaml"),
    Path("/etc/hysteria2-gecko-app-relay/outer-server/server.yaml"),
    Path("/etc/hysteria2-gecko-app-relay/real-gecko/server.yaml"),
]
ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
changed = []

def ensure_quic(text: str) -> str:
    if re.search(r'(?m)^quic:\s*$', text):
        text = re.sub(r'(?m)^(\s*)maxIdleTimeout:\s*\S+\s*$', r'\1maxIdleTimeout: 60s', text)
        if not re.search(r'(?m)^\s*maxIdleTimeout:\s*', text):
            text = re.sub(r'(?m)^quic:\s*$', 'quic:\n  maxIdleTimeout: 60s', text, count=1)
        if not re.search(r'(?m)^\s*keepAlivePeriod:\s*', text):
            text = re.sub(r'(?m)^(\s*maxIdleTimeout:\s*60s\s*)$', r'\1\n  keepAlivePeriod: 10s', text, count=1)
    else:
        text = text.rstrip() + "\n\nquic:\n  maxIdleTimeout: 60s\n  keepAlivePeriod: 10s\n"
    return text

for p in paths:
    if not p.exists():
        continue
    old = p.read_text(encoding="utf-8", errors="ignore")
    new = ensure_quic(old)
    if new != old:
        backup = p.with_suffix(p.suffix + f".bak-quic-{ts}")
        shutil.copy2(p, backup)
        p.write_text(new, encoding="utf-8")
        changed.append((str(p), str(backup)))

if changed:
    print("Updated config files:")
    for p, b in changed:
        print(f"  {p}")
        print(f"    backup: {b}")
else:
    print("No changes needed or no known GECKO/Hysteria config found.")
PY

  echo
  echo "Restarting known services if present..."
  for SVC in hysteria2-gecko hysteria2 hysteria2-gecko-app-relay-client hysteria2-gecko-app-relay-server hysteria2-gecko-real; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SVC}.service"; then
      systemctl restart "$SVC" 2>/dev/null || true
    fi
  done

  echo
  echo "Current service status:"
  systemctl --no-pager --type=service | grep -Ei 'hysteria|gecko' || true
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
  echo -e "5)  \e[96mGECKO App Relay Tunnel Menu (replaces old tunnel)\e[0m"
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
