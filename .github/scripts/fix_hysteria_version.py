from pathlib import Path

p = Path('GECKO.sh')
s = p.read_text()

old_func = '''hysteria_core_version() {
  local bin="/usr/local/bin/hysteria" out
  if [[ ! -x "$bin" ]]; then
    echo "not-installed"
    return 0
  fi
  out="$("$bin" version 2>/dev/null | head -n 1)"
  if [[ "$out" =~ v?([0-9]+\\.[0-9]+\\.[0-9]+) ]]; then
    echo "v${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}
'''

new_func = '''hysteria_version_from_binary() {
  local bin="$1" out version
  [[ -x "$bin" ]] || return 1

  out="$("$bin" version 2>&1 || true)"
  if [[ ! "$out" =~ [vV]?([0-9]+\\.[0-9]+\\.[0-9]+) ]]; then
    out="$("$bin" -v 2>&1 || true)"
  fi
  if [[ "$out" =~ [vV]?([0-9]+\\.[0-9]+\\.[0-9]+) ]]; then
    version="${BASH_REMATCH[1]}"
    printf 'v%s\\n' "$version"
    return 0
  fi
  return 1
}

hysteria_core_version() {
  local bin="/usr/local/bin/hysteria"
  if [[ ! -x "$bin" ]]; then
    echo "not-installed"
    return 0
  fi
  hysteria_version_from_binary "$bin" 2>/dev/null || echo "unknown"
}
'''

if old_func not in s:
    raise SystemExit('old hysteria_core_version function not found')
s = s.replace(old_func, new_func, 1)

old_check = '''  downloaded_version="$("$new_bin" version 2>/dev/null | head -n 1)"
  if [[ ! "$downloaded_version" =~ ${latest#v} ]]; then
    rm -rf "$tmp_dir"
    echo "Downloaded binary version check failed. Existing installation is unchanged."
    return 1
  fi
'''

new_check = '''  downloaded_version="$(hysteria_version_from_binary "$new_bin" 2>/dev/null || true)"
  if [[ "$downloaded_version" != "$latest" ]]; then
    rm -rf "$tmp_dir"
    echo "Downloaded binary version check failed (got: ${downloaded_version:-unknown}, expected: $latest). Existing installation is unchanged."
    return 1
  fi
'''

if old_check not in s:
    raise SystemExit('old downloaded version check not found')
s = s.replace(old_check, new_check, 1)

p.write_text(s)
