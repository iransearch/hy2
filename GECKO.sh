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
  HY2_LINK="hy2://$EN_AUTH@$SERVER_IP:$HY2_PORT?sni=$EN_SNI&insecure=1&obfs=gecko&obfs-password=$EN_OBFS#$EN_REMARK"

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
# CSF Firewall Manager
# Install, manage ports (TCP/UDP, IN/OUT), manage IPs
# Ubuntu/Debian compatible
# =======================================================

csf_ok_c()   { echo -e "\e[32m[OK]\e[0m $1"; }
csf_err_c()  { echo -e "\e[31m[ERR]\e[0m $1"; }
csf_info_c() { echo -e "\e[34m[*]\e[0m $1"; }
csf_warn_c() { echo -e "\e[33m[!]\e[0m $1"; }

csf_is_installed() { [ -x /usr/sbin/csf ]; }

csf_require_install() {
  if ! csf_is_installed; then
    csf_err_c "CSF is not installed. Please install it first (option 1)."
    return 1
  fi
}

# ---- 1) Install ----

csf_install_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Install"
  echo "======================================================="
  if csf_is_installed; then
    csf_warn_c "CSF is already installed."
    csf --version 2>/dev/null || true
    return 0
  fi

  csf_info_c "Installing dependencies..."
  apt-get update -y
  apt-get install -y wget vim perl libwww-perl liblwp-protocol-https-perl \
    libgd-graph-perl sendmail dnsutils iptables

  csf_info_c "Downloading CSF..."
  cd /usr/src/ || { csf_err_c "Cannot cd to /usr/src/"; return 1; }
  wget -q --show-progress \
    https://github.com/centminmod/configserver-scripts/raw/refs/heads/main/csf.tgz \
    -O csf.tgz || { csf_err_c "Download failed."; return 1; }
  [ -s csf.tgz ] || { csf_err_c "Downloaded file is empty."; return 1; }

  csf_info_c "Extracting..."
  tar -xzf csf.tgz
  cd csf || { csf_err_c "Cannot cd to csf directory."; return 1; }

  csf_info_c "Running installer..."
  sh install.sh

  # Disable firewalld if present
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    csf_info_c "Stopping and disabling firewalld..."
    systemctl stop firewalld
    systemctl disable firewalld
  fi

  # Disable TESTING mode
  csf_info_c "Setting TESTING = 0 in csf.conf..."
  sed -i 's/^TESTING = "1"/TESTING = "0"/' /etc/csf/csf.conf

  # Start and enable services
  systemctl start csf
  systemctl start lfd
  systemctl enable csf
  systemctl enable lfd

  echo
  csf_ok_c "CSF installed and activated."
  echo
  echo "--- CSF test result ---"
  perl /usr/local/csf/bin/csftest.pl 2>/dev/null | tail -5
}

# ---- 2) Start / Stop / Reload ----

csf_control_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Start / Stop / Reload"
  echo "======================================================="
  csf_require_install || return 1
  echo " 1) Start firewall     (csf -s)"
  echo " 2) Stop  firewall     (csf -f)"
  echo " 3) Reload rules       (csf -r)"
  echo " 4) Show status"
  echo " 0) Back"
  echo "======================================================="
  read -rp "Choose: " cc
  case "$cc" in
    1) csf -s && csf_ok_c "Firewall started." ;;
    2) csf -f && csf_ok_c "Firewall stopped." ;;
    3) csf -r && csf_ok_c "Rules reloaded." ;;
    4)
      echo
      echo "--- CSF status ---"
      systemctl is-active csf && echo "csf : active" || echo "csf : inactive"
      systemctl is-active lfd && echo "lfd : active" || echo "lfd : inactive"
      echo
      echo "--- TESTING mode ---"
      grep "^TESTING" /etc/csf/csf.conf
      ;;
    0) return ;;
    *) csf_err_c "Invalid choice." ;;
  esac
}

# ---- helpers: port conf keys ----

# direction: IN / OUT
# proto: tcp / udp
# csf.conf key: TCP_IN, TCP_OUT, UDP_IN, UDP_OUT

csf_conf_key() {
  # $1=proto(tcp|udp) $2=dir(IN|OUT)
  echo "${1^^}_${2^^}"
}

csf_port_exists_in_conf() {
  local key="$1" port="$2"
  local val
  val="$(grep "^${key} = " /etc/csf/csf.conf | head -1 | sed 's/.*= "\(.*\)"/\1/')"
  echo "$val" | tr ',' '\n' | grep -qxF "$port"
}

csf_add_port_to_conf() {
  local key="$1" port="$2"
  local current
  current="$(grep "^${key} = " /etc/csf/csf.conf | head -1 | sed 's/.*= "\(.*\)"/\1/')"
  if [ -z "$current" ]; then
    sed -i "s/^${key} = \".*\"/${key} = \"${port}\"/" /etc/csf/csf.conf
  else
    sed -i "s/^${key} = \".*\"/${key} = \"${current},${port}\"/" /etc/csf/csf.conf
  fi
}

csf_remove_port_from_conf() {
  local key="$1" port="$2"
  local current new_val
  current="$(grep "^${key} = " /etc/csf/csf.conf | head -1 | sed 's/.*= "\(.*\)"/\1/')"
  new_val="$(echo "$current" | tr ',' '\n' | grep -vxF "$port" | paste -sd ',')"
  sed -i "s/^${key} = \".*\"/${key} = \"${new_val}\"/" /etc/csf/csf.conf
}

csf_pick_proto_dir() {
  echo "Protocol:"
  echo "  1) TCP"
  echo "  2) UDP"
  read -rp "Choice: " pc
  case "$pc" in
    1) CSFC_PROTO="tcp" ;;
    2) CSFC_PROTO="udp" ;;
    *) csf_err_c "Invalid protocol."; return 1 ;;
  esac
  echo "Direction:"
  echo "  1) Incoming (IN)"
  echo "  2) Outgoing (OUT)"
  read -rp "Choice: " dc
  case "$dc" in
    1) CSFC_DIR="IN" ;;
    2) CSFC_DIR="OUT" ;;
    *) csf_err_c "Invalid direction."; return 1 ;;
  esac
}

# ---- 3) Add port ----

csf_show_all_ports() {
  # Print numbered list for one key, returns count in CSFC_COUNT_<key>
  local key="$1" color="$2"
  local raw port_list=()
  raw="$(grep "^${key} = " /etc/csf/csf.conf | head -1 | sed 's/.*= "\(.*\)"/\1/')"
  [ -n "$raw" ] && IFS=',' read -ra port_list <<< "$raw"
  echo -e " ${color}${key}\e[0m (${#port_list[@]} ports):"
  if [ ${#port_list[@]} -eq 0 ]; then
    echo "   (none)"
  else
    local i=1
    for p in "${port_list[@]}"; do
      p="$(echo "$p" | tr -d ' ')"
      [ -n "$p" ] && { printf "   %3d) %s\n" "$i" "$p"; i=$((i+1)); }
    done
  fi
}

csf_get_port_list() {
  local key="$1"
  local raw
  raw="$(grep "^${key} = " /etc/csf/csf.conf | head -1 | sed 's/.*= "\(.*\)"/\1/')"
  CSFC_PORT_LIST=()
  [ -n "$raw" ] && IFS=',' read -ra CSFC_PORT_LIST <<< "$raw"
}

csf_port_mgmt_c() {
  csf_require_install || return 1

  while true; do
    clear
    echo "======================================================="
    echo " CSF Firewall — Port Management"
    echo "======================================================="
    csf_show_all_ports "TCP_IN"  "\e[92m"
    echo
    csf_show_all_ports "TCP_OUT" "\e[93m"
    echo
    csf_show_all_ports "UDP_IN"  "\e[96m"
    echo
    csf_show_all_ports "UDP_OUT" "\e[95m"
    echo "======================================================="
    echo " 1) Add port(s)"
    echo " 2) Remove port(s) by number"
    echo " 0) Back"
    echo "======================================================="
    read -rp " Choose: " action

    case "$action" in
      1)
        echo
        echo " Protocol:  1) TCP   2) UDP"
        read -rp " Choice: " pc
        case "$pc" in 1) CSFC_PROTO="tcp" ;; 2) CSFC_PROTO="udp" ;; *) csf_err_c "Invalid."; continue ;; esac
        echo " Direction: 1) IN    2) OUT"
        read -rp " Choice: " dc
        case "$dc" in 1) CSFC_DIR="IN" ;; 2) CSFC_DIR="OUT" ;; *) csf_err_c "Invalid."; continue ;; esac
        local key; key="$(csf_conf_key "$CSFC_PROTO" "$CSFC_DIR")"
        echo
        read -rp " Port(s) to add — comma separated (e.g. 443,8080,9000:9100): " input
        [ -n "$input" ] || { csf_err_c "Input required."; continue; }
        local added=0 skipped=0
        IFS=',' read -ra new_ports <<< "$input"
        for np in "${new_ports[@]}"; do
          np="$(echo "$np" | tr -d ' ')"
          [ -z "$np" ] && continue
          if csf_port_exists_in_conf "$key" "$np"; then
            csf_warn_c "Port $np already in ${key} — skipped."
            skipped=$((skipped+1))
          else
            csf_add_port_to_conf "$key" "$np"
            csf_ok_c "Added $np to ${key}."
            added=$((added+1))
          fi
        done
        echo " Done: $added added, $skipped skipped."
        read -rp " Reload CSF now? [Y/n]: " rr
        case "$rr" in n|N) ;; *) csf -r && csf_ok_c "Rules reloaded." ;; esac
        ;;
      2)
        echo
        echo " Protocol:  1) TCP   2) UDP"
        read -rp " Choice: " pc
        case "$pc" in 1) CSFC_PROTO="tcp" ;; 2) CSFC_PROTO="udp" ;; *) csf_err_c "Invalid."; continue ;; esac
        echo " Direction: 1) IN    2) OUT"
        read -rp " Choice: " dc
        case "$dc" in 1) CSFC_DIR="IN" ;; 2) CSFC_DIR="OUT" ;; *) csf_err_c "Invalid."; continue ;; esac
        local key2; key2="$(csf_conf_key "$CSFC_PROTO" "$CSFC_DIR")"
        csf_get_port_list "$key2"
        if [ ${#CSFC_PORT_LIST[@]} -eq 0 ]; then
          csf_warn_c "No ports in ${key2}."; continue
        fi
        echo
        echo " ${key2} ports:"
        local i=1
        for p in "${CSFC_PORT_LIST[@]}"; do
          p="$(echo "$p" | tr -d ' ')"
          [ -n "$p" ] && { printf "   %3d) %s\n" "$i" "$p"; i=$((i+1)); }
        done
        echo
        read -rp " Number(s) to remove — comma separated (e.g. 2,5,8): " picks
        [ -n "$picks" ] || { csf_err_c "Input required."; continue; }
        # Collect unique valid indices first
        local to_remove=()
        IFS=',' read -ra pick_arr <<< "$picks"
        for pick in "${pick_arr[@]}"; do
          pick="$(echo "$pick" | tr -d ' ')"
          if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#CSFC_PORT_LIST[@]}" ]; then
            csf_warn_c "Invalid number: $pick — skipped."
            continue
          fi
          local tp="${CSFC_PORT_LIST[$((pick-1))]}"
          tp="$(echo "$tp" | tr -d ' ')"
          to_remove+=("$tp")
        done
        local removed=0
        for tp in "${to_remove[@]}"; do
          csf_remove_port_from_conf "$key2" "$tp"
          csf_ok_c "Removed $tp from ${key2}."
          removed=$((removed+1))
        done
        echo " Done: $removed port(s) removed."
        read -rp " Reload CSF now? [Y/n]: " rr
        case "$rr" in n|N) ;; *) csf -r && csf_ok_c "Rules reloaded." ;; esac
        ;;
      0) return ;;
      *) csf_err_c "Invalid choice."; sleep 1 ;;
    esac
  done
}

