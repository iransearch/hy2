#!/bin/bash
################################################################################
# add-gost-tunnel.sh
# Adds a "Gost Tunnel" section (menu option 8) to the Sing-Box/Hysteria2 script.
# Safe: backs up the target first, refuses to double-apply.
#
# Usage:
#   sudo ./add-gost-tunnel.sh /path/to/your/script.sh
# If no path is given it tries common locations.
################################################################################

set -e

TARGET="$1"

# Try to auto-find the script if not provided
if [ -z "$TARGET" ]; then
  for c in ./install.sh ./Source-menu.sh ./menu.sh /root/install.sh /etc/singbox/install.sh; do
    [ -f "$c" ] && TARGET="$c" && break
  done
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "ERROR: Could not find the target script."
  echo "Run:  sudo $0 /full/path/to/your/script.sh"
  exit 1
fi

echo "Target script: $TARGET"

# Refuse to double-apply
if grep -q "gost_tunnel_menu_tcs" "$TARGET"; then
  echo "It looks like Gost Tunnel is already added to this script. Nothing to do."
  exit 0
fi

# Backup
BK="${TARGET}.bak-gost-$(date +%Y%m%d-%H%M%S)"
cp -a "$TARGET" "$BK"
echo "Backup saved: $BK"

# ---- 1) Write the Gost function block to a temp file ----
GOST_TMP="$(mktemp)"
cat > "$GOST_TMP" <<'GOST_BLOCK_EOF'

# =======================================================
# Gost Tunnel - multiple named tunnels, port=port forward
# Each tunnel = its own systemd service: gostm_<name>.service
# Forwarding: this-server:PORT -> destination:PORT (same port)
# Supports TCP / UDP / gRPC, IPv4 and IPv6 destinations.
# =======================================================

GOST_BIN_TCS="/usr/local/bin/gost"
GOST_SVC_PREFIX_TCS="gostm_"
GOST_SVC_DIR_TCS="/etc/systemd/system"

gost_valid_name_tcs() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

gost_ensure_bin_tcs() {
  if [ -x "$GOST_BIN_TCS" ]; then
    return 0
  fi
  echo "gost binary not found at $GOST_BIN_TCS"
  read -rp "Install GOST v3 now? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cannot continue without gost."; return 1 ;; esac

  command -v wget >/dev/null 2>&1 || { apt update -y && apt install -y wget tar curl; }
  echo "Downloading GOST v3..."
  local url="https://github.com/go-gost/gost/releases/download/v3.0.0/gost_3.0.0_linux_amd64.tar.gz"
  wget -qO /tmp/gost.tar.gz "$url" || { echo "Download failed."; return 1; }
  [ -s /tmp/gost.tar.gz ] || { echo "Downloaded file is empty."; return 1; }
  tar -xzf /tmp/gost.tar.gz -C /usr/local/bin/ gost 2>/dev/null || tar -xzf /tmp/gost.tar.gz -C /usr/local/bin/
  chmod +x "$GOST_BIN_TCS"
  rm -f /tmp/gost.tar.gz
  [ -x "$GOST_BIN_TCS" ] && echo "GOST installed." || { echo "Install failed."; return 1; }
}

gost_create_tunnel_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnel: Create New"
  echo "======================================================="
  echo "Forwards this-server:PORT  ->  destination:PORT (same port)."
  echo "======================================================="
  [ "$(id -u)" -eq 0 ] || { echo "Please run as root."; return 1; }
  gost_ensure_bin_tcs || return 1

  read -rp "Tunnel name (letters/numbers/-/_): " name
  if ! gost_valid_name_tcs "$name"; then
    echo "Invalid name. Use only letters, numbers, - and _"; return 1
  fi
  local svc="${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}${name}.service"
  if [ -f "$svc" ]; then
    echo "A tunnel named '$name' already exists. Delete it first or pick another name."
    return 1
  fi

  read -rp "Destination IP (IPv4 or IPv6): " dest
  [ -n "$dest" ] || { echo "Destination required."; return 1; }

  echo "Ports: comma-separated (e.g. 8880,2052,443)"
  read -rp "Ports: " ports
  [ -n "$ports" ] || { echo "At least one port required."; return 1; }

  echo "Protocol:  1) TCP   2) UDP   3) gRPC"
  read -rp "Choice: " p
  case "$p" in
    1) proto="tcp" ;;
    2) proto="udp" ;;
    3) proto="grpc" ;;
    *) echo "Invalid protocol."; return 1 ;;
  esac

  local dest_fmt="$dest"
  if [[ "$dest" == *:* ]]; then dest_fmt="[$dest]"; fi

  local exec_line="ExecStart=${GOST_BIN_TCS}"
  local good=0
  IFS=',' read -ra parr <<< "$ports"
  for raw in "${parr[@]}"; do
    port="$(echo "$raw" | tr -d ' ')"
    [ -z "$port" ] && continue
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      echo "Invalid port: $port"; return 1
    fi
    exec_line+=" -L=${proto}://:${port}/${dest_fmt}:${port}"
    good=1
  done
  [ "$good" -eq 1 ] || { echo "No valid ports."; return 1; }

  cat > "$svc" <<EOF
