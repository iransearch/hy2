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




uninstall_hysteria2_gecko_v292() {
  clear
  echo "======================================================="
  echo " Uninstall Hysteria2 v2.9.2 + Gecko"
  echo "======================================================="
  echo "This will remove:"
  echo "  - hysteria2-gecko.service"
  echo "  - /usr/local/bin/hysteria"
  echo "  - /etc/hysteria2/ (config, certs, links)"
  echo "  - WARP routes file if present"
  echo "======================================================="
  read -rp "Are you sure? [y/N]: " CONFIRM_UNINSTALL
  case "$CONFIRM_UNINSTALL" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Cancelled."; return 0 ;;
  esac

  systemctl disable --now hysteria2-gecko.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/hysteria2-gecko.service
  rm -f /etc/systemd/system/hysteria2-gecko.service.d/override.conf
  rmdir /etc/systemd/system/hysteria2-gecko.service.d 2>/dev/null || true
  rm -f /usr/local/bin/hysteria
  rm -rf /etc/hysteria2
  systemctl daemon-reload

  echo
  echo "Hysteria2 Gecko removed."
  echo "======================================================="
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

# =======================================================
# Hysteria2 Gecko Port Tunnel - one dedicated port per channel
# Each tunnel = one Hysteria2 server on Kharej + one Hysteria2
# client on Iran, both using Gecko obfuscation.
# The same port number is used on Iran (public listen) and on
# Kharej (local forward target). Whatever TCP/UDP service is
# listening on that port on Kharej becomes reachable through it.
# =======================================================

GECKO_TUNNELS_BASE_DIR="/etc/hysteria2-gecko-tunnels"

gecko_tunnel_slug() {
  echo "$1" | tr -c 'A-Za-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//'
}

list_gecko_tunnels() {
  [ -d "$GECKO_TUNNELS_BASE_DIR" ] || return 0
  find "$GECKO_TUNNELS_BASE_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

kharej_install_gecko_port_tunnel() {
  clear
  echo "======================================================="
  echo " Kharej: Create New Gecko Port Tunnel"
  echo "======================================================="
  echo "Each tunnel is one dedicated port carried over a Gecko-"
  echo "obfuscated Hysteria2 channel. TCP and UDP are both relayed."
  echo "Whatever service listens on this port locally on Kharej"
  echo "becomes reachable through the same port on Iran."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }

  read -rp "Port for this tunnel (same number used on Iran and Kharej) [7777]: " TUNNEL_PORT
  TUNNEL_PORT="${TUNNEL_PORT:-7777}"
  if ! [[ "$TUNNEL_PORT" =~ ^[0-9]+$ ]] || [ "$TUNNEL_PORT" -lt 1 ] || [ "$TUNNEL_PORT" -gt 65535 ]; then
    echo "Invalid port."; return 1
  fi

  read -rp "Channel listen port between Iran and Kharej [443]: " CHANNEL_LISTEN
  CHANNEL_LISTEN="${CHANNEL_LISTEN:-443}"
  validate_port_or_range_hy2_global "$CHANNEL_LISTEN" || { echo "Invalid channel listen port/range."; return 1; }

  DEFAULT_AUTH="$(openssl rand -hex 16)"
  DEFAULT_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"
  read -rp "Auth password [$DEFAULT_AUTH]: " TUNNEL_AUTH
  TUNNEL_AUTH="${TUNNEL_AUTH:-$DEFAULT_AUTH}"
  read -rp "Gecko obfs password [$DEFAULT_OBFS]: " TUNNEL_OBFS
  TUNNEL_OBFS="${TUNNEL_OBFS:-$DEFAULT_OBFS}"
  read -rp "SNI / certificate CN [www.google.com]: " TUNNEL_SNI
  TUNNEL_SNI="${TUNNEL_SNI:-www.google.com}"
  read -rp "Remark [GECKO-TUNNEL-$TUNNEL_PORT]: " TUNNEL_REMARK
  TUNNEL_REMARK="${TUNNEL_REMARK:-GECKO-TUNNEL-$TUNNEL_PORT}"

  TUNNEL_SLUG="$(gecko_tunnel_slug "${TUNNEL_REMARK}-${TUNNEL_PORT}")"
  TUNNEL_DIR="$GECKO_TUNNELS_BASE_DIR/$TUNNEL_SLUG"
  if [ -d "$TUNNEL_DIR" ]; then
    echo "A tunnel with this name/port already exists: $TUNNEL_DIR"
    read -rp "Overwrite it? [y/N]: " OVERWRITE_TUNNEL
    case "$OVERWRITE_TUNNEL" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  fi

  install_hysteria_binary_multiarch_global || return 1

  TUNNEL_SERVICE="/etc/systemd/system/hysteria2-tunnel-${TUNNEL_SLUG}.service"
  TUNNEL_CONFIG="$TUNNEL_DIR/server.yaml"
  mkdir -p "$TUNNEL_DIR"

  echo "Generating self-signed certificate..."
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$TUNNEL_DIR/server.key" \
    -out "$TUNNEL_DIR/server.crt" \
    -subj "/CN=$TUNNEL_SNI" \
    -days 3650 >/dev/null 2>&1
  chmod 600 "$TUNNEL_DIR/server.key"

  AUTH_YAML="$(yaml_quote_hy2_global "$TUNNEL_AUTH")"
  OBFS_YAML="$(yaml_quote_hy2_global "$TUNNEL_OBFS")"

  cat > "$TUNNEL_CONFIG" <<EOF
listen: :$CHANNEL_LISTEN

tls:
  cert: $TUNNEL_DIR/server.crt
  key: $TUNNEL_DIR/server.key
  sniGuard: disable

auth:
  type: password
  password: $AUTH_YAML

obfs:
  type: gecko
  gecko:
    password: $OBFS_YAML
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

tcpForwarding:
  - listen: 0.0.0.0:$TUNNEL_PORT
    remote: 127.0.0.1:$TUNNEL_PORT

udpForwarding:
  - listen: 0.0.0.0:$TUNNEL_PORT
    remote: 127.0.0.1:$TUNNEL_PORT
    timeout: 60s
EOF

  cat > "$TUNNEL_SERVICE" <<EOF
[Unit]
Description=GECKO Port Tunnel Server ($TUNNEL_REMARK, port $TUNNEL_PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN_GLOBAL server -c $TUNNEL_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "hysteria2-tunnel-${TUNNEL_SLUG}.service"
  systemctl restart "hysteria2-tunnel-${TUNNEL_SLUG}.service"

  open_udp_firewall_hy2_global "$CHANNEL_LISTEN"
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$TUNNEL_PORT/tcp" >/dev/null 2>&1 || true
    ufw allow "$TUNNEL_PORT/udp" >/dev/null 2>&1 || true
  fi

  KHAREJ_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  TUNNEL_LINK="$(python3 - "$KHAREJ_IP" "$CHANNEL_LISTEN" "$TUNNEL_AUTH" "$TUNNEL_OBFS" "$TUNNEL_SNI" "$TUNNEL_PORT" "$TUNNEL_REMARK" <<'PY'
import sys, json, base64
keys = ["kharej_server","channel_listen","auth","obfs_password","sni","port","remark"]
obj = dict(zip(keys, sys.argv[1:]))
obj["type"] = "gecko-port-tunnel"
obj["obfs"] = "gecko"
raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode()
print("hy2tunnel://" + base64.urlsafe_b64encode(raw).decode().rstrip("="))
PY
)"

  echo "$TUNNEL_LINK" > "$TUNNEL_DIR/tunnel-link.txt"
  cat > "$TUNNEL_DIR/info.txt" <<EOF
Remark: $TUNNEL_REMARK
Tunnel Port (same on Iran and Kharej): $TUNNEL_PORT
Channel Listen Port (Iran<->Kharej): $CHANNEL_LISTEN
Kharej IP: $KHAREJ_IP
Auth: $TUNNEL_AUTH
Gecko Obfs Password: $TUNNEL_OBFS
SNI: $TUNNEL_SNI
Service: hysteria2-tunnel-${TUNNEL_SLUG}.service
Config: $TUNNEL_CONFIG

On Kharej, run your real service so it listens on 127.0.0.1:$TUNNEL_PORT (TCP and/or UDP as needed).

Tunnel Link for Iran:
$TUNNEL_LINK
EOF

  echo
  echo "======================================================="
  echo "Gecko Port Tunnel created on KHAREJ."
  echo "Make sure your real service listens on 127.0.0.1:$TUNNEL_PORT (TCP/UDP)."
  echo "Paste this tunnel link on the IRAN server:"
  echo "-------------------------------------------------------"
  echo "$TUNNEL_LINK"
  echo "-------------------------------------------------------"
  echo "Saved: $TUNNEL_DIR/tunnel-link.txt"
  echo "======================================================="
}

parse_hy2_tunnel_link_to_env_global() {
  LINK="$1"
  if ! echo "$LINK" | grep -q '^hy2tunnel://'; then echo "Invalid tunnel link. It must start with hy2tunnel://"; return 1; fi
  PAYLOAD="${LINK#hy2tunnel://}"
  JSON_PAYLOAD="$(b64url_decode_hy2_global "$PAYLOAD")"
  TUN_TYPE="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global type)"
  TUN_OBFS="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global obfs)"
  TUN_KHAREJ_SERVER="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global kharej_server)"
  TUN_CHANNEL_LISTEN="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global channel_listen)"
  TUN_AUTH="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global auth)"
  TUN_OBFS_PASSWORD="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global obfs_password)"
  TUN_SNI="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global sni)"
  TUN_PORT="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global port)"
  TUN_REMARK="$(printf '%s' "$JSON_PAYLOAD" | json_get_hy2_global remark)"
  if [ "$TUN_OBFS" != "gecko" ]; then echo "Invalid tunnel link. Only Gecko obfuscation is allowed."; return 1; fi
  if [ -z "$TUN_KHAREJ_SERVER" ] || [ -z "$TUN_CHANNEL_LISTEN" ] || [ -z "$TUN_AUTH" ] || [ -z "$TUN_OBFS_PASSWORD" ] || [ -z "$TUN_PORT" ]; then
    echo "Invalid tunnel link. Missing required fields."; return 1
  fi
  TUN_SNI="${TUN_SNI:-www.google.com}"
  TUN_REMARK="${TUN_REMARK:-GECKO-TUNNEL}"
  export TUN_TYPE TUN_OBFS TUN_KHAREJ_SERVER TUN_CHANNEL_LISTEN TUN_AUTH TUN_OBFS_PASSWORD TUN_SNI TUN_PORT TUN_REMARK
}

iran_install_gecko_port_tunnel() {
  clear
  echo "======================================================="
  echo " Iran: Connect to a Gecko Port Tunnel"
  echo "======================================================="
  echo "This runs a Hysteria2 client with tcpForwarding + udpForwarding."
  echo "The same port opened here on Iran is the port reachable on Kharej."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }

  install_hysteria_binary_multiarch_global || return 1
  read -rp "Paste hy2tunnel:// link from Kharej: " TUNNEL_LINK_INPUT
  parse_hy2_tunnel_link_to_env_global "$TUNNEL_LINK_INPUT" || return 1

  echo
  echo "Parsed tunnel link:"
  echo "  Kharej channel server: $TUN_KHAREJ_SERVER:$TUN_CHANNEL_LISTEN"
  echo "  Tunnel port:            $TUN_PORT"
  echo "  Remark:                 $TUN_REMARK"
  echo

  TUNNEL_SLUG="$(gecko_tunnel_slug "${TUN_REMARK}-${TUN_PORT}")"
  TUNNEL_DIR="$GECKO_TUNNELS_BASE_DIR/$TUNNEL_SLUG"
  TUNNEL_CONFIG="$TUNNEL_DIR/client.yaml"
  TUNNEL_SERVICE="/etc/systemd/system/hysteria2-tunnel-${TUNNEL_SLUG}-client.service"

  if [ -f "$TUNNEL_SERVICE" ]; then
    echo "A client for this tunnel already seems installed."
    read -rp "Reinstall and overwrite config? [y/N]: " REINSTALL_TUNNEL
    case "$REINSTALL_TUNNEL" in
      y|Y|yes|YES|Yes) systemctl disable --now "hysteria2-tunnel-${TUNNEL_SLUG}-client.service" >/dev/null 2>&1 || true ;;
      *) echo "Cancelled."; return 0 ;;
    esac
  fi

  mkdir -p "$TUNNEL_DIR"
  CHANNEL_SERVER_ADDR="$TUN_KHAREJ_SERVER:$TUN_CHANNEL_LISTEN"
  AUTH_YAML="$(yaml_quote_hy2_global "$TUN_AUTH")"
  OBFS_YAML="$(yaml_quote_hy2_global "$TUN_OBFS_PASSWORD")"
  SNI_YAML="$(yaml_quote_hy2_global "$TUN_SNI")"
  SERVER_YAML="$(yaml_quote_hy2_global "$CHANNEL_SERVER_ADDR")"

  cat > "$TUNNEL_CONFIG" <<EOF