# ---- 5) Block IP ----

csf_block_ip_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Block IP (add to deny list)"
  echo "======================================================="
  csf_require_install || return 1
  read -rp "IP to block: " ip
  [ -n "$ip" ] || { csf_err_c "IP required."; return 1; }
  csf -d "$ip" && csf_ok_c "IP $ip blocked (added to csf.deny)."
}

# ---- 6) Unblock IP ----

csf_unblock_ip_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Unblock IP (remove from deny list)"
  echo "======================================================="
  csf_require_install || return 1
  echo "Current deny list:"
  grep -v "^#" /etc/csf/csf.deny 2>/dev/null | grep -v "^$" | head -20 | sed 's/^/  /' || echo "  (empty)"
  echo
  read -rp "IP to unblock: " ip
  [ -n "$ip" ] || { csf_err_c "IP required."; return 1; }
  csf -dr "$ip" && csf_ok_c "IP $ip unblocked."
}

# ---- 7) Allow IP ----

csf_allow_ip_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Allow IP (whitelist)"
  echo "======================================================="
  csf_require_install || return 1
  read -rp "IP to allow (or comma-separated list): " ips
  [ -n "$ips" ] || { csf_err_c "IP required."; return 1; }
  IFS=',' read -ra ip_arr <<< "$ips"
  for ip in "${ip_arr[@]}"; do
    ip="$(echo "$ip" | tr -d ' ')"
    [ -z "$ip" ] && continue
    csf -a "$ip" && csf_ok_c "IP $ip allowed (added to csf.allow)."
  done
}

# ---- 8) Remove IP from whitelist ----

csf_remove_allow_ip_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Remove IP from Whitelist"
  echo "======================================================="
  csf_require_install || return 1
  echo "Current allow list:"
  grep -v "^#" /etc/csf/csf.allow 2>/dev/null | grep -v "^$" | head -20 | sed 's/^/  /' || echo "  (empty)"
  echo
  read -rp "IP to remove from whitelist: " ip
  [ -n "$ip" ] || { csf_err_c "IP required."; return 1; }
  csf -ar "$ip" && csf_ok_c "IP $ip removed from whitelist."
}

# ---- 9) Show rules ----

csf_show_rules_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Current Rules"
  echo "======================================================="
  csf_require_install || return 1
  csf -l 2>/dev/null | head -80
}

# ---- 10) Show LFD logs ----

csf_show_logs_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — LFD Logs (last 40 lines)"
  echo "======================================================="
  csf_require_install || return 1
  local logfile=""
  for f in /var/log/lfd.log /var/log/syslog /var/log/messages; do
    [ -f "$f" ] && { logfile="$f"; break; }
  done
  if [ -z "$logfile" ]; then
    csf_warn_c "No log file found. Trying journalctl..."
    journalctl -u lfd -n 40 --no-pager
  else
    tail -n 40 "$logfile"
  fi
}

# ---- 11) PING block ----

csf_ping_block_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — PING Block (ICMP_IN)"
  echo "======================================================="
  csf_require_install || return 1
  local current
  current="$(grep "^ICMP_IN = " /etc/csf/csf.conf | head -1 | grep -oP '"[01]"' | tr -d '"')"
  echo "Current ICMP_IN = \"${current}\""
  echo
  echo " 1) Block PING   (ICMP_IN = 0)"
  echo " 2) Allow PING   (ICMP_IN = 1)"
  echo " 0) Back"
  read -rp "Choose: " pc
  case "$pc" in
    1)
      sed -i 's/^ICMP_IN = ".*"/ICMP_IN = "0"/' /etc/csf/csf.conf
      csf_ok_c "PING blocked (ICMP_IN = 0)."
      read -rp "Reload CSF now? [Y/n]: " rr
      case "$rr" in n|N) ;; *) csf -r && csf_ok_c "Rules reloaded." ;; esac
      ;;
    2)
      sed -i 's/^ICMP_IN = ".*"/ICMP_IN = "1"/' /etc/csf/csf.conf
      csf_ok_c "PING allowed (ICMP_IN = 1)."
      read -rp "Reload CSF now? [Y/n]: " rr
      case "$rr" in n|N) ;; *) csf -r && csf_ok_c "Rules reloaded." ;; esac
      ;;
    0) return ;;
    *) csf_err_c "Invalid choice." ;;
  esac
}

# ---- 12) Uninstall ----

csf_uninstall_c() {
  clear
  echo "======================================================="
  echo " CSF Firewall — Uninstall"
  echo "======================================================="
  csf_require_install || return 1
  read -rp "Uninstall CSF completely? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  if [ -f /etc/csf/uninstall.sh ]; then
    sh /etc/csf/uninstall.sh
  elif [ -f /usr/src/csf/uninstall.sh ]; then
    sh /usr/src/csf/uninstall.sh
  else
    csf_warn_c "Uninstall script not found. Removing manually..."
    systemctl stop csf lfd 2>/dev/null || true
    systemctl disable csf lfd 2>/dev/null || true
    rm -rf /etc/csf /usr/local/csf
    rm -f /usr/sbin/csf /usr/sbin/lfd
    systemctl daemon-reload
  fi
  csf_ok_c "CSF uninstalled."
}

# ---- Main menu ----

csf_lfd_ssh_mgmt_c() {
  csf_require_install || return 1

  while true; do
    clear
    echo "======================================================="
    echo " CSF — LFD SSH Brute-Force Settings"
    echo "======================================================="

    # Read current values
    local cur_count cur_interval cur_perm cur_temp cur_temp_dur
    cur_count="$(grep    "^LF_SSHD ="       /etc/csf/csf.conf | head -1 | grep -oP '"\K[^"]+')"
    cur_interval="$(grep "^LF_TRIGGER_PERM" /etc/csf/csf.conf | head -1 | grep -oP '"\K[^"]+'  || echo "?")"
    cur_perm="$(grep     "^LF_SSHD_PERM ="  /etc/csf/csf.conf | head -1 | grep -oP '"\K[^"]+')"
    cur_temp="$(grep     "^LF_SSHD_TEMP ="  /etc/csf/csf.conf | head -1 | grep -oP '"\K[^"]+')"
    cur_temp_dur="$(grep "^LF_TEMP_BLOCK ="  /etc/csf/csf.conf | head -1 | grep -oP '"\K[^"]+')"

    # Block mode: PERM=1 means permanent, TEMP=1 means temporary
    local block_mode="unknown"
    [ "$cur_perm" = "1" ] && block_mode="Permanent"
    [ "$cur_temp" = "1" ] && block_mode="Temporary (${cur_temp_dur}s)"
    [ "$cur_perm" = "1" ] && [ "$cur_temp" = "1" ] && block_mode="Both (Perm+Temp)"
    [ "$cur_perm" = "0" ] && [ "$cur_temp" = "0" ] && block_mode="Disabled"

    echo " Current settings:"
    echo "   Failed attempts before block : ${cur_count}"
    echo "   Block mode                   : ${block_mode}"
    [ "$cur_temp" = "1" ] &&     echo "   Temporary block duration     : ${cur_temp_dur} seconds ($(( ${cur_temp_dur:-0} / 60 )) min)"
    echo "======================================================="
    echo " 1) Change failed attempt limit  (LF_SSHD)"
    echo " 2) Set block mode               (Permanent / Temporary / Both)"
    echo " 3) Change temporary block duration (LF_TEMP_BLOCK)"
    echo " 4) Disable SSH brute-force protection"
    echo " 0) Back"
    echo "======================================================="
    read -rp " Choose: " lfd_choice

    case "$lfd_choice" in
      1)
        echo
        echo " Current: LF_SSHD = "${cur_count}""
        echo " (0 = disabled, recommended: 5-10)"
        read -rp " New value: " new_val
        if ! [[ "$new_val" =~ ^[0-9]+$ ]]; then
          csf_err_c "Must be a number."; sleep 1; continue
        fi
        sed -i "s/^LF_SSHD = \".*\"/LF_SSHD = \"${new_val}\"/" /etc/csf/csf.conf
        csf_ok_c "LF_SSHD set to ${new_val}."
        read -rp " Restart LFD now? [Y/n]: " rr
        case "$rr" in n|N) ;; *) systemctl restart lfd && csf_ok_c "LFD restarted." ;; esac
        ;;
      2)
        echo
        echo " Block mode:"
        echo "   1) Permanent  — blocked IP never auto-unblocked"
        echo "   2) Temporary  — blocked IP unblocked after LF_TEMP_BLOCK seconds"
        echo "   3) Both       — block permanently AND add temporary rule"
        read -rp " Choose: " bm
        case "$bm" in
          1)
            sed -i "s/^LF_SSHD_PERM = \".*\"/LF_SSHD_PERM = \"1\"/" /etc/csf/csf.conf
            sed -i "s/^LF_SSHD_TEMP = \".*\"/LF_SSHD_TEMP = \"0\"/" /etc/csf/csf.conf
            csf_ok_c "Block mode: Permanent."
            ;;
          2)
            sed -i "s/^LF_SSHD_PERM = \".*\"/LF_SSHD_PERM = \"0\"/" /etc/csf/csf.conf
            sed -i "s/^LF_SSHD_TEMP = \".*\"/LF_SSHD_TEMP = \"1\"/" /etc/csf/csf.conf
            csf_ok_c "Block mode: Temporary."
            ;;
          3)
            sed -i "s/^LF_SSHD_PERM = \".*\"/LF_SSHD_PERM = \"1\"/" /etc/csf/csf.conf
            sed -i "s/^LF_SSHD_TEMP = \".*\"/LF_SSHD_TEMP = \"1\"/" /etc/csf/csf.conf
            csf_ok_c "Block mode: Permanent + Temporary."
            ;;
          *) csf_err_c "Invalid."; sleep 1; continue ;;
        esac
        read -rp " Restart LFD now? [Y/n]: " rr
        case "$rr" in n|N) ;; *) systemctl restart lfd && csf_ok_c "LFD restarted." ;; esac
        ;;
      3)
        echo
        echo " Current: LF_TEMP_BLOCK = "${cur_temp_dur}" seconds"
        echo " Examples: 3600 = 1hr  |  86400 = 24hr  |  604800 = 7 days"
        read -rp " New duration (seconds): " new_dur
        if ! [[ "$new_dur" =~ ^[0-9]+$ ]]; then
          csf_err_c "Must be a number in seconds."; sleep 1; continue
        fi
        local hrs=$(( new_dur / 3600 ))
        local mins=$(( (new_dur % 3600) / 60 ))
        sed -i "s/^LF_TEMP_BLOCK = \".*\"/LF_TEMP_BLOCK = \"${new_dur}\"/" /etc/csf/csf.conf
        csf_ok_c "LF_TEMP_BLOCK set to ${new_dur}s (${hrs}h ${mins}m)."
        read -rp " Restart LFD now? [Y/n]: " rr
        case "$rr" in n|N) ;; *) systemctl restart lfd && csf_ok_c "LFD restarted." ;; esac
        ;;
      4)
        echo
        csf_warn_c "This will disable SSH brute-force protection (LF_SSHD = 0)."
        read -rp " Are you sure? [y/N]: " confirm
        case "$confirm" in
          y|Y|yes|YES)
            sed -i "s/^LF_SSHD = \".*\"/LF_SSHD = \"0\"/" /etc/csf/csf.conf
            csf_ok_c "SSH brute-force protection disabled."
            read -rp " Restart LFD now? [Y/n]: " rr
            case "$rr" in n|N) ;; *) systemctl restart lfd && csf_ok_c "LFD restarted." ;; esac
            ;;
          *) echo " Cancelled." ;;
        esac
        ;;
      0) return ;;
      *) csf_err_c "Invalid choice."; sleep 1 ;;
    esac
  done
}

