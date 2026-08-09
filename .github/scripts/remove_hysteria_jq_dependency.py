from pathlib import Path

p = Path('GECKO.sh')
s = p.read_text()

old = r'''  command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; return 1; }
  release_data="$(
    curl -fsSL --retry 3 --connect-timeout 15 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -H 'Cache-Control: no-cache' \
      -H 'User-Agent: GECKO-Hysteria-updater' \
      'https://api.github.com/repos/apernet/hysteria/releases?per_page=20' |
    jq -r --arg asset "hysteria-linux-${arch}" '
      [
        .[]
        | select(.draft == false and .prerelease == false)
        | select(.tag_name | startswith("app/v"))
        | . as $release
        | $release.assets[]?
        | select(.name == $asset)
        | {
            published_at: $release.published_at,
            tag: $release.tag_name,
            url: .browser_download_url,
            digest: (.digest // "")
          }
      ]
      | sort_by(.published_at)
      | reverse
      | first
      | select(. != null)
      | [.tag, .url, .digest]
      | @tsv
    '
  )" || return 1
'''

new = r'''  if ! command -v python3 >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1 && apt-get install -y python3 >/dev/null 2>&1 || {
        echo "python3 is required to query Hysteria releases." >&2
        return 1
      }
    else
      echo "python3 is required to query Hysteria releases." >&2
      return 1
    fi
  fi

  release_data="$(
    curl -fsSL --retry 3 --connect-timeout 15 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -H 'Cache-Control: no-cache' \
      -H 'User-Agent: GECKO-Hysteria-updater' \
      'https://api.github.com/repos/apernet/hysteria/releases?per_page=20' |
    python3 -c '
import json, sys
arch = sys.argv[1]
asset_name = "hysteria-linux-" + arch
try:
    releases = json.load(sys.stdin)
except Exception:
    sys.exit(1)

matches = []
for release in releases:
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not tag.startswith("app/v"):
        continue
    for asset in release.get("assets", []):
        if asset.get("name") == asset_name:
            matches.append((
                release.get("published_at", ""),
                tag,
                asset.get("browser_download_url", ""),
                asset.get("digest") or "",
            ))
            break

if not matches:
    sys.exit(2)
matches.sort(key=lambda x: x[0], reverse=True)
_, tag, url, digest = matches[0]
print("\t".join((tag, url, digest)))
' "$arch"
  )" || return 1
'''

if old not in s:
    raise SystemExit('jq-based Hysteria release block not found')

s = s.replace(old, new, 1)
p.write_text(s)