server: $SERVER_YAML

auth: $AUTH_YAML

tls:
  sni: $SNI_YAML
  insecure: true

obfs:
  type: gecko
  gecko:
    password: $OBFS_YAML
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

tcpForwarding:
  - listen: 0.0.0.0:$TUN_PORT
    remote: 127.0.0.1:$TUN_PORT

udpForwarding:
  - listen: 0.0.0.0:$TUN_PORT
    remote: 127.0.0.1:$TUN_PORT
    timeout: 60s
EOF

  cat > "$TUNNEL_SERVICE" <<EOF
[Unit]
Description=GECKO Port Tunnel Client ($TUN_REMARK, port $TUN_PORT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN_GLOBAL client -c $TUNNEL_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "hysteria2-tunnel-${TUNNEL_SLUG}-client.service"
  systemctl restart "hysteria2-tunnel-${TUNNEL_SLUG}-client.service"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$TUN_PORT/tcp" >/dev/null 2>&1 || true
    ufw allow "$TUN_PORT/udp" >/dev/null 2>&1 || true
  fi

  IRAN_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  cat > "$TUNNEL_DIR/iran-info.txt" <<EOF
Mode: GECKO Port Tunnel Entry (Iran)
Remark: $TUN_REMARK
Iran IP: $IRAN_IP
Tunnel Port (TCP+UDP): $TUN_PORT
Kharej Channel Server: $CHANNEL_SERVER_ADDR
Service: hysteria2-tunnel-${TUNNEL_SLUG}-client.service

Connect your clients to: $IRAN_IP:$TUN_PORT
Whatever runs on Kharej's 127.0.0.1:$TUN_PORT will answer there.
EOF

  echo
  echo "======================================================="
  echo "Gecko Port Tunnel connected on IRAN."
  echo "Users/clients should connect to:"
  echo "-------------------------------------------------------"
  echo "$IRAN_IP:$TUN_PORT  (TCP and UDP)"
  echo "-------------------------------------------------------"
  echo "Path: Client -> Iran:$TUN_PORT -> Gecko tunnel -> Kharej 127.0.0.1:$TUN_PORT"
  echo "Saved: $TUNNEL_DIR/iran-info.txt"
  echo "======================================================="
}