csf_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " CSF Firewall Menu"
    echo "======================================================="
    if csf_is_installed; then
      local csf_state lfd_state testing
      csf_state="$(systemctl is-active csf 2>/dev/null)"
      lfd_state="$(systemctl is-active lfd 2>/dev/null)"
      testing="$(grep "^TESTING = " /etc/csf/csf.conf 2>/dev/null | grep -oP '"[01]"' | tr -d '"')"
      echo " csf: [$csf_state]  lfd: [$lfd_state]  TESTING: [${testing:-?}]"
    else
      echo " CSF: [NOT INSTALLED]"
    fi
    echo "======================================================="
    echo " 1)  Install CSF"
    echo " 2)  Start / Stop / Reload"
    echo " 3)  Port Management (TCP/UDP · IN/OUT)"
    echo " 4)  Block IP   (add to deny list)"
    echo " 5)  Unblock IP (remove from deny list)"
    echo " 6)  Allow IP   (whitelist)"
    echo " 7)  Remove IP from whitelist"
    echo " 8)  Show firewall rules"
    echo " 9)  Show LFD logs"
    echo " 10) PING block (ICMP_IN)"
    echo " 11) LFD — SSH Brute-Force Settings"
    echo " 12) Uninstall CSF"
    echo " 0)  Back"
    echo "======================================================="
    read -rp "Choose: " CSF_CHOICE
    case "$CSF_CHOICE" in
      1)  csf_install_c;         read -rp "Press Enter to continue..." ;;
      2)  csf_control_c;         read -rp "Press Enter to continue..." ;;
      3)  csf_port_mgmt_c;       read -rp "Press Enter to continue..." ;;
      4)  csf_block_ip_c;        read -rp "Press Enter to continue..." ;;
      5)  csf_unblock_ip_c;      read -rp "Press Enter to continue..." ;;
      6)  csf_allow_ip_c;        read -rp "Press Enter to continue..." ;;
      7)  csf_remove_allow_ip_c; read -rp "Press Enter to continue..." ;;
      8)  csf_show_rules_c;      read -rp "Press Enter to continue..." ;;
      9)  csf_show_logs_c;       read -rp "Press Enter to continue..." ;;
      10) csf_ping_block_c;      read -rp "Press Enter to continue..." ;;
      11) csf_lfd_ssh_mgmt_c;    read -rp "Press Enter to continue..." ;;
      12) csf_uninstall_c;       read -rp "Press Enter to continue..." ;;
      0)  return ;;
      *)  echo "Invalid choice."; sleep 1 ;;
    esac
  done
}


# =======================================================
# GOST Multi-Tunnel Manager
# Multiple named tunnels, each to a different destination.
# Forwarding: this-server:PORT -> destination:PORT (same port)
# Each tunnel = its own systemd service: gostm_<name>.service
# Supports TCP / UDP / gRPC, IPv4 and IPv6 destinations.
# =======================================================

GOST_BIN_M="/usr/local/bin/gost"
GOST_SVC_PREFIX_M="gostm_"
GOST_SVC_DIR_M="/etc/systemd/system"

gost_ok_m()   { echo -e "\e[32m[OK]\e[0m $1"; }
gost_err_m()  { echo -e "\e[31m[ERR]\e[0m $1"; }
gost_info_m() { echo -e "\e[34m[*]\e[0m $1"; }
gost_warn_m() { echo -e "\e[33m[!]\e[0m $1"; }

gost_valid_name_m() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

gost_ensure_bin_m() {
  if [ -x "$GOST_BIN_M" ]; then return 0; fi
  gost_warn_m "gost binary not found at $GOST_BIN_M"
  read -rp "Install GOST v3 now? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) gost_err_m "Cannot continue without gost."; return 1 ;; esac
  command -v wget >/dev/null 2>&1 || { apt-get update -y && apt-get install -y wget tar curl; }
  gost_info_m "Downloading GOST v3..."
  local url="https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_amd64.tar.gz"
  wget -qO /tmp/gost.tar.gz "$url" || { gost_err_m "Download failed."; return 1; }
  [ -s /tmp/gost.tar.gz ] || { gost_err_m "Downloaded file is empty."; return 1; }
  tar -xzf /tmp/gost.tar.gz -C /usr/local/bin/ gost 2>/dev/null || \
    tar -xzf /tmp/gost.tar.gz -C /usr/local/bin/
  chmod +x "$GOST_BIN_M"
  rm -f /tmp/gost.tar.gz
  [ -x "$GOST_BIN_M" ] && gost_ok_m "GOST installed." || { gost_err_m "Install failed."; return 1; }
}

gost_create_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — Create New"
  echo "======================================================="
  echo " Forwards this-server:PORT -> destination:PORT (same port)"
  echo "======================================================="
  gost_ensure_bin_m || return 1

  read -rp "Tunnel name (letters/numbers/-/_): " name
  if ! gost_valid_name_m "$name"; then
    gost_err_m "Invalid name. Use only letters, numbers, - and _"; return 1
  fi
  local svc="${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}${name}.service"
  if [ -f "$svc" ]; then
    gost_err_m "A tunnel named '$name' already exists. Delete it first or pick another name."
    return 1
  fi

  read -rp "Destination IP (IPv4 or IPv6): " dest
  [ -n "$dest" ] || { gost_err_m "Destination required."; return 1; }

  echo "Ports: comma-separated (e.g. 8880,2052,443)"
  read -rp "Ports: " ports
  [ -n "$ports" ] || { gost_err_m "At least one port required."; return 1; }

  echo "Protocol:  1) TCP   2) UDP   3) gRPC"
  read -rp "Choice: " p
  case "$p" in
    1) proto="tcp" ;;
    2) proto="udp" ;;
    3) proto="grpc" ;;
    *) gost_err_m "Invalid protocol."; return 1 ;;
  esac

  local dest_fmt="$dest"
  [[ "$dest" == *:* ]] && dest_fmt="[$dest]"

  local exec_line="ExecStart=${GOST_BIN_M}"
  local good=0
  IFS=',' read -ra parr <<< "$ports"
  for raw in "${parr[@]}"; do
    local port; port="$(echo "$raw" | tr -d ' ')"
    [ -z "$port" ] && continue
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      gost_err_m "Invalid port: $port"; return 1
    fi
    exec_line+=" -L=${proto}://:${port}/${dest_fmt}:${port}"
    good=1
  done
  [ "$good" -eq 1 ] || { gost_err_m "No valid ports."; return 1; }

  cat > "$svc" <<EOF
[Unit]
Description=GOST Multi-Tunnel ($name -> $dest)
After=network.target
Wants=network.target

[Service]
Type=simple
Environment="GOST_LOGGER_LEVEL=fatal"
$exec_line
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${GOST_SVC_PREFIX_M}${name}" >/dev/null 2>&1
  systemctl restart "${GOST_SVC_PREFIX_M}${name}"
  sleep 2

  echo
  if systemctl is-active --quiet "${GOST_SVC_PREFIX_M}${name}"; then
    gost_ok_m "Tunnel '$name' is RUNNING."
    echo " Forwards:"
    for raw in "${parr[@]}"; do
      local port; port="$(echo "$raw" | tr -d ' ')"
      [ -n "$port" ] && echo "   this-server:$port -> $dest:$port ($proto)"
    done
  else
    gost_err_m "Tunnel failed to start. Recent logs:"
    journalctl -u "${GOST_SVC_PREFIX_M}${name}" -n 15 --no-pager
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo
    gost_warn_m "ufw is active. Allow your ports, e.g.:"
    for raw in "${parr[@]}"; do
      local port; port="$(echo "$raw" | tr -d ' ')"
      [ -n "$port" ] && echo "   ufw allow $port"
    done
  fi
}

gost_list_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — List"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}"*.service)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    gost_warn_m "No GOST tunnels created yet."
    return 0
  fi
  for f in "${files[@]}"; do
    local base name state dest
    base="$(basename "$f")"
    name="${base#$GOST_SVC_PREFIX_M}"; name="${name%.service}"
    state="$(systemctl is-active "$base" 2>/dev/null)"
    dest="$(grep -oP 'Description=GOST Multi-Tunnel \(\K[^)]+' "$f")"
    echo -e "\e[96m$name\e[0m  [$state]"
    echo "   $dest"
    grep -oP -- '-L=\K[^ ]+' "$f" | sed 's/^/     /'
    echo
  done
}

gost_delete_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — Delete"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}"*.service)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    gost_warn_m "No tunnels to delete."; return 0
  fi
  echo "Existing tunnels:"
  for f in "${files[@]}"; do
    local base name; base="$(basename "$f")"
    name="${base#$GOST_SVC_PREFIX_M}"; name="${name%.service}"
    echo "  - $name"
  done
  echo
  read -rp "Name to delete: " name
  gost_valid_name_m "$name" || { gost_err_m "Invalid name."; return 1; }
  local svc="${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}${name}.service"
  [ -f "$svc" ] || { gost_err_m "No tunnel named '$name'."; return 1; }
  read -rp "Confirm delete '$name'? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  systemctl disable --now "${GOST_SVC_PREFIX_M}${name}" >/dev/null 2>&1
  rm -f "$svc"
  systemctl daemon-reload
  gost_ok_m "Tunnel '$name' deleted."
}