[Unit]
Description=Gost Multi-Tunnel ($name -> $dest)
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
  systemctl enable "${GOST_SVC_PREFIX_TCS}${name}" >/dev/null 2>&1
  systemctl restart "${GOST_SVC_PREFIX_TCS}${name}"
  sleep 2

  echo
  if systemctl is-active --quiet "${GOST_SVC_PREFIX_TCS}${name}"; then
    echo "Tunnel '$name' is RUNNING."
    echo "Forwards:"
    for raw in "${parr[@]}"; do
      port="$(echo "$raw" | tr -d ' ')"
      [ -n "$port" ] && echo "   this-server:$port -> $dest:$port ($proto)"
    done
  else
    echo "Tunnel failed to start. Recent logs:"
    journalctl -u "${GOST_SVC_PREFIX_TCS}${name}" -n 15 --no-pager
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo
    echo "ufw is active. Allow your ports, e.g.:"
    for raw in "${parr[@]}"; do
      port="$(echo "$raw" | tr -d ' ')"
      [ -n "$port" ] && echo "   ufw allow $port"
    done
  fi
}

gost_list_tunnels_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnels"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}"*.service)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    echo "No Gost tunnels created yet."
    return 0
  fi
  for f in "${files[@]}"; do
    local base name state dest
    base="$(basename "$f")"
    name="${base#$GOST_SVC_PREFIX_TCS}"; name="${name%.service}"
    state="$(systemctl is-active "$base" 2>/dev/null)"
    dest="$(grep -oP 'Description=Gost Multi-Tunnel \(\K[^)]+' "$f")"
    echo "* $name  [$state]"
    echo "    $dest"
    grep -oP -- '-L=\K[^ ]+' "$f" | sed 's/^/      /'
    echo
  done
}

gost_pick_tunnel_tcs() {
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}"*.service)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    echo "No Gost tunnels found."
    return 1
  fi
  local i=1
  GOST_PICK_NAMES_TCS=()
  echo "Choose a tunnel:"
  for f in "${files[@]}"; do
    local base name
    base="$(basename "$f")"
    name="${base#$GOST_SVC_PREFIX_TCS}"; name="${name%.service}"
    GOST_PICK_NAMES_TCS+=("$name")
    echo "  $i) $name"
    i=$((i+1))
  done
  read -rp "Number: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#GOST_PICK_NAMES_TCS[@]}" ]; then
    echo "Invalid choice."; return 1
  fi
  GOST_PICKED_TCS="${GOST_PICK_NAMES_TCS[$((pick-1))]}"
}

gost_delete_tunnel_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnel: Delete"
  echo "======================================================="
  gost_pick_tunnel_tcs || return 1
  read -rp "Delete '$GOST_PICKED_TCS'? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  systemctl disable --now "${GOST_SVC_PREFIX_TCS}${GOST_PICKED_TCS}" >/dev/null 2>&1
  rm -f "${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}${GOST_PICKED_TCS}.service"
  systemctl daemon-reload
  echo "Tunnel '$GOST_PICKED_TCS' deleted."
}

gost_status_tunnel_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnel: Status / Logs"
  echo "======================================================="
  gost_pick_tunnel_tcs || return 1
  local unit="${GOST_SVC_PREFIX_TCS}${GOST_PICKED_TCS}"
  systemctl status "$unit" --no-pager | head -15
  echo
  echo "Last 20 log lines:"
  journalctl -u "$unit" -n 20 --no-pager
}

gost_restart_all_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnel: Restart All"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}"*.service)
  shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { echo "No Gost tunnels."; return 0; }
  systemctl daemon-reload
  for f in "${files[@]}"; do
    local base; base="$(basename "$f")"
    systemctl restart "$base"
    echo "Restarted $base"
  done
}

