# Reality + XHTTP TLS pairs (menu 14)

Creates an isolated Xray service per named pair, with shared users and two client
profiles. Other Reality, XHTTP and AnyTLS instances are retained.

## Actual forwarding mechanism

The public listener is VLESS/TCP/Reality (default 443). Authenticated Reality
connections terminate there. Ordinary TLS handshakes are passed, still encrypted,
through `realitySettings.target` to `127.0.0.1:<backend_port>` (default 2096).
That listener is VLESS/XHTTP/TLS, using a certificate for the same domain/SNI.
Both generated links use the public port. The backend is never publicly bound.

This deliberately does **not** copy XUI's `settings.fallbacks` screen:
VLESS fallback forwards decrypted bytes and cannot directly feed a TLS listener.
Furthermore, Xray performs VLESS Encryption's handshake before VLESS fallback.
The REALITY target forwarding mechanism works with optional VLESS Encryption on
both profiles. It is server-side sharing, not automatic client failover.

References:
- https://xtls.github.io/en/config/transports/reality.html
- https://github.com/XTLS/Xray-core/blob/main/proxy/vless/inbound/inbound.go

## Setup

1. Run the updated GECKO script as root and choose **14 -> 1**.
2. Choose a pair name, server IP/domain, TLS domain, public port, internal port,
   XHTTP path and `none` or `mlkem768` encryption.
3. Supply an existing full-chain PEM and matching private key under `/etc`, or
   select `letsencrypt` (requires certbot, direct DNS and an available TCP port 80).
   The script does not stop unrelated web servers to acquire a certificate.
4. Enter the first username. Both links are printed after validation and startup.

Public trust, certificate expiry, hostname and key matching are checked. There
is no insecure TLS option. Cloudflare Origin CA and self-signed certificates
are not accepted for this direct-TLS setup. Certificate paths stay external, so
renewed files are read on restart; a certbot deploy hook restarts active pairs
using the renewed lineage. Existing-certificate renewers other than certbot
must restart the associated service themselves.

Ports are selectable and reserved even while the pair is stopped. The private
Reality key and Short ID are generated automatically. The SNI is the TLS domain,
not an unrelated camouflage domain. Reality uses empty flow, matching the
supplied sample. XHTTP uses auto mode with HTTP/2 and HTTP/1.1 ALPN.

When enabled, VLESS Encryption uses independent generated key pairs for the two
inbounds. It requires supporting Xray clients. Turning it on/off changes both
client links, which must be imported again.

## Management and files

Menu 14 supports create, edit, add/remove user, show links, status/logs,
start/stop/restart, core update and deletion. Each user's UUID is shared between
the two profiles; deleting the user removes both client exports. At least one
user must remain. Delete the pair to remove the last user and service.

- Service: `gecko-rx-<pair>.service`
- Core: `/usr/bin/gecko-rx-<pair>`
- Server and metadata: `/etc/gecko-reality-xhttp/<pair>/`
- Links: `links.txt`
- Client JSONs: `<user>-reality.json` and `<user>-xhttp.json`

Each client JSON is a separate profile exposing local SOCKS on 127.0.0.1:10808.
They should not be launched simultaneously without changing their local ports.
Private metadata, links and client profiles are created with restrictive modes.
Deletion keeps external certificates. Configuration edits validate both server
and client JSON before replacement, restore previous files after startup
failure, and preserve stopped services. Core updates also restore the previous
binary on validation/startup failure.

Pairs participate in menu 6 WARP selective/all/disabled routing and its rollback.
Only client proxy traffic is routed; the local TLS target remains local.

## Validation

Run with a downloaded official Xray core:

```bash
XRAY_BINARY=/path/to/xray python3 tests/test_reality_xhttp.py
bash -n GECKO.sh
```

Tested with official Xray **26.3.27** (release archive SHA-256 verified).
The integration test uses an isolated, temporarily trusted test CA without
changing the host trust store. It transfers actual HTTP content through both
profiles in both encryption modes. It also tests hostname rejection, IPv6 URI
encoding, WARP configurations, activation rollback, stopped-service preservation
and stale user export removal. Systemd lifecycle failures are simulated; actual
installation, certificate issuance and remote-network reachability require the
deployment server. No production credentials from the uploaded examples are
used or included.