gost_status_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — Status / Logs"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}"*.service)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    gost_warn_m "No GOST tunnels found."; return 0
  fi
  local names=()
  local i=1
  echo "Choose a tunnel:"
  for f in "${files[@]}"; do
    local base name state
    base="$(basename "$f")"
    name="${base#$GOST_SVC_PREFIX_M}"; name="${name%.service}"
    state="$(systemctl is-active "$base" 2>/dev/null)"
    names+=("$name")
    echo "  $i) $name  [$state]"
    i=$((i+1))
  done
  echo
  read -rp "Number: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#names[@]}" ]; then
    gost_err_m "Invalid choice."; return 1
  fi
  local selected="${names[$((pick-1))]}"
  local unit="${GOST_SVC_PREFIX_M}${selected}"
  echo
  systemctl status "$unit" --no-pager | head -15
  echo
  echo "Last 20 log lines:"
  journalctl -u "$unit" -n 20 --no-pager
}

gost_restart_all_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — Restart ALL"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}"*.service)
  shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { gost_warn_m "No GOST tunnels."; return 0; }
  systemctl daemon-reload
  for f in "${files[@]}"; do
    local base; base="$(basename "$f")"
    systemctl restart "$base"
    gost_ok_m "Restarted $base"
  done
}

gost_uninstall_all_m() {
  clear
  echo "======================================================="
  echo " GOST Multi-Tunnel — Uninstall ALL"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_M}/${GOST_SVC_PREFIX_M}"*.service)
  shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { gost_warn_m "No GOST tunnels to remove."; return 0; }
  read -rp "Remove ALL GOST tunnels (gostm_*)? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  for f in "${files[@]}"; do
    local base; base="$(basename "$f")"
    systemctl disable --now "$base" >/dev/null 2>&1
    rm -f "$f"
  done
  systemctl daemon-reload
  gost_ok_m "All GOST tunnels removed."
  read -rp "Also remove gost binary ($GOST_BIN_M)? [y/N]: " rb
  case "$rb" in y|Y|yes|YES|Yes) rm -f "$GOST_BIN_M"; gost_ok_m "gost binary removed." ;; esac
}

gost_auto_clear_cache_m() {
  clear
  echo "======================================================="
  echo " GOST — Auto Clear Cache"
  echo "======================================================="
  echo " 1) Enable Auto Clear Cache"
  echo " 2) Disable Auto Clear Cache"
  echo " 0) Back"
  echo "======================================================="
  read -rp "Choose: " acc_choice
  case "$acc_choice" in
    1)
      read -rp "Interval in days (e.g. 1=daily, 7=weekly): " interval_days
      if ! [[ "$interval_days" =~ ^[0-9]+$ ]] || [ "$interval_days" -lt 1 ]; then
        gost_err_m "Invalid interval."; return 1
      fi
      local cron_interval="0 0 */${interval_days} * *"
      (crontab -l 2>/dev/null | grep -v "drop_caches"; \
       echo "${cron_interval} sync; echo 1 > /proc/sys/vm/drop_caches && sync; echo 2 > /proc/sys/vm/drop_caches && sync; echo 3 > /proc/sys/vm/drop_caches") \
        | crontab -
      gost_ok_m "Auto Clear Cache enabled (every ${interval_days} day(s))."
      ;;
    2)
      crontab -l 2>/dev/null | grep -v "drop_caches" | crontab -
      gost_ok_m "Auto Clear Cache disabled."
      ;;
    0) return ;;
    *) gost_err_m "Invalid choice." ;;
  esac
}

gost_multi_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " GOST Multi-Tunnel Menu"
    echo "======================================================="
    echo " Forward this-server:PORT -> destination:PORT (same port)"
    echo " Each tunnel is its own systemd service (gostm_<name>)"
    echo " Supports TCP / UDP / gRPC · IPv4 and IPv6"
    echo "======================================================="
    echo " 1) Create tunnel"
    echo " 2) List tunnels"
    echo " 3) Delete tunnel"
    echo " 4) Status / logs of a tunnel"
    echo " 5) Restart ALL tunnels"
    echo " 6) Uninstall ALL tunnels"
    echo " 7) Auto Clear Cache"
    echo " 0) Back"
    echo "======================================================="
    read -rp "Choose: " GOST_M_CHOICE
    case "$GOST_M_CHOICE" in
      1) gost_create_m;            read -rp "Press Enter to return to menu..." ;;
      2) gost_list_m;              read -rp "Press Enter to return to menu..." ;;
      3) gost_delete_m;            read -rp "Press Enter to return to menu..." ;;
      4) gost_status_m;            read -rp "Press Enter to return to menu..." ;;
      5) gost_restart_all_m;       read -rp "Press Enter to return to menu..." ;;
      6) gost_uninstall_all_m;     read -rp "Press Enter to return to menu..." ;;
      7) gost_auto_clear_cache_m;  read -rp "Press Enter to return to menu..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
}


# =======================================================
# GECKO Relay Tunnel
# Hysteria2 + Gecko obfs tunnel between two servers.
# Kharej (exit) = server side.  Iran (entry) = client side.
# Each tunnel lives in: /etc/hysteria2-gtunnels/<name>/
# Service per instance: hysteria2-gtunnel@<name>.service
# =======================================================

GTUN_DIR="/etc/hysteria2-gtunnels"
GTUN_SVC_TEMPLATE="/etc/systemd/system/hysteria2-gtunnel@.service"
GTUN_BIN="/usr/local/bin/hysteria"
GTUN_TLS_DIR="/etc/hysteria2-gtunnels/tls"
GECKO_MIN_PKT=512
GECKO_MAX_PKT=1200

# ---- helpers ----

gtun_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

gtun_idir() { printf '%s/%s' "$GTUN_DIR" "$1"; }

gtun_meta_set() { mkdir -p "$(gtun_idir "$1")"; echo "$3" > "$(gtun_idir "$1")/$2.meta"; }
gtun_meta_get() { local f="$(gtun_idir "$1")/$2.meta"; [ -f "$f" ] && cat "$f" || echo ""; }

gtun_instances() {
  [ -d "$GTUN_DIR" ] || return 0
  find "$GTUN_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -v '^tls$' | sort
}

gtun_svc() { printf 'hysteria2-gtunnel@%s.service' "$1"; }

gtun_svc_state() {
  systemctl is-active "$(gtun_svc "$1")" 2>/dev/null || echo "inactive"
}

gtun_yaml_quote() {
  python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$1"
}

gtun_urlencode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

gtun_ensure_binary() {
  if [ -x "$GTUN_BIN" ]; then return 0; fi
  echo "Hysteria binary not found at $GTUN_BIN. Installing..."
  local arch
  case "$(uname -m)" in
    x86_64|amd64)   arch="amd64" ;;
    aarch64|arm64)  arch="arm64" ;;
    armv7l|armv7)   arch="armv7" ;;
    i386|i686)      arch="386"   ;;
    *) echo "Unsupported architecture."; return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl; }
  local url="https://github.com/apernet/hysteria/releases/download/app%2Fv2.9.2/hysteria-linux-${arch}"
  local tmp; tmp="$(mktemp /tmp/hysteria-gtun.XXXXXX)"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
    rm -f "$tmp"; echo "Download failed."; return 1
  fi
  install -m 0755 "$tmp" "$GTUN_BIN.new"
  mv -f "$GTUN_BIN.new" "$GTUN_BIN"
  rm -f "$tmp"
  echo "Hysteria installed."
}

gtun_gen_tls() {
  local sni="$1"
  mkdir -p "$GTUN_TLS_DIR"
  if [ -f "$GTUN_TLS_DIR/cert.crt" ] && [ -f "$GTUN_TLS_DIR/cert.key" ]; then return 0; fi
  command -v openssl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y openssl; }
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$GTUN_TLS_DIR/cert.key" \
    -out    "$GTUN_TLS_DIR/cert.crt" \
    -subj   "/CN=${sni:-www.google.com}" \
    -days 3650 >/dev/null 2>&1
  chmod 600 "$GTUN_TLS_DIR/cert.key"
}