list_gecko_port_tunnels_table() {
  clear
  echo "======================================================="
  echo " Gecko Port Tunnels"
  echo "======================================================="
  if [ ! -d "$GECKO_TUNNELS_BASE_DIR" ] || [ -z "$(list_gecko_tunnels)" ]; then
    echo "No tunnels found."
    return 0
  fi
  local i=1
  while IFS= read -r SLUG; do
    echo "$i) $SLUG"
    if [ -f "$GECKO_TUNNELS_BASE_DIR/$SLUG/info.txt" ]; then
      grep -E '^(Remark|Tunnel Port|Channel Listen Port|Kharej IP):' "$GECKO_TUNNELS_BASE_DIR/$SLUG/info.txt" | sed 's/^/   /'
    elif [ -f "$GECKO_TUNNELS_BASE_DIR/$SLUG/iran-info.txt" ]; then
      grep -E '^(Remark|Tunnel Port|Kharej Channel Server):' "$GECKO_TUNNELS_BASE_DIR/$SLUG/iran-info.txt" | sed 's/^/   /'
    fi
    SVC_SERVER="hysteria2-tunnel-${SLUG}.service"
    SVC_CLIENT="hysteria2-tunnel-${SLUG}-client.service"
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SVC_SERVER}"; then
      systemctl is-active "$SVC_SERVER" >/dev/null 2>&1 && echo "   Role: Kharej server, status: active" || echo "   Role: Kharej server, status: inactive"
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q "^${SVC_CLIENT}"; then
      systemctl is-active "$SVC_CLIENT" >/dev/null 2>&1 && echo "   Role: Iran client, status: active" || echo "   Role: Iran client, status: inactive"
    fi
    echo
    i=$((i+1))
  done < <(list_gecko_tunnels)
}