gost_uninstall_all_tcs() {
  clear
  echo "======================================================="
  echo " Gost Tunnel: Uninstall ALL"
  echo "======================================================="
  shopt -s nullglob
  local files=("${GOST_SVC_DIR_TCS}/${GOST_SVC_PREFIX_TCS}"*.service)
  shopt -u nullglob
  [ ${#files[@]} -eq 0 ] && { echo "No Gost tunnels to remove."; return 0; }
  read -rp "Remove ALL Gost tunnels (gostm_*)? [y/N]: " c
  case "$c" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled."; return 0 ;; esac
  for f in "${files[@]}"; do
    local base; base="$(basename "$f")"
    systemctl disable --now "$base" >/dev/null 2>&1
    rm -f "$f"
  done
  systemctl daemon-reload
  echo "All Gost tunnels removed."
  read -rp "Also remove gost binary ($GOST_BIN_TCS)? [y/N]: " rb
  case "$rb" in y|Y|yes|YES|Yes) rm -f "$GOST_BIN_TCS"; echo "gost binary removed." ;; esac
}

gost_tunnel_menu_tcs() {
  while true; do
    clear
    echo "======================================================="
    echo " Gost Tunnel Menu"
    echo "======================================================="
    echo "Forward this-server:PORT -> destination:PORT (same port)."
    echo "Each tunnel is its own service (gostm_<name>)."
    echo "======================================================="
    echo " 1) Create tunnel"
    echo " 2) List tunnels"
    echo " 3) Delete tunnel"
    echo " 4) Status / logs of a tunnel"
    echo " 5) Restart all tunnels"
    echo " 6) Uninstall ALL tunnels"
    echo " 0) Back"
    echo "======================================================="
    read -rp "Choose: " GOST_CHOICE
    case "$GOST_CHOICE" in
      1) gost_create_tunnel_tcs;  read -rp "Press Enter to return to Gost menu..." ;;
      2) gost_list_tunnels_tcs;   read -rp "Press Enter to return to Gost menu..." ;;
      3) gost_delete_tunnel_tcs;  read -rp "Press Enter to return to Gost menu..." ;;
      4) gost_status_tunnel_tcs;  read -rp "Press Enter to return to Gost menu..." ;;
      5) gost_restart_all_tcs;    read -rp "Press Enter to return to Gost menu..." ;;
      6) gost_uninstall_all_tcs;  read -rp "Press Enter to return to Gost menu..." ;;
      0) return ;;
      *) echo "Invalid choice."; sleep 1 ;;
    esac
  done
}
GOST_BLOCK_EOF

# ---- 2) Insert the block right before the main "while true; do" loop ----
# Find the LAST "while true; do" line (the main menu loop).
MAIN_LOOP_LINE=$(grep -n '^while true; do' "$TARGET" | tail -1 | cut -d: -f1)
if [ -z "$MAIN_LOOP_LINE" ]; then
  echo "ERROR: Could not locate the main 'while true; do' loop."
  echo "No changes made. Backup is at: $BK"
  rm -f "$GOST_TMP"
  exit 1
fi

# Build the new file: lines before loop + gost block + loop onward
NEW_TMP="$(mktemp)"
head -n $((MAIN_LOOP_LINE - 1)) "$TARGET" > "$NEW_TMP"
cat "$GOST_TMP" >> "$NEW_TMP"
echo "" >> "$NEW_TMP"
tail -n +"$MAIN_LOOP_LINE" "$TARGET" >> "$NEW_TMP"

# ---- 3) Add the menu line "8) Gost Tunnel" before the "0)  Exit" echo ----
# Insert before the line containing the Exit menu entry.
python3 - "$NEW_TMP" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8', errors='ignore').read()

# 3a) Add menu echo line before the Exit echo line.
# Match the actual echo line that prints the "0) ... Exit" menu entry.
# (Guard removed on purpose: the outer script already refuses double-apply.)
exit_echo = re.search(r'(?m)^[ \t]*echo -e "0\).*Exit.*"\s*$', s)
if exit_echo and 'echo -e "8)  \\e[96mGost Tunnel' not in s:
    menu_line = r'  echo -e "8)  \e[96mGost Tunnel\e[0m"'
    s = s[:exit_echo.start()] + menu_line + "\n" + s[exit_echo.start():]
    print("Menu line inserted.")
else:
    print("WARNING: could not insert menu line (pattern not found).")

# 3b) Add case handler "8)" before the "0)" case in the MAIN case block.
# Target the main loop's case branch: '  0)\n    clear\n    echo "Exiting."'
m = re.search(r'(?m)^([ \t]*)0\)\s*\n[ \t]*clear\s*\n[ \t]*echo "Exiting\."', s)
if m and re.search(r'(?m)^[ \t]*8\)\s*\n[ \t]*clear\s*\n[ \t]*gost_tunnel_menu_tcs', s) is None:
    indent = m.group(1)
    case_block = (
        f'{indent}8)\n'
        f'{indent}  clear\n'
        f'{indent}  gost_tunnel_menu_tcs\n'
        f'{indent}  ;;\n'
    )
    s = s[:m.start()] + case_block + s[m.start():]
    print("Case handler inserted.")
else:
    print("WARNING: could not insert case handler (pattern not found).")

open(p, 'w', encoding='utf-8').write(s)
PY

# ---- 4) Validate syntax, then replace original ----
if bash -n "$NEW_TMP"; then
  cp -a "$NEW_TMP" "$TARGET"
  echo
  echo "SUCCESS: 'Gost Tunnel' added as menu option 8."
  echo "Backup of original: $BK"
  echo "Run your script again to see it."
else
  echo
  echo "ERROR: The patched script failed syntax check. Original NOT changed."
  echo "Backup is safe at: $BK"
  echo "Broken candidate kept at: $NEW_TMP"
  rm -f "$GOST_TMP"
  exit 1
fi

rm -f "$GOST_TMP" "$NEW_TMP"
