#!/usr/bin/env bash
set -euo pipefail

HYSTERIA_VERSION="v2.9.2"
HYSTERIA_BIN="/usr/local/bin/hysteria"
HYSTERIA_DIR="/etc/hysteria2"
HYSTERIA_CONFIG="$HYSTERIA_DIR/server.yaml"
HYSTERIA_SERVICE="/etc/systemd/system/hysteria2-gecko.service"

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

root_check() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
  fi
}

install_deps() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl openssl python3 ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl openssl python3 ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl openssl python3 ca-certificates
  else
    echo "Unsupported package manager. Install curl openssl python3 manually."
    exit 1
  fi
}

urlencode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

install_hysteria2_gecko_v292() {
  echo "======================================================="
  echo " Hysteria2 ${HYSTERIA_VERSION} + Gecko Obfuscation Installer"
  echo "======================================================="

  root_check
  install_deps

  HY2_ARCH="$(detect_hysteria_arch)"
  if [ "$HY2_ARCH" = "unsupported" ]; then
    echo "Unsupported architecture: $(uname -m)"
    exit 1
  fi

  HYSTERIA_RELEASE="app%2F${HYSTERIA_VERSION}"
  HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_RELEASE}/hysteria-linux-${HY2_ARCH}"

  read -rp "Port [2020]: " HY2_PORT
  HY2_PORT="${HY2_PORT:-2020}"

  if ! [[ "$HY2_PORT" =~ ^[0-9]+$ ]] || [ "$HY2_PORT" -lt 1 ] || [ "$HY2_PORT" -gt 65535 ]; then
    echo "Invalid port."
    exit 1
  fi

  DEFAULT_AUTH="$(openssl rand -hex 16)"
  read -rp "Auth password [$DEFAULT_AUTH]: " HY2_AUTH
  HY2_AUTH="${HY2_AUTH:-$DEFAULT_AUTH}"

  DEFAULT_OBFS="$(openssl rand -base64 18 | tr -d '=+/')"
  read -rp "Gecko obfs password [$DEFAULT_OBFS]: " HY2_OBFS
  HY2_OBFS="${HY2_OBFS:-$DEFAULT_OBFS}"

  read -rp "SNI / certificate CN [www.google.com]: " HY2_SNI
  HY2_SNI="${HY2_SNI:-www.google.com}"

  read -rp "Remark [HY2-GECKO]: " HY2_REMARK
  HY2_REMARK="${HY2_REMARK:-HY2-GECKO}"

  echo
  echo "Masquerade mode:"
  echo " 1) Disable / default 404"
  echo " 2) Static file website"
  echo " 3) Reverse proxy to a website"
  echo " 4) Simple string response"
  read -rp "Choose masquerade mode [3]: " MASQ_MODE
  MASQ_MODE="${MASQ_MODE:-3}"

  MASQ_CONFIG=""

  case "$MASQ_MODE" in
    1)
      MASQ_CONFIG=""
      ;;
    2)
      read -rp "Static website directory [/var/www/hysteria2-masq]: " MASQ_DIR
      MASQ_DIR="${MASQ_DIR:-/var/www/hysteria2-masq}"
      mkdir -p "$MASQ_DIR"
      [ -f "$MASQ_DIR/index.html" ] || echo "Welcome" > "$MASQ_DIR/index.html"
      MASQ_CONFIG=$(cat <<EOF
masquerade:
  type: file
  file:
    dir: "$MASQ_DIR"
EOF
)
      ;;
    3)
      read -rp "Proxy target [https://www.bing.com]: " MASQ_PROXY
      MASQ_PROXY="${MASQ_PROXY:-https://www.bing.com}"
      MASQ_CONFIG=$(cat <<EOF
masquerade:
  type: proxy
  proxy:
    url: "$MASQ_PROXY"
    rewriteHost: true
EOF
)
      ;;
    4)
      read -rp "Response string [Hello]: " MASQ_STRING
      MASQ_STRING="${MASQ_STRING:-Hello}"
      MASQ_CONFIG=$(cat <<EOF
masquerade:
  type: string
  string:
    content: "$MASQ_STRING"
    headers:
      content-type: text/plain
    statusCode: 200
EOF
)
      ;;
    *)
      echo "Invalid masquerade mode."
      exit 1
      ;;
  esac

  systemctl stop hysteria2-gecko.service >/dev/null 2>&1 || true
  systemctl stop hysteria-server.service >/dev/null 2>&1 || true
  systemctl stop hysteria.service >/dev/null 2>&1 || true

  if command -v pgrep >/dev/null 2>&1 && pgrep -x hysteria >/dev/null 2>&1; then
    pkill -x hysteria >/dev/null 2>&1 || true
    sleep 1
  fi

  echo "Downloading Hysteria ${HYSTERIA_VERSION} linux-${HY2_ARCH}..."
  TMP_BIN="$(mktemp /tmp/hysteria-v292.XXXXXX)"

  if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP_BIN" "$HYSTERIA_URL"; then
    rm -f "$TMP_BIN"
    echo "Download failed: $HYSTERIA_URL"
    exit 1
  fi

  chmod +x "$TMP_BIN"
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

auth:
  type: password
  password: "$HY2_AUTH"

obfs:
  type: gecko
  gecko:
    password: "$HY2_OBFS"

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false

bandwidth:
  up: 1 gbps
  down: 1 gbps

ignoreClientBandwidth: false

disableUDP: false

$MASQ_CONFIG
EOF

  cat > "$HYSTERIA_SERVICE" <<EOF
[Unit]
Description=Hysteria2 Gecko Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $HYSTERIA_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now hysteria2-gecko.service

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "$HY2_PORT/udp" >/dev/null 2>&1 || true
  fi

  SERVER_IP="$(curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

  EN_AUTH="$(urlencode "$HY2_AUTH")"
  EN_OBFS="$(urlencode "$HY2_OBFS")"
  EN_SNI="$(urlencode "$HY2_SNI")"
  EN_REMARK="$(urlencode "$HY2_REMARK")"

  HY2_LINK="hy2://$EN_AUTH@$SERVER_IP:$HY2_PORT?sni=$EN_SNI&insecure=1&obfs=gecko&obfs-password=$EN_OBFS#$EN_REMARK"

  cat > "$HYSTERIA_DIR/client-link.txt" <<EOF
$HY2_LINK
EOF

  echo
  echo "======================================================="
  echo " Installed successfully."
  echo " Architecture: linux-${HY2_ARCH}"
  echo " Config: $HYSTERIA_CONFIG"
  echo " Service: hysteria2-gecko.service"
  echo " Client link:"
  echo "$HY2_LINK"
  echo "======================================================="
}

install_hysteria2_gecko_v292