show_gecko_port_tunnel_link() {
  clear
  echo "======================================================="
  echo " Show Tunnel Link / Info"
  echo "======================================================="
  if [ -z "$(list_gecko_tunnels)" ]; then
    echo "No tunnels found."
    return 0
  fi
  local i=1
  local SLUGS=()
  while IFS= read -r SLUG; do
    SLUGS+=("$SLUG")
    echo "$i) $SLUG"
    i=$((i+1))
  done < <(list_gecko_tunnels)
  read -rp "Choose tunnel number: " PICK
  if ! [[ "$PICK" =~ ^[0-9]+$ ]] || [ "$PICK" -lt 1 ] || [ "$PICK" -gt "${#SLUGS[@]}" ]; then
    echo "Invalid choice."; return 1
  fi
  SLUG="${SLUGS[$((PICK-1))]}"
  echo
  [ -f "$GECKO_TUNNELS_BASE_DIR/$SLUG/info.txt" ] && cat "$GECKO_TUNNELS_BASE_DIR/$SLUG/info.txt"
  [ -f "$GECKO_TUNNELS_BASE_DIR/$SLUG/iran-info.txt" ] && cat "$GECKO_TUNNELS_BASE_DIR/$SLUG/iran-info.txt"
}

manage_gecko_port_tunnel_pick() {
  ACTION_LABEL="$1"
  if [ -z "$(list_gecko_tunnels)" ]; then
    echo "No tunnels found."
    return 1
  fi
  local i=1
  local SLUGS=()
  echo "Choose a tunnel to $ACTION_LABEL:"
  while IFS= read -r SLUG; do
    SLUGS+=("$SLUG")
    echo "$i) $SLUG"
    i=$((i+1))
  done < <(list_gecko_tunnels)
  read -rp "Choose tunnel number: " PICK
  if ! [[ "$PICK" =~ ^[0-9]+$ ]] || [ "$PICK" -lt 1 ] || [ "$PICK" -gt "${#SLUGS[@]}" ]; then
    echo "Invalid choice."; return 1
  fi
  PICKED_SLUG="${SLUGS[$((PICK-1))]}"
  export PICKED_SLUG
}