gtun_install_template() {
  [ -f "$GTUN_SVC_TEMPLATE" ] && return 0
  cat > "$GTUN_SVC_TEMPLATE" <<EOF
[Unit]
Description=GECKO Relay Tunnel (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash /etc/hysteria2-gtunnels/%i/run.sh
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

gtun_write_run_script() {
  local name="$1" role="$2" dir
  dir="$(gtun_idir "$name")"
  cat > "$dir/run.sh" <<EOF
#!/bin/bash
exec $GTUN_BIN $([ "$role" = "exit" ] && echo "server" || echo "client") -c "$dir/config.yaml"
EOF
  chmod +x "$dir/run.sh"
}

gtun_start() {
  local name="$1"
  systemctl daemon-reload
  systemctl enable "$(gtun_svc "$name")" >/dev/null 2>&1
  systemctl restart "$(gtun_svc "$name")"
  sleep 2
  if systemctl is-active --quiet "$(gtun_svc "$name")"; then
    echo "Tunnel '$name' is ACTIVE."
    return 0
  else
    echo "Tunnel '$name' failed to start. Recent log:"
    journalctl -u "$(gtun_svc "$name")" -n 15 --no-pager
    return 1
  fi
}

# ---- Kharej (exit/server) ----

gtun_write_exit_config() {
  local name="$1" dir; dir="$(gtun_idir "$name")"
  local port auth obfs sni up down
  port="$(gtun_meta_get "$name" PORT)"
  auth="$(gtun_meta_get "$name" AUTH)"
  obfs="$(gtun_meta_get "$name" OBFS)"
  sni="$(gtun_meta_get "$name"  SNI)";  sni="${sni:-www.google.com}"
  up="$(gtun_meta_get "$name"   UP)";   up="${up:-100}"
  down="$(gtun_meta_get "$name" DOWN)"; down="${down:-100}"

  local AUTH_Y OBFS_Y
  AUTH_Y="$(gtun_yaml_quote "$auth")"
  OBFS_Y="$(gtun_yaml_quote "$obfs")"

  cat > "$dir/config.yaml" <<EOF
listen: :${port}

tls:
  cert: ${GTUN_TLS_DIR}/cert.crt
  key:  ${GTUN_TLS_DIR}/cert.key
  sniGuard: disable

auth:
  type: password
  password: ${AUTH_Y}

obfs:
  type: gecko
  gecko:
    password: ${OBFS_Y}
    minPacketSize: ${GECKO_MIN_PKT}
    maxPacketSize: ${GECKO_MAX_PKT}

bandwidth:
  up:   ${up} mbps
  down: ${down} mbps

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
}

gtun_write_entry_config() {
  local name="$1" dir; dir="$(gtun_idir "$name")"
  local server_ip port ports auth obfs up down hop_interval
  server_ip="$(gtun_meta_get "$name" REMOTE_IP)"
  port="$(gtun_meta_get "$name"      PORT)"
  ports="$(gtun_meta_get "$name"     PORTS)"
  auth="$(gtun_meta_get "$name"      AUTH)"
  obfs="$(gtun_meta_get "$name"      OBFS)"
  up="$(gtun_meta_get "$name"        UP)";  up="${up:-100}"
  down="$(gtun_meta_get "$name"      DOWN)"; down="${down:-100}"
  hop_interval="$(gtun_meta_get "$name" HOP_INTERVAL)"; hop_interval="${hop_interval:-30s}"

  local AUTH_Y OBFS_Y
  AUTH_Y="$(gtun_yaml_quote "$auth")"
  OBFS_Y="$(gtun_yaml_quote "$obfs")"

  {
    echo "server: ${server_ip}:${port}"
    echo ""
    echo "auth: ${AUTH_Y}"
    echo ""
    echo "tls:"
    echo "  insecure: true"
    echo ""
    echo "obfs:"
    echo "  type: gecko"
    echo "  gecko:"
    echo "    password: ${OBFS_Y}"
    echo "    minPacketSize: ${GECKO_MIN_PKT}"
    echo "    maxPacketSize: ${GECKO_MAX_PKT}"
    echo ""
    echo "bandwidth:"
    echo "  up:   ${up} mbps"
    echo "  down: ${down} mbps"
    echo ""
    echo "fastOpen: true"
    echo ""
    echo "quic:"
    echo "  initStreamReceiveWindow: 8388608"
    echo "  maxStreamReceiveWindow: 8388608"
    echo "  initConnReceiveWindow: 20971520"
    echo "  maxConnReceiveWindow: 20971520"
    echo "  maxIdleTimeout: 60s"
    echo "  keepAlivePeriod: 10s"
    echo "  maxIncomingStreams: 1024"
    echo "  disablePathMTUDiscovery: false"
    if [[ "$port" == *-* ]]; then
      echo ""
      echo "transport:"
      echo "  type: udp"
      echo "  udp:"
      echo "    hopInterval: ${hop_interval}"
    fi
    echo ""
    echo "tcpForwarding:"
    local p
    IFS=',' read -ra parr <<< "$ports"
    for p in "${parr[@]}"; do
      p="$(echo "$p" | tr -d ' ')"
      [ -n "$p" ] || continue
      echo "  - listen: :${p}"
      echo "    remote: 127.0.0.1:${p}"
    done
    echo ""
    echo "udpForwarding:"
    for p in "${parr[@]}"; do
      p="$(echo "$p" | tr -d ' ')"
      [ -n "$p" ] || continue
      echo "  - listen: :${p}"
      echo "    remote: 127.0.0.1:${p}"
      echo "    timeout: 60s"
    done
  } > "$dir/config.yaml"
}

gtun_make_link() {
  local name="$1"
  local server_ip port auth obfs sni remark
  server_ip="$(gtun_meta_get "$name" SERVER_IP)"
  port="$(gtun_meta_get "$name"      PORT)"
  auth="$(gtun_meta_get "$name"      AUTH)"
  obfs="$(gtun_meta_get "$name"      OBFS)"
  sni="$(gtun_meta_get "$name"       SNI)";    sni="${sni:-www.google.com}"
  remark="$(gtun_meta_get "$name"    REMARK)"; remark="${remark:-GECKO-RELAY-$name}"

  local EA EO ES ER
  EA="$(gtun_urlencode "$auth")"
  EO="$(gtun_urlencode "$obfs")"
  ES="$(gtun_urlencode "$sni")"
  ER="$(gtun_urlencode "$remark")"

  # Port hopping: use mport= for ranges
  local port_param
  if [[ "$port" == *-* ]]; then
    port_param="mport=${port}"
    port="${port%%-*}"  # main port for the URI host
  else
    port_param=""
  fi

  local link="hy2://${EA}@${server_ip}:${port}?sni=${ES}&insecure=1&obfs=gecko&obfs-password=${EO}"
  [ -n "$port_param" ] && link="${link}&${port_param}"
  link="${link}#${ER}"
  echo "$link"
}

# ---- Setup: Kharej ----

gtun_setup_kharej() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Kharej (Exit) Setup"
  echo "======================================================="
  echo "This server will be the EXIT node."
  echo "Run setup on Iran (entry) after this completes."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }

  gtun_ensure_binary   || return 1
  gtun_install_template

  local raw name
  read -rp "Tunnel name [gtun1]: " raw
  raw="${raw:-gtun1}"
  name="$(gtun_slug "$raw")"
  if [ -z "$name" ]; then echo "Invalid name."; return 1; fi
  if [ -d "$(gtun_idir "$name")" ]; then
    echo "Tunnel '$name' already exists. Delete it first."
    return 1
  fi
  mkdir -p "$(gtun_idir "$name")"
  gtun_meta_set "$name" ROLE "exit"

  local DEFAULT_AUTH DEFAULT_OBFS
  DEFAULT_AUTH="$(openssl rand -hex 16 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')"
  DEFAULT_OBFS="$(openssl rand -base64 18 2>/dev/null | tr -d '=+/' || cat /proc/sys/kernel/random/uuid)"

  local AUTH OBFS SNI REMARK PORT UP DOWN
  read -rp "Auth password [$DEFAULT_AUTH]: " AUTH;   AUTH="${AUTH:-$DEFAULT_AUTH}"
  read -rp "Gecko obfs password [$DEFAULT_OBFS]: " OBFS; OBFS="${OBFS:-$DEFAULT_OBFS}"
  read -rp "SNI / certificate CN [www.google.com]: " SNI; SNI="${SNI:-www.google.com}"
  read -rp "Link port (or range e.g. 8000-9000 for hopping) [443]: " PORT; PORT="${PORT:-443}"
  if ! validate_port_or_range_hy2_global "$PORT" 2>/dev/null; then
    if [[ ! "$PORT" =~ ^[0-9]+-[0-9]+$ ]] && ! [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]]; then
      echo "Invalid port or range."; rm -rf "$(gtun_idir "$name")"; return 1
    fi
  fi
  read -rp "Remark [GECKO-RELAY-${name}]: " REMARK; REMARK="${REMARK:-GECKO-RELAY-${name}}"
  read -rp "Upload mbps [100]: " UP;   UP="${UP:-100}"
  read -rp "Download mbps [100]: " DOWN; DOWN="${DOWN:-100}"

  gtun_meta_set "$name" AUTH    "$AUTH"
  gtun_meta_set "$name" OBFS    "$OBFS"
  gtun_meta_set "$name" SNI     "$SNI"
  gtun_meta_set "$name" PORT    "$PORT"
  gtun_meta_set "$name" REMARK  "$REMARK"
  gtun_meta_set "$name" UP      "$UP"
  gtun_meta_set "$name" DOWN    "$DOWN"

  gtun_gen_tls "$SNI"
  gtun_write_exit_config "$name"
  gtun_write_run_script  "$name" "exit"

  # Firewall
  local main_port="${PORT%%-*}"
  command -v ufw >/dev/null 2>&1 && ufw allow "${main_port}/udp" >/dev/null 2>&1 || true
  if [[ "$PORT" == *-* ]]; then
    local p2="${PORT##*-}"
    command -v ufw >/dev/null 2>&1 && ufw allow "${main_port}:${p2}/udp" >/dev/null 2>&1 || true
  fi

  gtun_start "$name" || { rm -rf "$(gtun_idir "$name")"; return 1; }

  # Save public IP for link generation
  local SERVER_IP
  SERVER_IP="$(curl -4fsSL --max-time 6 https://api.ipify.org 2>/dev/null \
             || curl -4fsSL --max-time 6 https://ifconfig.me 2>/dev/null \
             || hostname -I | awk '{print $1}')"
  gtun_meta_set "$name" SERVER_IP "$SERVER_IP"

  local link; link="$(gtun_make_link "$name")"
  echo "$link" > "$(gtun_idir "$name")/link.txt"

  echo
  echo "======================================================="
  echo " GECKO Relay Tunnel '$name' is LIVE on Kharej."
  echo "======================================================="
  echo " Link port : $PORT"
  echo " Auth      : $AUTH"
  echo " Obfs      : $OBFS"
  echo "-------------------------------------------------------"
  echo " Share link (add to Iran entry):"
  echo ""
  echo " $link"
  echo ""
  echo " Link saved: $(gtun_idir "$name")/link.txt"
  echo "======================================================="
  echo
  echo "Next: run this script on the IRAN server, choose"
  echo "'GECKO Relay Tunnel Menu' -> 'Iran: Connect from link',"
  echo "and paste the link above."
}

# ---- Setup: Iran (entry from link) ----

gtun_setup_iran() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Iran (Entry) Setup"
  echo "======================================================="
  echo "This server will be the ENTRY node."
  echo "You need the hy2://... link from the Kharej setup."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }

  gtun_ensure_binary   || return 1
  gtun_install_template

  local raw name
  read -rp "Tunnel name [gtun1]: " raw
  raw="${raw:-gtun1}"
  name="$(gtun_slug "$raw")"
  if [ -z "$name" ]; then echo "Invalid name."; return 1; fi
  if [ -d "$(gtun_idir "$name")" ]; then
    echo "Tunnel '$name' already exists. Delete it first."
    return 1
  fi
  mkdir -p "$(gtun_idir "$name")"
  gtun_meta_set "$name" ROLE "entry"

  local link
  read -rp "Paste hy2://... link from Kharej: " link
  if [[ ! "$link" =~ ^hy2:// ]]; then
    echo "Invalid link — must start with hy2://"; rm -rf "$(gtun_idir "$name")"; return 1
  fi

  # Parse link: hy2://AUTH@IP:PORT?sni=...&obfs=gecko&obfs-password=...
  local userinfo hostpart query
  userinfo="${link#hy2://}";    userinfo="${userinfo%%@*}"
  hostpart="${link#*@}";        hostpart="${hostpart%%\?*}"
  query="${link#*\?}";          query="${query%%#*}"

  local server_ip link_port auth obfs sni mport
  auth="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$userinfo")"
  server_ip="${hostpart%%:*}"
  link_port="${hostpart##*:}"

  # Extract from query string
  sni="$(echo "$query"   | tr '&' '\n' | grep '^sni='          | head -1 | cut -d= -f2-)"
  obfs="$(echo "$query"  | tr '&' '\n' | grep '^obfs-password=' | head -1 | cut -d= -f2-)"
  mport="$(echo "$query" | tr '&' '\n' | grep '^mport='         | head -1 | cut -d= -f2-)"
  sni="$(python3   -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "${sni:-www.google.com}")"
  obfs="$(python3  -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "${obfs:-}")"

  local effective_port
  effective_port="${mport:-$link_port}"

  local ports UP DOWN
  echo "Ports to forward from this server (comma-separated, e.g. 443,8080,2087):"
  read -rp "Ports: " ports
  [ -n "$ports" ] || { echo "At least one port required."; rm -rf "$(gtun_idir "$name")"; return 1; }
  read -rp "Upload mbps [100]: "   UP;   UP="${UP:-100}"
  read -rp "Download mbps [100]: " DOWN; DOWN="${DOWN:-100}"
  if [[ "$effective_port" == *-* ]]; then
    local hi; read -rp "Port hop interval [30s]: " hi
    gtun_meta_set "$name" HOP_INTERVAL "${hi:-30s}"
  fi

  gtun_meta_set "$name" REMOTE_IP "$server_ip"
  gtun_meta_set "$name" PORT      "$effective_port"
  gtun_meta_set "$name" AUTH      "$auth"
  gtun_meta_set "$name" OBFS      "$obfs"
  gtun_meta_set "$name" SNI       "$sni"
  gtun_meta_set "$name" PORTS     "$ports"
  gtun_meta_set "$name" UP        "$UP"
  gtun_meta_set "$name" DOWN      "$DOWN"

  gtun_write_entry_config "$name"
  gtun_write_run_script   "$name" "entry"

  # Open user ports in firewall
  local p
  IFS=',' read -ra parr <<< "$ports"
  for p in "${parr[@]}"; do
    p="$(echo "$p" | tr -d ' ')"
    [ -n "$p" ] || continue
    command -v ufw >/dev/null 2>&1 && ufw allow "${p}/udp" >/dev/null 2>&1 || true
    command -v ufw >/dev/null 2>&1 && ufw allow "${p}/tcp" >/dev/null 2>&1 || true
  done

  gtun_start "$name" || { rm -rf "$(gtun_idir "$name")"; return 1; }

  echo
  echo "======================================================="
  echo " GECKO Relay Tunnel '$name' is LIVE on Iran."
  echo "======================================================="
  echo " Exit (Kharej)  : ${server_ip}:${effective_port}"
  echo " Forwarded ports: ${ports}"
  echo "======================================================="
  echo "Point your clients at THIS server's IP on those ports."
}

