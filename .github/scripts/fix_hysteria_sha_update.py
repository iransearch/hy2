from pathlib import Path

p = Path('GECKO.sh')
s = p.read_text()

old_core = '''hysteria_core_version() {
  local bin="/usr/local/bin/hysteria"
  if [[ ! -x "$bin" ]]; then
    echo "not-installed"
    return 0
  fi
  hysteria_version_from_binary "$bin" 2>/dev/null || echo "unknown"
}
'''
new_core = '''HYSTERIA_CORE_VERSION_FILE="/var/lib/gecko/hysteria-core-version"

hysteria_core_version() {
  local bin="/usr/local/bin/hysteria" version
  if [[ ! -x "$bin" ]]; then
    echo "not-installed"
    return 0
  fi
  version="$(hysteria_version_from_binary "$bin" 2>/dev/null || true)"
  if [[ -n "$version" ]]; then
    echo "$version"
    return 0
  fi
  if [[ -s "$HYSTERIA_CORE_VERSION_FILE" ]]; then
    head -n 1 "$HYSTERIA_CORE_VERSION_FILE"
    return 0
  fi
  echo "unknown"
}

hysteria_record_core_version() {
  local version="$1"
  [[ "$version" =~ ^v[0-9]+\\.[0-9]+\\.[0-9]+$ ]] || return 1
  install -d -m 0755 /var/lib/gecko || return 1
  printf '%s\\n' "$version" > "$HYSTERIA_CORE_VERSION_FILE" || return 1
  chmod 0644 "$HYSTERIA_CORE_VERSION_FILE" 2>/dev/null || true
}
'''
if old_core not in s:
    raise SystemExit('core version block not found')
s = s.replace(old_core, new_core, 1)

old_locals = '  local tmp_dir new_bin backup_bin expected_sha actual_sha downloaded_version\n  local was_active="false"\n'
new_locals = '  local tmp_dir new_bin backup_bin expected_sha actual_sha downloaded_version current_sha\n  local digest_verified="false" was_active="false"\n'
if old_locals not in s:
    raise SystemExit('update locals not found')
s = s.replace(old_locals, new_locals, 1)

old_after_latest = '''  if [[ "$current" == "$latest" ]]; then
    echo "Already latest. No files were changed."
    return 0
  fi

  tmp_dir="$(mktemp -d /tmp/gecko-hysteria-core.XXXXXX)" || return 1
'''
new_after_latest = '''  if [[ "$current" == "$latest" ]]; then
    echo "Already latest. No files were changed."
    return 0
  fi

  if [[ "$digest" =~ ^sha256:([0-9A-Fa-f]{64})$ ]]; then
    expected_sha="${BASH_REMATCH[1],,}"
    current_sha="$(sha256sum "$bin" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$current_sha" && "$current_sha" == "$expected_sha" ]]; then
      hysteria_record_core_version "$latest" || true
      echo "Installed binary SHA-256 already matches $latest."
      echo "Core version recorded as: $latest"
      return 0
    fi
  fi

  tmp_dir="$(mktemp -d /tmp/gecko-hysteria-core.XXXXXX)" || return 1
'''
if old_after_latest not in s:
    raise SystemExit('post latest block not found')
s = s.replace(old_after_latest, new_after_latest, 1)

old_verify = '''  if [[ "$digest" =~ ^sha256:([0-9A-Fa-f]{64})$ ]]; then
    expected_sha="${BASH_REMATCH[1],,}"
    actual_sha="$(sha256sum "$new_bin" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -rf "$tmp_dir"
      echo "SHA-256 verification failed. Existing installation is unchanged."
      return 1
    fi
    echo "SHA-256 verified."
  fi

  downloaded_version="$(hysteria_version_from_binary "$new_bin" 2>/dev/null || true)"
  if [[ "$downloaded_version" != "$latest" ]]; then
    rm -rf "$tmp_dir"
    echo "Downloaded binary version check failed (got: ${downloaded_version:-unknown}, expected: $latest). Existing installation is unchanged."
    return 1
  fi
'''
new_verify = '''  if [[ "$digest" =~ ^sha256:([0-9A-Fa-f]{64})$ ]]; then
    expected_sha="${BASH_REMATCH[1],,}"
    actual_sha="$(sha256sum "$new_bin" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -rf "$tmp_dir"
      echo "SHA-256 verification failed. Existing installation is unchanged."
      return 1
    fi
    digest_verified="true"
    echo "SHA-256 verified."
  fi

  downloaded_version="$(hysteria_version_from_binary "$new_bin" 2>/dev/null || true)"
  if [[ -n "$downloaded_version" && "$downloaded_version" != "$latest" ]]; then
    rm -rf "$tmp_dir"
    echo "Downloaded binary reports $downloaded_version but release metadata says $latest. Existing installation is unchanged."
    return 1
  fi
  if [[ -z "$downloaded_version" && "$digest_verified" != "true" ]]; then
    rm -rf "$tmp_dir"
    echo "Could not verify downloaded core version and GitHub did not provide a SHA-256 digest. Existing installation is unchanged."
    return 1
  fi
  if [[ -z "$downloaded_version" ]]; then
    echo "Version command is not parseable on this server; trusted official SHA-256 verification instead."
  fi
'''
if old_verify not in s:
    raise SystemExit('download verify block not found')
s = s.replace(old_verify, new_verify, 1)

old_success = '''  gecko_configure_hysteria_service_logging >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
  echo "Update successful."
  echo "Core Before: $current"
  echo "Core After : $(hysteria_core_version)"
  echo "Config/accounts preserved: /etc/hysteria2 was not modified."
'''
new_success = '''  hysteria_record_core_version "$latest" || true
  gecko_configure_hysteria_service_logging >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
  echo "Update successful."
  echo "Core Before: $current"
  echo "Core After : $(hysteria_core_version)"
  echo "Config/accounts preserved: /etc/hysteria2 was not modified."
'''
if old_success not in s:
    raise SystemExit('success block not found')
s = s.replace(old_success, new_success, 1)

p.write_text(s)