restart_gecko_port_tunnel() {
  clear
  echo "======================================================="
  echo " Restart a Gecko Port Tunnel"
  echo "======================================================="
  manage_gecko_port_tunnel_pick "restart" || return 1
  systemctl restart "hysteria2-tunnel-${PICKED_SLUG}.service" >/dev/null 2>&1 || true
  systemctl restart "hysteria2-tunnel-${PICKED_SLUG}-client.service" >/dev/null 2>&1 || true
  echo "Restarted (if present on this machine)."
  systemctl status "hysteria2-tunnel-${PICKED_SLUG}.service" --no-pager 2>/dev/null || true
  systemctl status "hysteria2-tunnel-${PICKED_SLUG}-client.service" --no-pager 2>/dev/null || true
}

stop_gecko_port_tunnel() {
  clear
  echo "======================================================="
  echo " Stop a Gecko Port Tunnel"
  echo "======================================================="
  manage_gecko_port_tunnel_pick "stop" || return 1
  systemctl stop "hysteria2-tunnel-${PICKED_SLUG}.service" >/dev/null 2>&1 || true
  systemctl stop "hysteria2-tunnel-${PICKED_SLUG}-client.service" >/dev/null 2>&1 || true
  echo "Stopped (if present on this machine)."
}

uninstall_gecko_port_tunnel() {
  clear
  echo "======================================================="
  echo " Uninstall a Gecko Port Tunnel"
  echo "======================================================="
  manage_gecko_port_tunnel_pick "uninstall" || return 1
  read -rp "Remove tunnel '$PICKED_SLUG' completely? [y/N]: " CONFIRM_REMOVE
  case "$CONFIRM_REMOVE" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Cancelled."; return 0 ;;
  esac
  systemctl disable --now "hysteria2-tunnel-${PICKED_SLUG}.service" >/dev/null 2>&1 || true
  systemctl disable --now "hysteria2-tunnel-${PICKED_SLUG}-client.service" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/hysteria2-tunnel-${PICKED_SLUG}.service" "/etc/systemd/system/hysteria2-tunnel-${PICKED_SLUG}-client.service"
  rm -rf "$GECKO_TUNNELS_BASE_DIR/$PICKED_SLUG"
  systemctl daemon-reload
  echo "Tunnel '$PICKED_SLUG' removed."
}