# ---- List / Status / Delete / Restart ----

gtun_list() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnels"
  echo "======================================================="
  local any=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    any=1
    local role state remote ports
    role="$(gtun_meta_get "$name" ROLE)"
    state="$(gtun_svc_state "$name")"
    remote="$(gtun_meta_get "$name" REMOTE_IP)"
    ports="$(gtun_meta_get "$name" PORTS)"
    local port; port="$(gtun_meta_get "$name" PORT)"
    if [ "$role" = "exit" ]; then
      echo "  * $name  [exit]  listen :${port}  [$state]"
    else
      echo "  * $name  [entry] -> ${remote}:${port}  ports:${ports}  [$state]"
    fi
  done < <(gtun_instances)
  [ "$any" -eq 0 ] && echo "  No GECKO relay tunnels configured."
  echo "======================================================="
}

gtun_pick() {
  local names=() name i=1
  while IFS= read -r name; do [ -n "$name" ] && names+=("$name"); done < <(gtun_instances)
  if [ "${#names[@]}" -eq 0 ]; then echo "No tunnels found."; return 1; fi
  echo "Choose a tunnel:"
  for name in "${names[@]}"; do
    local role state
    role="$(gtun_meta_get "$name" ROLE)"
    state="$(gtun_svc_state "$name")"
    echo "  $i) $name  [$role] [$state]"
    i=$((i+1))
  done
  local pick
  read -rp "Number: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#names[@]}" ]; then
    echo "Invalid choice."; return 1
  fi
  GTUN_PICKED="${names[$((pick-1))]}"
}

gtun_show_status() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Status"
  echo "======================================================="
  gtun_pick || return 1
  local name="$GTUN_PICKED"
  echo
  systemctl status "$(gtun_svc "$name")" --no-pager | head -18
  echo
  echo "--- Last 20 log lines ---"
  journalctl -u "$(gtun_svc "$name")" -n 20 --no-pager
  echo
  # Show link if exit
  if [ "$(gtun_meta_get "$name" ROLE)" = "exit" ]; then
    local lf="$(gtun_idir "$name")/link.txt"
    if [ -f "$lf" ]; then
      echo "--- Share link ---"
      cat "$lf"
      echo
    fi
  fi
}

gtun_restart_one() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Restart"
  echo "======================================================="
  gtun_pick || return 1
  gtun_start "$GTUN_PICKED"
}

gtun_restart_all() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Restart ALL"
  echo "======================================================="
  local name any=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    any=1
    systemctl restart "$(gtun_svc "$name")" 2>/dev/null && echo "Restarted: $name" || echo "Failed: $name"
  done < <(gtun_instances)
  [ "$any" -eq 0 ] && echo "No tunnels to restart."
}

gtun_show_link() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Show Link"
  echo "======================================================="
  gtun_pick || return 1
  local name="$GTUN_PICKED"
  if [ "$(gtun_meta_get "$name" ROLE)" != "exit" ]; then
    echo "Link is only available on EXIT (Kharej) tunnels."; return 1
  fi
  # Regenerate fresh (IP might have changed)
  local SERVER_IP
  SERVER_IP="$(curl -4fsSL --max-time 6 https://api.ipify.org 2>/dev/null \
             || curl -4fsSL --max-time 6 https://ifconfig.me 2>/dev/null \
             || hostname -I | awk '{print $1}')"
  gtun_meta_set "$name" SERVER_IP "$SERVER_IP"
  local link; link="$(gtun_make_link "$name")"
  echo "$link" > "$(gtun_idir "$name")/link.txt"
  echo
  echo "$link"
  echo
  echo "(Saved to: $(gtun_idir "$name")/link.txt)"
}

gtun_delete_one() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Delete"
  echo "======================================================="
  gtun_pick || return 1
  local name="$GTUN_PICKED"
  read -rp "Delete tunnel '$name'? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  systemctl disable --now "$(gtun_svc "$name")" >/dev/null 2>&1 || true
  rm -rf "$(gtun_idir "$name")"
  systemctl daemon-reload
  echo "Tunnel '$name' deleted."
}

gtun_uninstall_all() {
  clear
  echo "======================================================="
  echo " GECKO Relay Tunnel — Uninstall ALL"
  echo "======================================================="
  local names=() name
  while IFS= read -r name; do [ -n "$name" ] && names+=("$name"); done < <(gtun_instances)
  if [ "${#names[@]}" -eq 0 ]; then echo "No tunnels to remove."; return 0; fi
  read -rp "Remove ALL GECKO relay tunnels? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  for name in "${names[@]}"; do
    systemctl disable --now "$(gtun_svc "$name")" >/dev/null 2>&1 || true
    rm -rf "$(gtun_idir "$name")"
    echo "Removed: $name"
  done
  rm -f "$GTUN_SVC_TEMPLATE"
  rm -rf "$GTUN_TLS_DIR"
  systemctl daemon-reload
  echo "All GECKO relay tunnels removed."
}

# ---- Main menu for this section ----

gecko_relay_tunnel_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " GECKO Relay Tunnel Menu"
    echo "======================================================="
    echo " Hysteria2 + Gecko obfs tunnel: Iran <-> Kharej"
    echo " Iran entry forwards user ports to the Kharej exit."
    echo "======================================================="
    echo " 1) Kharej: Install new exit tunnel + get link"
    echo " 2) Iran:   Connect from Kharej link"
    echo " 3) List tunnels"
    echo " 4) Status / logs"
    echo " 5) Show / regenerate Kharej link"
    echo " 6) Restart one tunnel"
    echo " 7) Restart ALL tunnels"
    echo " 8) Delete a tunnel"
    echo " 9) Uninstall ALL tunnels"
    echo " 0) Back"
    echo "======================================================="
    read -rp "Choose: " GTUN_CHOICE
    case "$GTUN_CHOICE" in
      1) gtun_setup_kharej;    read -rp "Press Enter to continue..." ;;
      2) gtun_setup_iran;      read -rp "Press Enter to continue..." ;;
      3) gtun_list;            read -rp "Press Enter to continue..." ;;
      4) gtun_show_status;     read -rp "Press Enter to continue..." ;;
      5) gtun_show_link;       read -rp "Press Enter to continue..." ;;
      6) gtun_restart_one;     read -rp "Press Enter to continue..." ;;
      7) gtun_restart_all;     read -rp "Press Enter to continue..." ;;
      8) gtun_delete_one;      read -rp "Press Enter to continue..." ;;
      9) gtun_uninstall_all;   read -rp "Press Enter to continue..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
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


# =======================================================
# =======================================================
# Xboard ISP Dedicated Proxies - Panel Outbound Routing
# Uses outbound generated by Xboard panel.
# No SOCKS credentials are requested or written by this script.
# No separate domain list is created or edited.
# =======================================================

XBOARD_SOCKS_TAG="ISP Dedicated Proxies"
XBOARD_SOCKS_BACKUP_DIR="/root/xboard-isp-socks-backups"
XBOARD_SOCKS_STATE_FILE="/etc/xboard-isp-socks.env"

xboard_socks_ok()   { echo -e "\e[32m[OK]\e[0m $1"; }
xboard_socks_err()  { echo -e "\e[31m[ERR]\e[0m $1"; }
xboard_socks_info() { echo -e "\e[34m[*]\e[0m $1"; }
xboard_socks_warn() { echo -e "\e[33m[!]\e[0m $1"; }

xboard_socks_require_root() {
  [ "$(id -u)" -eq 0 ] || { xboard_socks_err "Please run as root."; return 1; }
}

xboard_socks_shell_quote() {
  python3 -c 'import sys,shlex; print(shlex.quote(sys.argv[1]))' "$1"
}

xboard_socks_load_state() {
  [ -f "$XBOARD_SOCKS_STATE_FILE" ] && . "$XBOARD_SOCKS_STATE_FILE" 2>/dev/null || true
}

xboard_socks_save_state() {
  mkdir -p "$(dirname "$XBOARD_SOCKS_STATE_FILE")"
  {
    echo "XBOARD_SOCKS_CONFIG=$(xboard_socks_shell_quote "${XBOARD_SOCKS_CONFIG:-}")"
    echo "XBOARD_SOCKS_SERVICE=$(xboard_socks_shell_quote "${XBOARD_SOCKS_SERVICE:-}")"
  } > "$XBOARD_SOCKS_STATE_FILE"
  chmod 600 "$XBOARD_SOCKS_STATE_FILE" 2>/dev/null || true
}

xboard_socks_json_looks_like_xray() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -q '"outbounds"' "$f" 2>/dev/null && grep -q '"routing"' "$f" 2>/dev/null
}

xboard_socks_detect_config() {
  xboard_socks_load_state
  if [ -n "${XBOARD_SOCKS_CONFIG:-}" ] && xboard_socks_json_looks_like_xray "$XBOARD_SOCKS_CONFIG"; then
    return 0
  fi

  XBOARD_SOCKS_CONFIG=""
  local candidates=(
    "/usr/local/etc/xray/config.json"
    "/etc/xray/config.json"
    "/usr/local/xray/config.json"
    "/opt/xray/config.json"
    "/etc/XrayR/config.json"
    "/etc/xrayr/config.json"
    "/etc/Xboard-Node/config.json"
    "/etc/xboard-node/config.json"
    "/opt/Xboard-Node/config.json"
    "/opt/xboard-node/config.json"
  )
  local f
  for f in "${candidates[@]}"; do
    if xboard_socks_json_looks_like_xray "$f"; then
      XBOARD_SOCKS_CONFIG="$f"
      return 0
    fi
  done

  while IFS= read -r f; do
    if xboard_socks_json_looks_like_xray "$f"; then
      XBOARD_SOCKS_CONFIG="$f"
      return 0
    fi
  done < <(find /etc /usr/local/etc /opt -maxdepth 5 -type f -name '*.json' 2>/dev/null | head -200)

  return 1
}

