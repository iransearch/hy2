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
  HYSTERIA_URL_AMD64="https://github.com/apernet/hysteria/releases/download/app%2Fv2.9.2/hysteria-linux-amd64"

  echo "======================================================="
  echo " Hysteria2 v2.9.2 + Gecko Obfuscation Installer"
  echo "======================================================="

  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    return 1
  fi

  ARCH="$(uname -m)"
  if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    echo "This custom build uses the requested linux-amd64 binary only. Current arch: $ARCH"
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

  echo "Downloading Hysteria v2.9.2 linux-amd64..."
  TMP_BIN="$(mktemp /tmp/hysteria-v292.XXXXXX)"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP_BIN" "$HYSTERIA_URL_AMD64"; then
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