uninstall_all_gecko_port_tunnels() {
  clear
  echo "======================================================="
  echo " Uninstall ALL Gecko Port Tunnels"
  echo "======================================================="
  if [ -z "$(list_gecko_tunnels)" ]; then
    echo "No tunnels found."
    return 0
  fi
  read -rp "Remove ALL tunnels on this machine? [y/N]: " CONFIRM_ALL
  case "$CONFIRM_ALL" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Cancelled."; return 0 ;;
  esac
  while IFS= read -r SLUG; do
    systemctl disable --now "hysteria2-tunnel-${SLUG}.service" >/dev/null 2>&1 || true
    systemctl disable --now "hysteria2-tunnel-${SLUG}-client.service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/hysteria2-tunnel-${SLUG}.service" "/etc/systemd/system/hysteria2-tunnel-${SLUG}-client.service"
  done < <(list_gecko_tunnels)
  rm -rf "$GECKO_TUNNELS_BASE_DIR"
  systemctl daemon-reload
  echo "All Gecko port tunnels removed."
}


# =======================================================
# GECKO WARP Proxy Outbound - Kharej only
# Uses fscarmen/warp Cloudflare Client Proxy mode and routes
# only Real Gecko server outbound through local SOCKS5 proxy.
# =======================================================

GECKO_WARP_DEFAULT_PORT="40000"
GECKO_WARP_ROUTES_FILE="/etc/hysteria2/warp-routes.txt"

# Auto-detect which Gecko config/service is installed
gecko_warp_detect_config_and_service() {
  if [ -f "/etc/hysteria2/server.yaml" ]; then
    GECKO_WARP_REAL_CONFIG="/etc/hysteria2/server.yaml"
    GECKO_WARP_REAL_SERVICE="hysteria2-gecko.service"
    GECKO_WARP_ROUTES_FILE="/etc/hysteria2/warp-routes.txt"
  else
    GECKO_WARP_REAL_CONFIG=""
    GECKO_WARP_REAL_SERVICE=""
  fi
}