xboard_socks_detect_service() {
  xboard_socks_load_state
  if [ -n "${XBOARD_SOCKS_SERVICE:-}" ] && systemctl list-unit-files 2>/dev/null | grep -q "^${XBOARD_SOCKS_SERVICE}\.service"; then
    return 0
  fi

  XBOARD_SOCKS_SERVICE=""
  local unit svc
  local candidate_units=(
    "xray.service"
    "XrayR.service"
    "xrayr.service"
    "xboard-node.service"
    "Xboard-Node.service"
    "xboard.service"
  )

  for unit in "${candidate_units[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
      svc="${unit%.service}"
      if [ -n "${XBOARD_SOCKS_CONFIG:-}" ] && systemctl cat "$svc" 2>/dev/null | grep -Fq "$XBOARD_SOCKS_CONFIG"; then
        XBOARD_SOCKS_SERVICE="$svc"
        return 0
      fi
    fi
  done

  for unit in "${candidate_units[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
      XBOARD_SOCKS_SERVICE="${unit%.service}"
      return 0
    fi
  done

  return 1
}

xboard_socks_pick_config_and_service() {
  xboard_socks_detect_config || true
  xboard_socks_detect_service || true

  echo
  if [ -n "${XBOARD_SOCKS_CONFIG:-}" ]; then
    xboard_socks_info "Detected Xray/Xboard config: $XBOARD_SOCKS_CONFIG"
  else
    xboard_socks_warn "Could not auto-detect Xray/Xboard config."
  fi

  read -rp "Xray/Xboard config path [${XBOARD_SOCKS_CONFIG:-manual required}]: " input_cfg
  input_cfg="${input_cfg:-${XBOARD_SOCKS_CONFIG:-}}"
  if [ -z "$input_cfg" ] || [ ! -f "$input_cfg" ]; then
    xboard_socks_err "Config file not found."
    return 1
  fi
  if ! xboard_socks_json_looks_like_xray "$input_cfg"; then
    xboard_socks_warn "This file does not clearly look like a final Xray JSON config with outbounds and routing."
    read -rp "Continue anyway? [y/N]: " cont
    case "$cont" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 1 ;; esac
  fi
  XBOARD_SOCKS_CONFIG="$input_cfg"

  xboard_socks_detect_service || true
  if [ -n "${XBOARD_SOCKS_SERVICE:-}" ]; then
    xboard_socks_info "Detected service: $XBOARD_SOCKS_SERVICE"
  else
    xboard_socks_warn "Could not auto-detect service."
  fi
  read -rp "Service name to restart [${XBOARD_SOCKS_SERVICE:-skip}]: " input_svc
  input_svc="${input_svc:-${XBOARD_SOCKS_SERVICE:-}}"
  XBOARD_SOCKS_SERVICE="$input_svc"

  xboard_socks_save_state
  return 0
}

xboard_socks_extract_existing_proxy_env() {
  local cfg="$1"
  python3 - "$cfg" "$XBOARD_SOCKS_TAG" <<'PY'
import sys, json, shlex
from pathlib import Path
cfg, tag = sys.argv[1], sys.argv[2]
text = Path(cfg).read_text(encoding='utf-8', errors='ignore')

def strip_comments(s):
    out=[]; i=0; n=len(s); in_str=False; esc=False
    while i<n:
        c=s[i]
        if in_str:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': in_str=False
            i+=1; continue
        if c=='"': in_str=True; out.append(c); i+=1; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            i+=2
            while i<n and s[i] not in '\r\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'):
                i+=1
            i+=2
            continue
        out.append(c); i+=1
    return ''.join(out)

data = json.loads(strip_comments(text))
for ob in data.get('outbounds', []) or []:
    if isinstance(ob, dict) and ob.get('tag') == tag:
        servers = ((ob.get('settings') or {}).get('servers') or [])
        if servers:
            s = servers[0]
            users = s.get('users') or []
            u = users[0] if users else {}
            print('XBOARD_SOCKS_HOST=' + shlex.quote(str(s.get('address',''))))
            print('XBOARD_SOCKS_PORT=' + shlex.quote(str(s.get('port',''))))
            print('XBOARD_SOCKS_USER=' + shlex.quote(str(u.get('user',''))))
            print('XBOARD_SOCKS_PASS=' + shlex.quote(str(u.get('pass',''))))
            raise SystemExit(0)
raise SystemExit(1)
PY
}

xboard_socks_backup_config() {
  local cfg="$1"
  mkdir -p "$XBOARD_SOCKS_BACKUP_DIR"
  local base ts backup
  base="$(basename "$cfg")"
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="$XBOARD_SOCKS_BACKUP_DIR/${base}.bak-${ts}"
  cp -a "$cfg" "$backup" || return 1
  chmod 600 "$backup" 2>/dev/null || true
  echo "$backup"
}

xboard_socks_find_xray_bin() {
  if command -v xray >/dev/null 2>&1; then command -v xray; return 0; fi
  for b in /usr/local/bin/xray /usr/bin/xray /opt/xray/xray; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

xboard_socks_test_xray_config() {
  local cfg="$1"
  local xb
  xb="$(xboard_socks_find_xray_bin 2>/dev/null || true)"
  if [ -z "$xb" ]; then
    xboard_socks_warn "xray binary not found. Skipping config test."
    return 0
  fi
  xboard_socks_info "Testing Xray config..."
  "$xb" test -config "$cfg"
}

xboard_socks_restart_service() {
  local svc="${XBOARD_SOCKS_SERVICE:-}"
  if [ -z "$svc" ]; then
    xboard_socks_warn "No service selected. Restart skipped."
    return 0
  fi
  xboard_socks_info "Restarting service: $svc"
  systemctl restart "$svc"
  sleep 1
  systemctl status "$svc" --no-pager | head -20 || true
}

xboard_socks_apply_routing_patch() {
  local cfg="$1"
  python3 - "$cfg" "$XBOARD_SOCKS_TAG" <<'PY'
import sys, json, os
from pathlib import Path
cfg_path, tag = sys.argv[1:3]
p = Path(cfg_path)
text = p.read_text(encoding='utf-8', errors='ignore')

def strip_comments(s):
    out=[]; i=0; n=len(s); in_str=False; esc=False
    while i<n:
        c=s[i]
        if in_str:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': in_str=False
            i+=1; continue
        if c=='"': in_str=True; out.append(c); i+=1; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            i+=2
            while i<n and s[i] not in '\r\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'):
                i+=1
            i+=2
            continue
        out.append(c); i+=1
    return ''.join(out)

def ordered_unique(items):
    seen=set(); out=[]
    for x in items:
        if not isinstance(x, str):
            continue
        x=x.strip()
        if not x or x in seen:
            continue
        seen.add(x); out.append(x)
    return out

data = json.loads(strip_comments(text))
if not isinstance(data, dict):
    raise SystemExit('Top-level JSON must be an object.')

outbounds = data.get('outbounds')
if not isinstance(outbounds, list):
    raise SystemExit('No outbounds list found in final Xray config.')

panel_outbound = None
for ob in outbounds:
    if isinstance(ob, dict) and ob.get('tag') == tag:
        panel_outbound = ob
        break
if panel_outbound is None:
    raise SystemExit(f'Panel outbound with tag "{tag}" was not found. Add it in Xboard panel first, then sync/restart the node.')

routing = data.get('routing')
if not isinstance(routing, dict):
    routing = {}
rules = routing.get('rules')
if not isinstance(rules, list):
    rules = []

skip_tags = {'block', 'blocked', 'blackhole'}
domains = []
for r in rules:
    if not isinstance(r, dict):
        continue
    if r.get('outboundTag') == tag:
        continue
    outbound_tag = str(r.get('outboundTag', '')).lower()
    if outbound_tag in skip_tags:
        continue
    d = r.get('domain')
    if isinstance(d, list):
        domains.extend(d)
    elif isinstance(d, str):
        domains.append(d)
domains = ordered_unique(domains)
if not domains:
    raise SystemExit('No domain rules found in routing.rules. Xboard site/domain rules must exist in the final Xray config first.')

rules = [r for r in rules if not (isinstance(r, dict) and r.get('outboundTag') == tag)]
managed_rule = {
    'type': 'field',
    'domain': domains,
    'outboundTag': tag,
}
rules.insert(0, managed_rule)
routing['rules'] = rules
data['routing'] = routing
# Important: do not edit outbounds. The panel owns the SOCKS outbound.

tmp = p.with_name(p.name + '.tmp-xboard-isp-socks-routing')
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
os.replace(tmp, p)
print(f'Using panel outbound tag: {tag}')
print(f'Routed domain entries: {len(domains)}')
PY
}

xboard_socks_remove_routing_patch() {
  local cfg="$1"
  python3 - "$cfg" "$XBOARD_SOCKS_TAG" <<'PY'
import sys, json, os
from pathlib import Path
cfg_path, tag = sys.argv[1], sys.argv[2]
p = Path(cfg_path)
text = p.read_text(encoding='utf-8', errors='ignore')

def strip_comments(s):
    out=[]; i=0; n=len(s); in_str=False; esc=False
    while i<n:
        c=s[i]
        if in_str:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': in_str=False
            i+=1; continue
        if c=='"': in_str=True; out.append(c); i+=1; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            i+=2
            while i<n and s[i] not in '\r\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'):
                i+=1
            i+=2
            continue
        out.append(c); i+=1
    return ''.join(out)

data = json.loads(strip_comments(text))
removed_rules = 0
routing = data.get('routing')
if isinstance(routing, dict) and isinstance(routing.get('rules'), list):
    old = routing['rules']
    routing['rules'] = [r for r in old if not (isinstance(r, dict) and r.get('outboundTag') == tag)]
    removed_rules = len(old) - len(routing['rules'])

# Important: do not remove the outbound. It is managed by Xboard panel.
tmp = p.with_name(p.name + '.tmp-xboard-isp-socks-disable')
tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
os.replace(tmp, p)
print(f'Removed routing rules: {removed_rules}')
print('Panel outbound was left unchanged.')
PY
}