gecko_warp_require_kharej_config() {
  gecko_warp_detect_config_and_service
  [ -n "$GECKO_WARP_REAL_CONFIG" ] && [ -f "$GECKO_WARP_REAL_CONFIG" ] || {
    echo "No Gecko config found. Expected:"
    echo "  /etc/hysteria2/server.yaml  (Install Hysteria2 Gecko first, menu option 3)"
    return 1
  }
  echo "Using config : $GECKO_WARP_REAL_CONFIG"
  echo "Using service: $GECKO_WARP_REAL_SERVICE"
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
  echo " GECKO WARP Proxy Status"
  echo "======================================================="
  gecko_warp_detect_config_and_service
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
    echo " GECKO WARP Proxy Outbound Menu"
    echo "======================================================="
    echo "Purpose: Client -> Gecko Server -> WARP Proxy -> Internet"
    echo "Auto-detects your installed Hysteria2 Gecko config and service."
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


gecko_port_tunnel_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " GECKO Port Tunnel Menu"
    echo "======================================================="
    echo "Architecture: Client -> Iran:PORT -> Gecko tunnel -> Kharej 127.0.0.1:PORT"
    echo "One dedicated port per tunnel. Same port number on Iran and Kharej."
    echo "Carries both TCP and UDP. Always Gecko-obfuscated."
    echo
    echo " 1) Kharej: Create New Port Tunnel"
    echo " 2) Iran:   Connect to a Port Tunnel from Link"
    echo " 3) List tunnels on this machine"
    echo " 4) Show tunnel link / info"
    echo " 5) Restart a tunnel"
    echo " 6) Stop a tunnel"
    echo " 7) Uninstall a tunnel"
    echo " 8) Uninstall ALL tunnels"
    echo " 9) Kharej: WARP Proxy Outbound Menu"
    echo " 0) Back"
    echo "======================================================="
    echo "Gecko-only. No nft/DNAT. No IP forwarding."
    echo "======================================================="
    read -rp "Choose: " TUNNEL_CHOICE
    case "$TUNNEL_CHOICE" in
      1) kharej_install_gecko_port_tunnel; read -rp "Press Enter to return to tunnel menu..." ;;
      2) iran_install_gecko_port_tunnel; read -rp "Press Enter to return to tunnel menu..." ;;
      3) list_gecko_port_tunnels_table; read -rp "Press Enter to return to tunnel menu..." ;;
      4) show_gecko_port_tunnel_link; read -rp "Press Enter to return to tunnel menu..." ;;
      5) restart_gecko_port_tunnel; read -rp "Press Enter to return to tunnel menu..." ;;
      6) stop_gecko_port_tunnel; read -rp "Press Enter to return to tunnel menu..." ;;
      7) uninstall_gecko_port_tunnel; read -rp "Press Enter to return to tunnel menu..." ;;
      8) uninstall_all_gecko_port_tunnels; read -rp "Press Enter to return to tunnel menu..." ;;
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
  echo -e "5)  \e[96mGECKO Port Tunnel Menu (dedicated port per tunnel)\e[0m"
  echo -e "6)  \e[96mHysteria2 Gecko Port Hop Menu (Kharej only)\e[0m"
  echo -e "7)  \e[93mGECKO WARP Proxy Outbound Menu\e[0m"
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
    if [ -f /etc/systemd/system/hysteria2-gecko.service ] || [ -f /etc/hysteria2/server.yaml ]; then
      clear
      echo "======================================================="
      echo " Hysteria2 Gecko is already installed."
      echo "======================================================="
      echo " 1) Reinstall (overwrite)"
      echo " 2) Uninstall"
      echo " 0) Cancel"
      echo "======================================================="
      read -rp "Choose: " HY2_MANAGE_CHOICE
      case "$HY2_MANAGE_CHOICE" in
        1) clear; install_hysteria2_gecko_v292 ;;
        2) clear; uninstall_hysteria2_gecko_v292 ;;
        *) echo "Cancelled." ;;
      esac
    else
      clear
      install_hysteria2_gecko_v292
    fi
    read -rp "Press Enter to return to menu..."
    ;;
  4)
    clear
    apply_hy2_network_and_limits_optimize
    read -rp "Press Enter to return to menu..."
    ;;
  5)
    clear
    gecko_port_tunnel_menu
    ;;
  6)
    clear
    hysteria2_gecko_porthop_menu
    ;;
  7)
    clear
    gecko_warp_proxy_menu
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