enable_xboard_socks_routing() {
  clear
  echo "======================================================="
  echo " Apply Xboard Sites Routing to Panel SOCKS Outbound"
  echo "======================================================="
  echo "This option does NOT ask for SOCKS user/pass/host/port."
  echo "The SOCKS outbound must already come from Xboard panel."
  echo "Required outbound tag: $XBOARD_SOCKS_TAG"
  echo "Domain source: existing Xboard/Xray routing.rules[].domain"
  echo "======================================================="
  xboard_socks_require_root || return 1
  command -v python3 >/dev/null 2>&1 || { xboard_socks_err "python3 is required."; return 1; }
  xboard_socks_pick_config_and_service || return 1

  if ! xboard_socks_extract_existing_proxy_env "$XBOARD_SOCKS_CONFIG" >/tmp/xboard_isp_socks_existing.env 2>/dev/null; then
    xboard_socks_err "Panel outbound not found in final config."
    echo "Add this outbound in Xboard panel first, then sync/restart node:"
    echo "  tag: $XBOARD_SOCKS_TAG"
    rm -f /tmp/xboard_isp_socks_existing.env
    return 1
  fi
  . /tmp/xboard_isp_socks_existing.env
  rm -f /tmp/xboard_isp_socks_existing.env

  echo
  echo "Panel outbound found: $XBOARD_SOCKS_TAG"
  echo "SOCKS target        : ${XBOARD_SOCKS_HOST:-unknown}:${XBOARD_SOCKS_PORT:-unknown}"
  [ -n "${XBOARD_SOCKS_USER:-}" ] && echo "SOCKS auth          : enabled" || echo "SOCKS auth          : disabled"
  echo
  read -rp "Apply routing changes now? [Y/n]: " apply_confirm
  apply_confirm="${apply_confirm:-Y}"
  case "$apply_confirm" in n|N|no|NO|No) echo "Cancelled."; return 0 ;; esac

  local backup
  backup="$(xboard_socks_backup_config "$XBOARD_SOCKS_CONFIG")" || { xboard_socks_err "Backup failed."; return 1; }
  xboard_socks_info "Backup saved: $backup"

  if ! xboard_socks_apply_routing_patch "$XBOARD_SOCKS_CONFIG"; then
    xboard_socks_err "Routing patch failed. Restoring backup."
    cp -a "$backup" "$XBOARD_SOCKS_CONFIG"
    return 1
  fi

  if ! xboard_socks_test_xray_config "$XBOARD_SOCKS_CONFIG"; then
    xboard_socks_err "Config test failed. Restoring backup."
    cp -a "$backup" "$XBOARD_SOCKS_CONFIG"
    xboard_socks_test_xray_config "$XBOARD_SOCKS_CONFIG" || true
    return 1
  fi

  xboard_socks_restart_service || xboard_socks_warn "Service restart failed. Check logs manually."

  echo
  xboard_socks_ok "Xboard domain traffic is now routed via panel outbound '$XBOARD_SOCKS_TAG'."
  echo "Config : $XBOARD_SOCKS_CONFIG"
  echo "Backup : $backup"
  echo "Note   : If Xboard regenerates this config later, run this option again after node sync."
}

disable_xboard_socks_routing() {
  clear
  echo "======================================================="
  echo " Disable Xboard ISP Dedicated SOCKS Routing"
  echo "======================================================="
  echo "Only routing rules using '$XBOARD_SOCKS_TAG' will be removed."
  echo "The panel outbound will NOT be deleted."
  echo "======================================================="
  xboard_socks_require_root || return 1
  command -v python3 >/dev/null 2>&1 || { xboard_socks_err "python3 is required."; return 1; }
  xboard_socks_pick_config_and_service || return 1

  local backup
  backup="$(xboard_socks_backup_config "$XBOARD_SOCKS_CONFIG")" || { xboard_socks_err "Backup failed."; return 1; }
  xboard_socks_info "Backup saved: $backup"

  if ! xboard_socks_remove_routing_patch "$XBOARD_SOCKS_CONFIG"; then
    xboard_socks_err "Disable patch failed. Restoring backup."
    cp -a "$backup" "$XBOARD_SOCKS_CONFIG"
    return 1
  fi

  if ! xboard_socks_test_xray_config "$XBOARD_SOCKS_CONFIG"; then
    xboard_socks_err "Config test failed. Restoring backup."
    cp -a "$backup" "$XBOARD_SOCKS_CONFIG"
    return 1
  fi

  xboard_socks_restart_service || xboard_socks_warn "Service restart failed. Check logs manually."
  echo
  xboard_socks_ok "Removed routing rules for '$XBOARD_SOCKS_TAG'. Panel outbound was kept."
  echo "Backup: $backup"
}

show_xboard_socks_status() {
  clear
  echo "======================================================="
  echo " Xboard ISP Dedicated SOCKS Routing Status"
  echo "======================================================="
  xboard_socks_detect_config || true
  xboard_socks_detect_service || true
  echo "Config : ${XBOARD_SOCKS_CONFIG:-not detected}"
  echo "Service: ${XBOARD_SOCKS_SERVICE:-not detected}"
  echo "Tag    : $XBOARD_SOCKS_TAG"
  echo
  if [ -z "${XBOARD_SOCKS_CONFIG:-}" ] || [ ! -f "$XBOARD_SOCKS_CONFIG" ]; then
    xboard_socks_err "No config detected."
    return 1
  fi

  python3 - "$XBOARD_SOCKS_CONFIG" "$XBOARD_SOCKS_TAG" <<'PY'
import sys, json
from pathlib import Path
cfg, tag = sys.argv[1], sys.argv[2]
text = Path(cfg).read_text(encoding='utf-8', errors='ignore')

def strip_comments(s):
    out=[]; i=0; n=len(s); in_str=False; esc=False
    while i<n:
        c=s[i]
        if in_str:
            out.append(c)
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': in_str=False
            i+=1; continue
        if c=='"': in_str=True; out.append(c); i+=1; continue
        if c=='/' and i+1<n and s[i+1]=='/':
            i+=2
            while i<n and s[i] not in '\r\n': i+=1
            continue
        if c=='/' and i+1<n and s[i+1]=='*':
            i+=2
            while i+1<n and not (s[i]=='*' and s[i+1]=='/'):
                i+=1
            i+=2
            continue
        out.append(c); i+=1
    return ''.join(out)

data = json.loads(strip_comments(text))
outbounds = data.get('outbounds') or []
rules = (data.get('routing') or {}).get('rules') or []
matched_outbounds = [o for o in outbounds if isinstance(o, dict) and o.get('tag') == tag]
matched_rules = [r for r in rules if isinstance(r, dict) and r.get('outboundTag') == tag]
print('Panel outbound   :', 'YES' if matched_outbounds else 'NO')
print('Routing rules    :', len(matched_rules))
if matched_outbounds:
    ob = matched_outbounds[0]
    print('Protocol         :', ob.get('protocol', ''))
    s = (((ob.get('settings') or {}).get('servers') or [{}])[0])
    host = s.get('address', '')
    port = s.get('port', '')
    users = s.get('users') or []
    auth = 'enabled' if users else 'disabled'
    print('SOCKS target     :', f'{host}:{port}')
    print('SOCKS auth       :', auth)
if matched_rules:
    domains = matched_rules[0].get('domain') or []
    print('Domain entries   :', len(domains))
    for d in domains[:25]:
        print('  -', d)
    if len(domains) > 25:
        print(f'  ... and {len(domains)-25} more')
PY
  echo
  if [ -n "${XBOARD_SOCKS_SERVICE:-}" ]; then
    systemctl status "$XBOARD_SOCKS_SERVICE" --no-pager 2>/dev/null | head -20 || true
  fi
}

test_xboard_socks_proxy() {
  clear
  echo "======================================================="
  echo " Test ISP Dedicated SOCKS Proxy from Panel Outbound"
  echo "======================================================="
  local host port user pass
  xboard_socks_detect_config || true
  if [ -n "${XBOARD_SOCKS_CONFIG:-}" ] && [ -f "$XBOARD_SOCKS_CONFIG" ]; then
    if xboard_socks_extract_existing_proxy_env "$XBOARD_SOCKS_CONFIG" >/tmp/xboard_isp_socks_existing.env 2>/dev/null; then
      . /tmp/xboard_isp_socks_existing.env
      host="$XBOARD_SOCKS_HOST"; port="$XBOARD_SOCKS_PORT"; user="$XBOARD_SOCKS_USER"; pass="$XBOARD_SOCKS_PASS"
    fi
    rm -f /tmp/xboard_isp_socks_existing.env
  fi

  if [ -z "$host" ] || [ -z "$port" ]; then
    xboard_socks_err "No panel outbound found with tag '$XBOARD_SOCKS_TAG'."
    echo "Add the SOCKS outbound in Xboard panel first, then sync/restart the node."
    return 1
  fi

  echo
  echo "Testing SOCKS target: $host:$port"
  [ -n "$user" ] && echo "Auth: enabled" || echo "Auth: disabled"
  echo

  if ! command -v curl >/dev/null 2>&1; then
    xboard_socks_err "curl is not installed."
    return 1
  fi

  local curl_args=(--socks5-hostname "$host:$port" --max-time 15 -fsSL)
  if [ -n "$user" ] || [ -n "$pass" ]; then
    curl_args=(--socks5-hostname "$host:$port" --proxy-user "$user:$pass" --max-time 15 -fsSL)
  fi

  echo "Cloudflare trace via SOCKS:"
  if curl "${curl_args[@]}" https://www.cloudflare.com/cdn-cgi/trace 2>/tmp/xboard_isp_socks_curl.err | grep -E '^(ip|colo|warp)='; then
    xboard_socks_ok "SOCKS proxy test succeeded."
  else
    xboard_socks_err "SOCKS proxy test failed."
    [ -s /tmp/xboard_isp_socks_curl.err ] && cat /tmp/xboard_isp_socks_curl.err
    rm -f /tmp/xboard_isp_socks_curl.err
    return 1
  fi
  rm -f /tmp/xboard_isp_socks_curl.err
}

xboard_socks_routing_menu() {
  while true; do
    clear
    echo "======================================================="
    echo " Xboard ISP Dedicated Proxies Routing Menu"
    echo "======================================================="
    echo "Purpose: Xboard domains/sites -> panel SOCKS outbound -> Internet"
    echo "Domain source: existing Xboard/Xray routing.rules[].domain"
    echo "Outbound source: Xboard panel custom outbound"
    echo "Outbound tag   : $XBOARD_SOCKS_TAG"
    echo
    echo " 1) Apply routing to existing panel outbound"
    echo " 2) Remove routing rule only"
    echo " 3) Show Xboard ISP SOCKS routing status"
    echo " 4) Test panel SOCKS outbound"
    echo " 0) Back"
    echo "======================================================="
    read -rp "Choose: " XBOARD_SOCKS_CHOICE
    case "$XBOARD_SOCKS_CHOICE" in
      1) enable_xboard_socks_routing; read -rp "Press Enter to return to menu..." ;;
      2) disable_xboard_socks_routing; read -rp "Press Enter to return to menu..." ;;
      3) show_xboard_socks_status; read -rp "Press Enter to return to menu..." ;;
      4) test_xboard_socks_proxy; read -rp "Press Enter to return to menu..." ;;
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
  echo -e "5)  \e[96mHysteria2 Gecko Port Hop Menu (Kharej only)\e[0m"
  echo -e "6)  \e[93mGECKO WARP Proxy Outbound Menu\e[0m"
  echo -e "7)  \e[96mGECKO Relay Tunnel Menu (Iran <-> Kharej)\e[0m"
  echo -e "8)  \e[93mGOST Multi-Tunnel Menu\e[0m"
  echo -e "9)  \e[91mCSF Firewall Menu\e[0m"
  echo -e "10) \e[96mXboard ISP Dedicated Proxies Routing Menu\e[0m"
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
    hysteria2_gecko_porthop_menu
    ;;
  6)
    clear
    gecko_warp_proxy_menu
    ;;
  7)
    clear
    gecko_relay_tunnel_menu
    ;;
  8)
    clear
    gost_multi_menu
    ;;
  9)
    clear
    csf_menu
    ;;
  10)
    clear
    xboard_socks_routing_menu
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
